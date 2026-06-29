-- Idempotent: complete remaining schema to match database.types.ts

-- ============ ENUMS ============
DO $$ BEGIN CREATE TYPE public.case_status AS ENUM ('open','in_study','closed_final','closed_non_final','appealed','archived'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.case_type AS ENUM ('labor','commercial','execution','civil','personal_status','administrative','criminal','other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.document_type AS ENUM ('lawsuit','judgment_final','judgment_non_final','appeal_judgment','memorandum_reply','session_minutes','power_of_attorney','evidence','other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.execution_status AS ENUM ('pending','in_progress','completed','rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.notification_channel AS ENUM ('whatsapp','sms','email'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.notification_status AS ENUM ('draft','scheduled','sent','failed','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.session_status AS ENUM ('scheduled','held','postponed','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.task_priority AS ENUM ('low','medium','high','urgent'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.task_status AS ENUM ('todo','in_progress','done','overdue'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.wakalah_status AS ENUM ('active','expired','revoked'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ extra column on employees ============
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS portal_access_code TEXT;

-- ============ has_role: fix argument order to (_role, _user_id) ============
DROP FUNCTION IF EXISTS public.has_role(uuid, public.app_role);
DROP FUNCTION IF EXISTS public.has_role(public.app_role, uuid);
CREATE OR REPLACE FUNCTION public.has_role(_role public.app_role, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;
REVOKE EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) TO authenticated, service_role;

-- ============ clients ============
CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL,
  national_id TEXT, email TEXT, phone TEXT, address TEXT, notes TEXT,
  portal_access_code TEXT,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "portal user reads own client" ON public.clients;
CREATE POLICY "portal user reads own client" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_upd ON public.clients;
CREATE TRIGGER trg_clients_upd BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ cases ============
CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_number TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  case_type public.case_type NOT NULL DEFAULT 'other',
  status public.case_status NOT NULL DEFAULT 'open',
  court TEXT, circuit_number TEXT,
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_cases_upd ON public.cases;
CREATE TRIGGER trg_cases_upd BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Now helper SECURITY DEFINER functions (after cases/clients exist)
CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id UUID, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cases c
    JOIN public.employees e ON e.owner_id = c.owner_id
    WHERE c.id = _case_id AND e.user_id = _user_id
      AND (e.assigned_cases IS NULL OR e.assigned_cases = '{}' OR c.id = ANY(e.assigned_cases))
  );
$$;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id UUID, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.clients cl
    JOIN public.employees e ON e.owner_id = cl.owner_id
    WHERE cl.id = _client_id AND e.user_id = _user_id
      AND (e.assigned_clients IS NULL OR e.assigned_clients = '{}' OR cl.id = ANY(e.assigned_clients))
  );
$$;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;

-- ============ sessions ============
CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL,
  court TEXT, room TEXT, notes TEXT, outcome TEXT,
  status public.session_status NOT NULL DEFAULT 'scheduled',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_sessions_upd ON public.sessions;
CREATE TRIGGER trg_sessions_upd BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.session_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lead_hours INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_at TIMESTAMPTZ, error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
CREATE POLICY "owner manage session_reminders" ON public.session_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ============ tasks ============
CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT,
  status public.task_status NOT NULL DEFAULT 'todo',
  priority public.task_priority NOT NULL DEFAULT 'medium',
  due_date TIMESTAMPTZ, completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_tasks_upd ON public.tasks;
CREATE TRIGGER trg_tasks_upd BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.task_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_at TIMESTAMPTZ, error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
CREATE POLICY "owner manage task_reminders" ON public.task_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ============ documents ============
CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT,
  doc_type public.document_type NOT NULL DEFAULT 'other',
  file_name TEXT, file_size BIGINT, mime_type TEXT, storage_path TEXT,
  court TEXT, circuit_number TEXT,
  filed_date DATE, judgment_date DATE, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_documents_upd ON public.documents;
CREATE TRIGGER trg_documents_upd BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  permission public.doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage doc_perm" ON public.document_permissions;
CREATE POLICY "owner manage doc_perm" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "user reads own doc_perm" ON public.document_permissions;
CREATE POLICY "user reads own doc_perm" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id UUID, _perm public.doc_permission, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.document_permissions dp
    WHERE dp.user_id = _user_id
      AND (dp.case_id IS NULL OR dp.case_id = _case_id)
      AND (dp.permission = _perm OR dp.permission = 'manage')
  );
$$;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) TO authenticated, service_role;

-- ============ executions ============
CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL,
  debtor_name TEXT, court TEXT, amount NUMERIC, notes TEXT,
  status public.execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_upd ON public.executions;
CREATE TRIGGER trg_executions_upd BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ powers_of_attorney ============
CREATE TABLE IF NOT EXISTS public.powers_of_attorney (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  wakalah_number TEXT NOT NULL,
  agent_name TEXT, issuer_name TEXT, scope TEXT, notes TEXT,
  status public.wakalah_status NOT NULL DEFAULT 'active',
  issue_date DATE, expiry_date DATE,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_poa_owner ON public.powers_of_attorney(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage poa" ON public.powers_of_attorney;
CREATE POLICY "owner manage poa" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_poa_upd ON public.powers_of_attorney;
CREATE TRIGGER trg_poa_upd BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ client_notifications ============
CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  channel public.notification_channel NOT NULL DEFAULT 'whatsapp',
  template TEXT, message TEXT NOT NULL,
  status public.notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage client_notif" ON public.client_notifications;
CREATE POLICY "owner manage client_notif" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_client_notif_upd ON public.client_notifications;
CREATE TRIGGER trg_client_notif_upd BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ portal_messages ============
CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE SET NULL,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL,
  subject TEXT, message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal_messages" ON public.portal_messages;
CREATE POLICY "owner manage portal_messages" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "portal user reads own messages" ON public.portal_messages;
CREATE POLICY "portal user reads own messages" ON public.portal_messages FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.clients c WHERE c.id = portal_messages.client_id AND c.portal_user_id = auth.uid()));

-- ============ notifications & preferences ============
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  office_id UUID,
  title TEXT NOT NULL, message TEXT, category TEXT, link TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own notifications" ON public.notifications;
CREATE POLICY "users manage own notifications" ON public.notifications FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  channels JSONB NOT NULL DEFAULT '{}'::jsonb,
  quiet_hours JSONB NOT NULL DEFAULT '{}'::jsonb,
  sessions JSONB NOT NULL DEFAULT '{}'::jsonb,
  tasks JSONB NOT NULL DEFAULT '{}'::jsonb,
  appeals JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notif_prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif_prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ============ audit_log (singular - new) & audit_logs (plural - legacy) ============
CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  entity_type TEXT NOT NULL, entity_id UUID,
  action TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT, user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_log_owner ON public.audit_log(owner_id, created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id OR auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID, actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  entity TEXT, entity_id UUID, action TEXT NOT NULL,
  details JSONB, ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.audit_logs TO authenticated;
GRANT ALL ON public.audit_logs TO service_role;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "actor reads audit_logs" ON public.audit_logs;
CREATE POLICY "actor reads audit_logs" ON public.audit_logs FOR SELECT TO authenticated USING (auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit_logs" ON public.audit_logs;
CREATE POLICY "actor inserts audit_logs" ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

-- ============ saved_filters ============
CREATE TABLE IF NOT EXISTS public.saved_filters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, name TEXT NOT NULL,
  filters JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ============ secure_secrets ============
CREATE TABLE IF NOT EXISTS public.secure_secrets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, key TEXT NOT NULL,
  ciphertext TEXT NOT NULL, iv TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, key)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.secure_secrets TO authenticated;
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage secrets" ON public.secure_secrets;
CREATE POLICY "owner manage secrets" ON public.secure_secrets FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ============ user_preferences ============
CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  sidebar_width INTEGER NOT NULL DEFAULT 280,
  sidebar_collapsed BOOLEAN NOT NULL DEFAULT FALSE,
  dashboard_cards JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;
GRANT ALL ON public.user_preferences TO service_role;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own prefs" ON public.user_preferences;
CREATE POLICY "users manage own prefs" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============ link_current_user_to_portal ============
CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_access_code TEXT DEFAULT NULL, _account_type TEXT DEFAULT 'client')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid UUID := auth.uid(); _rows INTEGER := 0;
BEGIN
  IF _uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthenticated'); END IF;
  IF _access_code IS NULL OR length(btrim(_access_code)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_code');
  END IF;
  IF _account_type = 'employee' THEN
    UPDATE public.employees SET user_id = _uid
      WHERE portal_access_code = _access_code AND user_id IS NULL;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  ELSE
    UPDATE public.clients SET portal_user_id = _uid
      WHERE portal_access_code = _access_code AND portal_user_id IS NULL;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  END IF;
  RETURN jsonb_build_object('ok', _rows > 0, 'linked', _rows);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;

-- ============ stub queue functions ============
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders() RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0; $$;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders() RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0; $$;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status() RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT '[]'::jsonb; $$;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

-- ============ tighten previous SECURITY DEFINER (from prior migration) ============
DO $$ BEGIN
  REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
EXCEPTION WHEN undefined_function THEN NULL; END $$;

-- Enable Realtime for notifications too
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;

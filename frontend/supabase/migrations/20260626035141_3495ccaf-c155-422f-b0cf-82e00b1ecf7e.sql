DO $$ BEGIN CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  email TEXT,
  phone TEXT,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL,
  national_id TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  notes TEXT,
  portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL,
  title TEXT NOT NULL,
  court TEXT,
  circuit_number TEXT,
  case_type public.case_type NOT NULL DEFAULT 'other',
  status public.case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE,
  closed_at DATE,
  description TEXT,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL,
  court TEXT,
  room TEXT,
  status public.session_status NOT NULL DEFAULT 'scheduled',
  notes TEXT,
  outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type public.document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL,
  description TEXT,
  storage_path TEXT,
  file_name TEXT,
  file_size BIGINT,
  mime_type TEXT,
  filed_date DATE,
  judgment_date DATE,
  court TEXT,
  circuit_number TEXT,
  appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_appeal_deadline()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.doc_type = 'judgment_non_final' AND NEW.judgment_date IS NOT NULL THEN
    NEW.appeal_deadline := NEW.judgment_date + INTERVAL '30 days';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_documents_appeal ON public.documents;
CREATE TRIGGER trg_documents_appeal BEFORE INSERT OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.set_appeal_deadline();

CREATE TABLE IF NOT EXISTS public.powers_of_attorney (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  wakalah_number TEXT NOT NULL,
  issuer_name TEXT,
  agent_name TEXT,
  issue_date DATE,
  expiry_date DATE,
  scope TEXT,
  status public.wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL,
  court TEXT,
  amount NUMERIC(14,2),
  debtor_name TEXT,
  status public.execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL,
  nationality TEXT,
  national_id TEXT,
  phone TEXT,
  email TEXT,
  residence_expiry DATE,
  job_title TEXT,
  qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE,
  end_date DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cases DROP CONSTRAINT IF EXISTS cases_assigned_employee_id_fkey;
ALTER TABLE public.cases ADD CONSTRAINT cases_assigned_employee_id_fkey FOREIGN KEY (assigned_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  due_date DATE,
  status public.task_status NOT NULL DEFAULT 'todo',
  priority public.task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT,
  message TEXT NOT NULL,
  channel public.notification_channel NOT NULL DEFAULT 'whatsapp',
  status public.notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer', 'employee')),
  sender_id UUID,
  subject TEXT,
  message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  status TEXT NOT NULL,
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  raw_payload JSONB,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT, UPDATE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT,
  last_used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  sidebar_width INTEGER NOT NULL DEFAULT 288,
  sidebar_collapsed BOOLEAN NOT NULL DEFAULT false,
  dashboard_cards JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;
GRANT ALL ON public.user_preferences TO service_role;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.saved_filters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  name TEXT NOT NULL,
  filters JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, name)
);
CREATE INDEX IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  sessions JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,48]}'::jsonb,
  tasks JSONB NOT NULL DEFAULT '{"toast":true,"email":false,"lead_hours":[24]}'::jsonb,
  appeals JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,72]}'::jsonb,
  channels JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"whatsapp":false,"sms":false}'::jsonb,
  quiet_hours JSONB NOT NULL DEFAULT '{"enabled":false,"start":"22:00","end":"07:00"}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission public.doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, user_id, permission)
);
CREATE INDEX IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id uuid, _user_id uuid, _perm public.doc_permission)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.cases c WHERE c.id = _case_id AND c.owner_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.document_permissions dp WHERE dp.case_id = _case_id AND dp.user_id = _user_id AND (dp.permission = _perm OR dp.permission = 'manage'));
$$;

CREATE TABLE IF NOT EXISTS public.secure_secrets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  key TEXT NOT NULL,
  ciphertext TEXT NOT NULL,
  iv TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, key)
);
CREATE INDEX IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.session_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lead_hours INT NOT NULL,
  sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, lead_hours)
);
CREATE INDEX IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
GRANT SELECT ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = c.owner_id
      AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])) OR c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
  );
$$;

CREATE OR REPLACE FUNCTION private.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = cl.owner_id
      AND (_client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])) OR EXISTS (SELECT 1 FROM public.cases c WHERE c.client_id = _client_id AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))))
  );
$$;

CREATE OR REPLACE FUNCTION private.has_doc_permission(_case_id uuid, _user_id uuid, _perm public.doc_permission)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.cases c WHERE c.id = _case_id AND c.owner_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.document_permissions dp WHERE dp.case_id = _case_id AND dp.user_id = _user_id AND (dp.permission = _perm OR dp.permission = 'manage'));
$$;
GRANT EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_client(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE(np.sessions->'lead_hours', '[24,48]'::jsonb) AS lead_hours
    FROM public.notification_preferences np
  ), expanded AS (
    SELECT s.id AS session_id, s.owner_id, s.session_date, (lh::text)::int AS lead_hours
    FROM public.sessions s
    LEFT JOIN prefs p ON p.owner_id = s.owner_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.lead_hours, '[24,48]'::jsonb)) AS lh
    WHERE s.status = 'scheduled' AND s.session_date > now()
  ), to_insert AS (
    SELECT e.owner_id, e.session_id, e.lead_hours
    FROM expanded e
    WHERE e.session_date - (e.lead_hours || ' hours')::interval <= now() + interval '15 minutes'
      AND e.session_date - (e.lead_hours || ' hours')::interval > now() - interval '1 hour'
  )
  INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
  SELECT owner_id, session_id, lead_hours FROM to_insert
  ON CONFLICT (session_id, lead_hours) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_account_type text DEFAULT NULL, _access_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  user_email text;
  acct text := lower(coalesce(_account_type, ''));
  code text := nullif(trim(coalesce(_access_code, '')), '');
  linked_id uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT email INTO user_email FROM auth.users WHERE id = uid;
  IF acct NOT IN ('client', 'employee') THEN
    SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1;
    IF linked_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
      DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
      RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
    END IF;
    SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1;
    IF linked_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
      DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
      RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked_id);
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'lawyer') ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('linked', true, 'role', 'lawyer');
  END IF;
  IF acct = 'client' THEN
    UPDATE public.clients c SET portal_user_id = uid
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC LIMIT 1
    ) RETURNING c.id INTO linked_id;
    IF linked_id IS NULL THEN SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1; END IF;
    IF linked_id IS NULL THEN RETURN jsonb_build_object('linked', false, 'role', 'client', 'reason', 'client_not_found'); END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
  END IF;
  IF acct = 'employee' THEN
    UPDATE public.employees e SET user_id = uid
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC LIMIT 1
    ) RETURNING e.id INTO linked_id;
    IF linked_id IS NULL THEN SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1; END IF;
    IF linked_id IS NULL THEN RETURN jsonb_build_object('linked', false, 'role', 'employee', 'reason', 'employee_not_found'); END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked_id);
  END IF;
  RETURN jsonb_build_object('linked', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  acct text := lower(coalesce(NEW.raw_user_meta_data->>'account_type', 'lawyer'));
  code text := nullif(trim(coalesce(NEW.raw_user_meta_data->>'portal_access_code', '')), '');
  linked_id uuid;
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email)
  ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, email = EXCLUDED.email;

  IF acct = 'client' THEN
    UPDATE public.clients c SET portal_user_id = NEW.id
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC LIMIT 1
    ) RETURNING c.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'client') ON CONFLICT DO NOTHING;
  ELSIF acct = 'employee' THEN
    UPDATE public.employees e SET user_id = NEW.id
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC LIMIT 1
    ) RETURNING e.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'employee') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer') ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (private.employee_can_access_client(id, auth.uid()));
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (private.employee_can_access_case(id, auth.uid()));
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (private.employee_can_access_case(case_id, auth.uid()));
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (private.employee_can_access_case(case_id, auth.uid()) OR private.has_doc_permission(case_id, auth.uid(), 'view')));
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid()));
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "client reads own case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d JOIN public.cases c ON c.id = d.case_id JOIN public.clients cl ON cl.id = c.client_id
    WHERE d.storage_path = storage.objects.name AND cl.portal_user_id = auth.uid()
  ));
CREATE POLICY "employee reads assigned case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    WHERE d.storage_path = storage.objects.name AND d.case_id IS NOT NULL AND private.employee_can_access_case(d.case_id, auth.uid())
  ));

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.cases; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.documents; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO service_role;
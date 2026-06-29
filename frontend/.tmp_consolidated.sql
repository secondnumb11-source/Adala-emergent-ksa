
-- ===== 20260625170017_584deceb-1f3e-4cb4-a40f-b763f2be946f.sql =====

DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
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
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

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
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL,
  title TEXT NOT NULL,
  court TEXT,
  circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other',
  status case_status NOT NULL DEFAULT 'open',
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
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL,
  court TEXT,
  room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled',
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
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
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
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL,
  court TEXT,
  amount NUMERIC(14,2),
  debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT,
  message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID,
  subject TEXT,
  message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated
  USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
  WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension',
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  error_message TEXT,
  raw_payload JSONB,
  trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;

DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'case-documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      JOIN public.cases c ON c.id = d.case_id
      JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = storage.objects.name
        AND cl.portal_user_id = auth.uid()
    )
  );

-- ===== 20260625170044_08fead0b-e7d9-42e3-9850-b7089056ad38.sql =====
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM authenticated;
-- ===== 20260625170827_a94d452e-aa8f-4d1d-aedb-94eb96a8bde1.sql =====
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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20260625175241_413db816-f3b9-4ae1-8618-1d4923475637.sql =====
DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
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
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

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
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL,
  title TEXT NOT NULL,
  court TEXT,
  circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other',
  status case_status NOT NULL DEFAULT 'open',
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
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL,
  court TEXT,
  room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled',
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
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
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
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL,
  court TEXT,
  amount NUMERIC(14,2),
  debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT,
  message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID,
  subject TEXT,
  message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated
  USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
  WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension',
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  error_message TEXT,
  raw_payload JSONB,
  trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO service_role;

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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'case-documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      JOIN public.cases c ON c.id = d.case_id
      JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = storage.objects.name
        AND cl.portal_user_id = auth.uid()
    )
  );
-- ===== 20260625182656_1e02da94-eb45-4ae3-b4e7-eb88e9f8695b.sql =====
DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other', status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE, description TEXT,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled', notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT,
  storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending', filed_date DATE,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT,
  residence_expiry DATE, job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status task_status NOT NULL DEFAULT 'todo', priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension', kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0, inserted_count INTEGER DEFAULT 0, updated_count INTEGER DEFAULT 0,
  error_message TEXT, raw_payload JSONB, trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE, label TEXT,
  last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO service_role;

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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20260625182724_a37a9673-5fa1-46da-a848-f5f1b722fadf.sql =====
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    JOIN public.cases c ON c.id = d.case_id
    JOIN public.clients cl ON cl.id = c.client_id
    WHERE d.storage_path = storage.objects.name AND cl.portal_user_id = auth.uid()
  ));
-- ===== 20260625192509_9dbc2b1c-7700-4886-8501-cbb666de11fe.sql =====
DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other', status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE, description TEXT,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled', notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT,
  storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending', filed_date DATE,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT,
  residence_expiry DATE, job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

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
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT, last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;
-- ===== 20260625192608_49ab4e07-23c6-4d71-a785-70abad4b646a.sql =====
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    JOIN public.cases c ON c.id = d.case_id
    JOIN public.clients cl ON cl.id = c.client_id
    WHERE d.storage_path = storage.objects.name AND cl.portal_user_id = auth.uid()
  ));
-- ===== 20260625193425_2abbd151-44c9-419e-a3f0-bed1ef7f35d1.sql =====
ALTER PUBLICATION supabase_realtime ADD TABLE public.cases;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.documents;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;
-- ===== 20260625213134_c26de1bb-85f8-43a9-97b6-655f74eb2bac.sql =====
DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other', status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE, description TEXT,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled', notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT,
  storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending', filed_date DATE,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT,
  residence_expiry DATE, job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

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
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT, last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;

DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    JOIN public.cases c ON c.id = d.case_id
    JOIN public.clients cl ON cl.id = c.client_id
    WHERE d.storage_path = storage.objects.name AND cl.portal_user_id = auth.uid()
  ));

ALTER PUBLICATION supabase_realtime ADD TABLE public.cases;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.documents;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;

-- ============================================================
-- Phase 2/3 additions: audit_log, saved_filters, notification_preferences,
-- document_permissions, secure_secrets, session_reminders + pg_cron
-- ============================================================
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, user_id, permission)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id uuid, _user_id uuid, _perm doc_permission)
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
GRANT SELECT ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[7, 24, 48] LOOP
    WITH due AS (
      SELECT s.id AS session_id, s.owner_id, lead_h AS lh FROM public.sessions s
      WHERE s.status = 'scheduled'
        AND s.session_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                              AND  now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
    SELECT owner_id, session_id, lh FROM due
    ON CONFLICT (session_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END $$;

DO $$ BEGIN PERFORM cron.unschedule('enqueue-session-reminders');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

SELECT cron.schedule(
  'enqueue-session-reminders',
  '*/15 * * * *',
  $$ SELECT public.enqueue_session_reminders(); $$
);
-- ===== 20260625213150_cb4e2012-55d7-4241-8d8c-2b4ea07aeb66.sql =====
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
-- ===== 20260625220458_da6b83a3-fd35-449d-8750-6d5686c4ab29.sql =====
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

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
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
GRANT SELECT ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = c.owner_id
      AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])) OR c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
  );
$$;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = cl.owner_id
      AND (_client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])) OR EXISTS (SELECT 1 FROM public.cases c WHERE c.client_id = _client_id AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))))
  );
$$;

CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[7, 24, 48] LOOP
    WITH due AS (
      SELECT s.id AS session_id, s.owner_id, lead_h AS lh FROM public.sessions s
      WHERE s.status = 'scheduled'
        AND s.session_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                              AND  now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
    SELECT owner_id, session_id, lh FROM due
    ON CONFLICT (session_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END $$;

CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_account_type text DEFAULT NULL, _access_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  user_email text;
  acct text := lower(coalesce(_account_type, ''));
  code text := nullif(trim(coalesce(_access_code, '')), '');
  linked_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

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
    UPDATE public.clients c
    SET portal_user_id = uid
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING c.id INTO linked_id;

    IF linked_id IS NULL THEN
      SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1;
    END IF;
    IF linked_id IS NULL THEN
      RETURN jsonb_build_object('linked', false, 'role', 'client', 'reason', 'client_not_found');
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
  END IF;

  IF acct = 'employee' THEN
    UPDATE public.employees e
    SET user_id = uid
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING e.id INTO linked_id;

    IF linked_id IS NULL THEN
      SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1;
    END IF;
    IF linked_id IS NULL THEN
      RETURN jsonb_build_object('linked', false, 'role', 'employee', 'reason', 'employee_not_found');
    END IF;
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
    UPDATE public.clients c
    SET portal_user_id = NEW.id
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING c.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'client') ON CONFLICT DO NOTHING;
  ELSIF acct = 'employee' THEN
    UPDATE public.employees e
    SET user_id = NEW.id
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING e.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'employee') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer') ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Update triggers
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- RLS policies
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (public.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (public.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (public.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (public.employee_can_access_case(case_id, auth.uid()) OR public.has_doc_permission(case_id, auth.uid(), 'view')));

DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

-- Storage policies for private case-documents bucket
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    JOIN public.cases c ON c.id = d.case_id
    JOIN public.clients cl ON cl.id = c.client_id
    WHERE d.storage_path = storage.objects.name AND cl.portal_user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
CREATE POLICY "employee reads assigned case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    WHERE d.storage_path = storage.objects.name
      AND d.case_id IS NOT NULL
      AND public.employee_can_access_case(d.case_id, auth.uid())
  ));

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.cases;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.documents;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;
-- ===== 20260625220607_6a4f75ce-0d8e-4a61-8ed0-45d554f78837.sql =====
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = c.owner_id
      AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])) OR c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
  );
$$;

CREATE OR REPLACE FUNCTION private.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = cl.owner_id
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

DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (private.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (private.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (private.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (private.employee_can_access_case(case_id, auth.uid()) OR private.has_doc_permission(case_id, auth.uid(), 'view')));

DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
CREATE POLICY "employee reads assigned case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d
    WHERE d.storage_path = storage.objects.name
      AND d.case_id IS NOT NULL
      AND private.employee_can_access_case(d.case_id, auth.uid())
  ));

REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO service_role;
-- ===== 20260625221123_8618f518-5b45-4648-9754-d547caa357db.sql =====
CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_account_type text DEFAULT NULL, _access_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  user_email text;
  acct text := lower(coalesce(_account_type, ''));
  code text := nullif(trim(coalesce(_access_code, '')), '');
  linked_id uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

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
    UPDATE public.clients c
    SET portal_user_id = uid
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING c.id INTO linked_id;

    IF linked_id IS NULL THEN
      SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1;
    END IF;
    IF linked_id IS NULL THEN
      RETURN jsonb_build_object('linked', false, 'role', 'client', 'reason', 'client_not_found');
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
  END IF;

  IF acct = 'employee' THEN
    UPDATE public.employees e
    SET user_id = uid
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING e.id INTO linked_id;

    IF linked_id IS NULL THEN
      SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1;
    END IF;
    IF linked_id IS NULL THEN
      RETURN jsonb_build_object('linked', false, 'role', 'employee', 'reason', 'employee_not_found');
    END IF;
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
    UPDATE public.clients c
    SET portal_user_id = NEW.id
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING c.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'client') ON CONFLICT DO NOTHING;
  ELSIF acct = 'employee' THEN
    UPDATE public.employees e
    SET user_id = NEW.id
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = NEW.id)
        AND lower(coalesce(email, '')) = lower(coalesce(NEW.email, ''))
        AND (portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC
      LIMIT 1
    )
    RETURNING e.id INTO linked_id;
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'employee') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer') ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO service_role;
-- ===== 20260626031335_5f4e5096-8a84-4265-8e82-c34f33619a83.sql =====
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TABLE IF NOT EXISTS public.profiles (id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated; GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, role public.app_role NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (user_id, role));
GRANT SELECT ON public.user_roles TO authenticated; GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role) RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role); $$;

CREATE TABLE IF NOT EXISTS public.clients (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, portal_access_code TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated; GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.cases (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL, assigned_employee_id UUID, case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT, case_type public.case_type NOT NULL DEFAULT 'other', status public.case_status NOT NULL DEFAULT 'open', opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE, description TEXT, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated; GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sessions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE, session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT, status public.session_status NOT NULL DEFAULT 'scheduled', notes TEXT, outcome TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated; GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.documents (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE, doc_type public.document_type NOT NULL DEFAULT 'other', title TEXT NOT NULL, description TEXT, storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT, filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated; GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_appeal_deadline() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$ BEGIN IF NEW.doc_type = 'judgment_non_final' AND NEW.judgment_date IS NOT NULL THEN NEW.appeal_deadline := NEW.judgment_date + INTERVAL '30 days'; END IF; RETURN NEW; END; $$;
DROP TRIGGER IF EXISTS trg_documents_appeal ON public.documents;
CREATE TRIGGER trg_documents_appeal BEFORE INSERT OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.set_appeal_deadline();

CREATE TABLE IF NOT EXISTS public.powers_of_attorney (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL, wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT, issue_date DATE, expiry_date DATE, scope TEXT, status public.wakalah_status NOT NULL DEFAULT 'active', najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated; GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.executions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL, client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL, execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT, status public.execution_status NOT NULL DEFAULT 'pending', filed_date DATE, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated; GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employees (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT, residence_expiry DATE, job_title TEXT, qualification TEXT, direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL, start_date DATE, end_date DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE, permissions JSONB DEFAULT '[]'::jsonb, assigned_cases UUID[] DEFAULT ARRAY[]::UUID[], assigned_clients UUID[] DEFAULT ARRAY[]::UUID[], portal_access_code TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated; GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.cases ADD CONSTRAINT cases_assigned_employee_id_fkey FOREIGN KEY (assigned_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.tasks (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL, case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL, title TEXT NOT NULL, description TEXT, due_date DATE, status public.task_status NOT NULL DEFAULT 'todo', priority public.task_priority NOT NULL DEFAULT 'medium', completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated; GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_notifications (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE, case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL, template TEXT, message TEXT NOT NULL, channel public.notification_channel NOT NULL DEFAULT 'whatsapp', status public.notification_status NOT NULL DEFAULT 'draft', scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated; GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.portal_messages (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE, case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL, sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer', 'employee')), sender_id UUID, subject TEXT, message TEXT NOT NULL, parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE, is_read BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated; GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, source TEXT NOT NULL, status TEXT NOT NULL, items_count INTEGER DEFAULT 0, inserted_count INTEGER DEFAULT 0, updated_count INTEGER DEFAULT 0, raw_payload JSONB, error_message TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
GRANT SELECT, INSERT, UPDATE ON public.najiz_sync_logs TO authenticated; GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, token_hash TEXT NOT NULL UNIQUE, label TEXT, last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ, is_revoked BOOLEAN NOT NULL DEFAULT FALSE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated; GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.user_preferences (user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE, sidebar_width INTEGER NOT NULL DEFAULT 288, sidebar_collapsed BOOLEAN NOT NULL DEFAULT false, dashboard_cards JSONB NOT NULL DEFAULT '[]'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated; GRANT ALL ON public.user_preferences TO service_role;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.audit_log (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL, action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT, metadata JSONB NOT NULL DEFAULT '{}'::jsonb, ip_address TEXT, user_agent TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
GRANT SELECT, INSERT ON public.audit_log TO authenticated; GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

CREATE TABLE IF NOT EXISTS public.saved_filters (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, scope TEXT NOT NULL, name TEXT NOT NULL, filters JSONB NOT NULL DEFAULT '{}'::jsonb, is_default BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (owner_id, scope, name));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated; GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.notification_preferences (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE, sessions JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,48]}'::jsonb, tasks JSONB NOT NULL DEFAULT '{"toast":true,"email":false,"lead_hours":[24]}'::jsonb, appeals JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,72]}'::jsonb, channels JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"whatsapp":false,"sms":false}'::jsonb, quiet_hours JSONB NOT NULL DEFAULT '{"enabled":false,"start":"22:00","end":"07:00"}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated; GRANT ALL ON public.notification_preferences TO service_role;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.document_permissions (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE, user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, permission public.doc_permission NOT NULL DEFAULT 'view', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (case_id, user_id, permission));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated; GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id uuid, _user_id uuid, _perm public.doc_permission) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT EXISTS (SELECT 1 FROM public.cases c WHERE c.id = _case_id AND c.owner_id = _user_id) OR EXISTS (SELECT 1 FROM public.document_permissions dp WHERE dp.case_id = _case_id AND dp.user_id = _user_id AND (dp.permission = _perm OR dp.permission = 'manage')); $$;

CREATE TABLE IF NOT EXISTS public.secure_secrets (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, scope TEXT NOT NULL, key TEXT NOT NULL, ciphertext TEXT NOT NULL, iv TEXT NOT NULL, metadata JSONB NOT NULL DEFAULT '{}'::jsonb, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (owner_id, scope, key));
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.session_reminders (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE, session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE, lead_hours INT NOT NULL, sent_at TIMESTAMPTZ, status TEXT NOT NULL DEFAULT 'pending', error TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (session_id, lead_hours));
GRANT SELECT ON public.session_reminders TO authenticated; GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.employee_can_access_case(_case_id uuid, _user_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT EXISTS (SELECT 1 FROM public.employees e JOIN public.cases c ON c.id = _case_id WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = c.owner_id AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])) OR c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))); $$;
CREATE OR REPLACE FUNCTION private.employee_can_access_client(_client_id uuid, _user_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT EXISTS (SELECT 1 FROM public.employees e JOIN public.clients cl ON cl.id = _client_id WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = cl.owner_id AND (_client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])) OR EXISTS (SELECT 1 FROM public.cases c WHERE c.client_id = _client_id AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))))); $$;
CREATE OR REPLACE FUNCTION private.has_doc_permission(_case_id uuid, _user_id uuid, _perm public.doc_permission) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT EXISTS (SELECT 1 FROM public.cases c WHERE c.id = _case_id AND c.owner_id = _user_id) OR EXISTS (SELECT 1 FROM public.document_permissions dp WHERE dp.case_id = _case_id AND dp.user_id = _user_id AND (dp.permission = _perm OR dp.permission = 'manage')); $$;
GRANT EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_client(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;

DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (private.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (private.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (private.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (private.employee_can_access_case(case_id, auth.uid()) OR private.has_doc_permission(case_id, auth.uid(), 'view')));

DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

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
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.cases; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.documents; EXCEPTION WHEN OTHERS THEN NULL; END $$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;
-- ===== 20260626031358_1731f5d7-c263-495e-b9a7-e5148061c6c5.sql =====
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders() RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE((np.sessions->'lead_hours')::jsonb, '[24,48]'::jsonb) AS lead_hours
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

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;
-- ===== 20260626035141_3495ccaf-c155-422f-b0cf-82e00b1ecf7e.sql =====
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

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
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
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
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (private.employee_can_access_client(id, auth.uid()));
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (private.employee_can_access_case(id, auth.uid()));
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (private.employee_can_access_case(case_id, auth.uid()));
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (private.employee_can_access_case(case_id, auth.uid()) OR private.has_doc_permission(case_id, auth.uid(), 'view')));
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid()));
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND EXISTS (
    SELECT 1 FROM public.documents d JOIN public.cases c ON c.id = d.case_id JOIN public.clients cl ON cl.id = c.client_id
    WHERE d.storage_path = storage.objects.name AND cl.portal_user_id = auth.uid()
  ));
DROP POLICY IF EXISTS "employee reads assigned case docs" ON storage.objects;
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
-- ===== 20260626035255_4f369eb1-4dbb-4fe7-bcc4-bdd9f788266e.sql =====
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO service_role;
-- ===== 20260626215212_3374e495-d79c-42bc-baad-d1579d21c580.sql =====
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
-- ===== 20260626215313_ec041c29-fdb1-432e-b91b-1c06bc90784a.sql =====
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
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
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT,
  address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type public.case_type NOT NULL DEFAULT 'other',
  status public.case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE,
  closed_at DATE, description TEXT, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status public.session_status NOT NULL DEFAULT 'scheduled',
  notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type public.document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT, storage_path TEXT, file_name TEXT,
  file_size BIGINT, mime_type TEXT, filed_date DATE, judgment_date DATE,
  court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
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
DROP TRIGGER IF EXISTS trg_documents_appeal ON public.documents;
CREATE TRIGGER trg_documents_appeal BEFORE INSERT OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.set_appeal_deadline();

CREATE TABLE IF NOT EXISTS public.powers_of_attorney (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status public.wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status public.execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT,
  residence_expiry DATE, job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
-- ===== 20260626215436_fbd2235b-9831-4610-b962-651cd4c042d0.sql =====
CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status public.task_status NOT NULL DEFAULT 'todo',
  priority public.task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel public.notification_channel NOT NULL DEFAULT 'whatsapp',
  status public.notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer', 'employee')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL, status TEXT NOT NULL,
  items_count INTEGER DEFAULT 0, inserted_count INTEGER DEFAULT 0, updated_count INTEGER DEFAULT 0,
  raw_payload JSONB, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT, UPDATE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE, label TEXT,
  last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
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
  action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT, user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.saved_filters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, name TEXT NOT NULL,
  filters JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, name)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
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
  scope TEXT NOT NULL, key TEXT NOT NULL,
  ciphertext TEXT NOT NULL, iv TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, key)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.session_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lead_hours INT NOT NULL, sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending', error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, lead_hours)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
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
    INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'employee') ON CONFLICT DO NOTHING;
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

DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
-- ===== 20260626215642_7a7cad8d-150e-4e43-b98f-9533428db40c.sql =====
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

DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (private.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (private.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (private.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (private.employee_can_access_case(case_id, auth.uid()) OR private.has_doc_permission(case_id, auth.uid(), 'view')));

DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

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
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;
-- ===== 20260626215745_3cebf142-df60-4fc8-b068-370be4aaa076.sql =====
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS TABLE (
  jobid bigint, jobname text, schedule text, active boolean,
  last_start timestamptz, last_status text, last_message text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, cron, extensions
AS $$
  SELECT j.jobid, j.jobname, j.schedule, j.active,
    r.start_time AS last_start, r.status AS last_status, r.return_message AS last_message
  FROM cron.job j
  LEFT JOIN LATERAL (
    SELECT start_time, status, return_message
    FROM cron.job_run_details d
    WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1
  ) r ON true
  WHERE EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = auth.uid() AND ur.role = 'admin');
$$;
REVOKE ALL ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated;

DO $$ BEGIN
  PERFORM cron.unschedule('enqueue-session-reminders');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

SELECT cron.schedule(
  'enqueue-session-reminders',
  '*/15 * * * *',
  $$ SELECT public.enqueue_session_reminders(); $$
);
-- ===== 20260626220630_3f3ef13d-031b-4b1c-ab9a-675a0ba3522c.sql =====

DROP POLICY IF EXISTS "case_documents_select_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_update_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_delete_own" ON storage.objects;

DROP POLICY IF EXISTS "case_documents_select_own" ON storage.objects;
CREATE POLICY "case_documents_select_own" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "case_documents_insert_own" ON storage.objects;
CREATE POLICY "case_documents_insert_own" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "case_documents_update_own" ON storage.objects;
CREATE POLICY "case_documents_update_own" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1])
WITH CHECK (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "case_documents_delete_own" ON storage.objects;
CREATE POLICY "case_documents_delete_own" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

-- ===== 20260626221741_2c453a12-610f-4fe1-b7a6-236a418ec8ad.sql =====
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated;
-- ===== 20260626221859_296d677a-e1dc-4116-8026-481aff5faf2d.sql =====
NOTIFY pgrst, 'reload schema';
-- ===== 20260626222308_dfb83629-1be3-4566-ade1-e1b21a98131e.sql =====
UPDATE auth.users SET email_confirmed_at = COALESCE(email_confirmed_at, now()) WHERE email = 'e2e@example.com';
-- ===== 20260626223127_87c950a2-2a1d-4d20-a41d-0f33dfed495f.sql =====

-- 1) Fix audit_log INSERT policy to prevent owner_id spoofing
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = actor_id AND auth.uid() = owner_id);

-- 2) Tighten storage policies for case-documents bucket
DROP POLICY IF EXISTS case_documents_select_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_insert_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_update_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_delete_own ON storage.objects;

-- Helper: extract case_id (second folder segment) safely
-- Path convention: {owner_uuid}/{case_uuid}/{filename}

-- SELECT: owner, assigned employee, portal client of the case, or doc-permission grantee
DROP POLICY IF EXISTS case_documents_select_authorized ON storage.objects;
CREATE POLICY case_documents_select_authorized ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (
    -- Owner (law firm) — original path-prefix check
    (auth.uid())::text = (storage.foldername(name))[1]
    OR EXISTS (
      SELECT 1
      FROM public.cases c
      WHERE c.id::text = (storage.foldername(name))[2]
        AND (
          c.owner_id = auth.uid()
          OR private.employee_can_access_case(c.id, auth.uid())
          OR EXISTS (
            SELECT 1 FROM public.clients cl
            WHERE cl.id = c.client_id AND cl.portal_user_id = auth.uid()
          )
          OR public.has_doc_permission(c.id, auth.uid(), 'view'::public.doc_permission)
        )
    )
  )
);

-- INSERT: only the owner of the case may upload (owner or doc-permission with manage/edit)
DROP POLICY IF EXISTS case_documents_insert_authorized ON storage.objects;
CREATE POLICY case_documents_insert_authorized ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
  AND EXISTS (
    SELECT 1 FROM public.cases c
    WHERE c.id::text = (storage.foldername(name))[2]
      AND c.owner_id = auth.uid()
  )
);

-- UPDATE: same as insert
DROP POLICY IF EXISTS case_documents_update_authorized ON storage.objects;
CREATE POLICY case_documents_update_authorized ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
)
WITH CHECK (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
);

-- DELETE: owner only
DROP POLICY IF EXISTS case_documents_delete_authorized ON storage.objects;
CREATE POLICY case_documents_delete_authorized ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
);

-- 3) Revoke EXECUTE from authenticated/PUBLIC on SECURITY DEFINER helpers
--    that should not be directly callable by signed-in users.
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, authenticated, anon;

-- Keep EXECUTE on user-callable RPCs (re-grant to be explicit)
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated;

-- ===== 20260626224647_707c6601-107b-41f2-a766-144d0d56765a.sql =====
-- Task reminders mirroring session_reminders
CREATE TABLE IF NOT EXISTS public.task_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours integer NOT NULL,
  sent_at timestamptz,
  status text NOT NULL DEFAULT 'pending',
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, lead_hours)
);

GRANT SELECT ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;

ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner reads task reminders" ON public.task_reminders;
CREATE POLICY "owner reads task reminders" ON public.task_reminders FOR SELECT
  TO authenticated
  USING (auth.uid() = owner_id OR (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())));

CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tr_pending ON public.task_reminders (status, created_at);

-- enqueue task reminders based on tasks.due_date and notification_preferences.tasks.lead_hours (default [24, 72])
CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE(np.tasks->'lead_hours', '[24, 72]'::jsonb) AS lead_hours
    FROM public.notification_preferences np
  ), expanded AS (
    SELECT t.id AS task_id, t.owner_id, t.employee_id,
           (t.due_date::timestamp AT TIME ZONE 'UTC') AS due_ts,
           (lh::text)::int AS lead_hours
    FROM public.tasks t
    LEFT JOIN prefs p ON p.owner_id = t.owner_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.lead_hours, '[24, 72]'::jsonb)) AS lh
    WHERE t.status <> 'done' AND t.due_date IS NOT NULL AND t.due_date >= CURRENT_DATE
  ), to_insert AS (
    SELECT e.owner_id, e.task_id, e.employee_id, e.lead_hours
    FROM expanded e
    WHERE e.due_ts - (e.lead_hours || ' hours')::interval <= now() + interval '15 minutes'
      AND e.due_ts - (e.lead_hours || ' hours')::interval > now() - interval '1 hour'
  )
  INSERT INTO public.task_reminders (owner_id, task_id, employee_id, lead_hours)
  SELECT owner_id, task_id, employee_id, lead_hours FROM to_insert
  ON CONFLICT (task_id, lead_hours) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role, authenticated;
-- ===== 20260626224657_977633b4-12ba-4303-b06c-e7d391dbac3f.sql =====
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM authenticated;
-- ===== 20260627012533_174e46a7-4225-4265-a437-949827443d01.sql =====
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT,
  address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL,
  court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other',
  status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE,
  closed_at DATE, description TEXT,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL,
  court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled',
  notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT,
  storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT,
  appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'case-documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      JOIN public.cases c ON c.id = d.case_id
      JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = storage.objects.name
        AND cl.portal_user_id = auth.uid()
    )
  );

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
  issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE,
  scope TEXT, status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT,
  amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT,
  phone TEXT, email TEXT, residence_expiry DATE,
  job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT,
  due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
) WITH CHECK (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
-- ===== 20260627012720_7f67c7f0-7229-4583-80f7-63a58bdd83f6.sql =====
-- portal_access_code on employees
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;

-- user_preferences
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
DROP POLICY IF EXISTS "user manages own prefs" ON public.user_preferences;
CREATE POLICY "user manages own prefs" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_prefs_updated ON public.user_preferences;
CREATE TRIGGER trg_user_prefs_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- audit_log
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id, created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id AND auth.uid() = owner_id);

-- sync_tokens
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manages sync tokens" ON public.sync_tokens;
CREATE POLICY "owner manages sync tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- notification_preferences
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
DROP POLICY IF EXISTS "owner manages notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manages notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notif_prefs_updated ON public.notification_preferences;
CREATE TRIGGER trg_notif_prefs_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- session_reminders
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
GRANT SELECT ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads session reminders" ON public.session_reminders;
CREATE POLICY "owner reads session reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

-- task_reminders
CREATE TABLE IF NOT EXISTS public.task_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours INT NOT NULL,
  sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, lead_hours)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tr_pending ON public.task_reminders(status, created_at);
GRANT SELECT ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads task reminders" ON public.task_reminders;
CREATE POLICY "owner reads task reminders" ON public.task_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id OR (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())));

-- RPCs
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE((np.sessions->'lead_hours')::jsonb, '[24,48]'::jsonb) AS lead_hours
    FROM public.notification_preferences np
  ), expanded AS (
    SELECT s.id AS session_id, s.owner_id, s.session_date, (lh::text)::int AS lead_hours
    FROM public.sessions s
    LEFT JOIN prefs p ON p.owner_id = s.owner_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.lead_hours, '[24,48]'::jsonb)) AS lh
    WHERE s.status = 'scheduled' AND s.session_date > now()
  ), to_insert AS (
    SELECT e.owner_id, e.session_id, e.lead_hours FROM expanded e
    WHERE e.session_date - (e.lead_hours || ' hours')::interval <= now() + interval '15 minutes'
      AND e.session_date - (e.lead_hours || ' hours')::interval > now() - interval '1 hour'
  )
  INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
  SELECT owner_id, session_id, lead_hours FROM to_insert
  ON CONFLICT (session_id, lead_hours) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END; $$;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE(np.tasks->'lead_hours', '[24,72]'::jsonb) AS lead_hours
    FROM public.notification_preferences np
  ), expanded AS (
    SELECT t.id AS task_id, t.owner_id, t.employee_id,
           (t.due_date::timestamp AT TIME ZONE 'UTC') AS due_ts,
           (lh::text)::int AS lead_hours
    FROM public.tasks t
    LEFT JOIN prefs p ON p.owner_id = t.owner_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.lead_hours, '[24,72]'::jsonb)) AS lh
    WHERE t.status <> 'done' AND t.due_date IS NOT NULL AND t.due_date >= CURRENT_DATE
  ), to_insert AS (
    SELECT e.owner_id, e.task_id, e.employee_id, e.lead_hours FROM expanded e
    WHERE e.due_ts - (e.lead_hours || ' hours')::interval <= now() + interval '15 minutes'
      AND e.due_ts - (e.lead_hours || ' hours')::interval > now() - interval '1 hour'
  )
  INSERT INTO public.task_reminders (owner_id, task_id, employee_id, lead_hours)
  SELECT owner_id, task_id, employee_id, lead_hours FROM to_insert
  ON CONFLICT (task_id, lead_hours) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END; $$;

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN jsonb_build_object('enabled', false, 'jobs', '[]'::jsonb);
END; $$;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

-- link_current_user_to_portal (used at sign-in)
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
END; $$;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;

-- Realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE public.cases;
ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.documents;
ALTER PUBLICATION supabase_realtime ADD TABLE public.portal_messages;
-- ===== 20260627012741_c1435149-20f2-41bb-9964-cebe13efd86d.sql =====
CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  items_count INTEGER,
  inserted_count INTEGER,
  updated_count INTEGER,
  error_message TEXT,
  raw_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_status ON public.najiz_sync_logs(status, created_at);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manages najiz logs" ON public.najiz_sync_logs;
CREATE POLICY "owner manages najiz logs" ON public.najiz_sync_logs FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
-- ===== 20260627013442_2277ff02-8d42-4f18-a7b9-1972f112fd56.sql =====
CREATE OR REPLACE FUNCTION public.system_check_inspect()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Only allow admins/lawyers to introspect
  IF NOT (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'lawyer')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT jsonb_build_object(
    'tables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('tablename', c.relname, 'rls', c.relrowsecurity))
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
    ), '[]'::jsonb),
    'policies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('tablename', tablename, 'cnt', cnt))
      FROM (
        SELECT tablename, COUNT(*) AS cnt
        FROM pg_policies
        WHERE schemaname = 'public'
        GROUP BY tablename
      ) p
    ), '[]'::jsonb),
    'grants', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'table_name', table_name,
        'grantee', grantee,
        'privilege_type', privilege_type
      ))
      FROM information_schema.role_table_grants
      WHERE table_schema = 'public'
        AND grantee IN ('anon','authenticated','service_role')
    ), '[]'::jsonb),
    'rpcs', COALESCE((
      SELECT jsonb_agg(routine_name)
      FROM information_schema.routines
      WHERE routine_schema = 'public'
    ), '[]'::jsonb),
    'publication', COALESCE((
      SELECT jsonb_agg(tablename)
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
    ), '[]'::jsonb),
    'buckets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'public', public))
      FROM storage.buckets
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO authenticated;
-- ===== 20260627014648_046037b7-9f2f-4bd0-bb88-080b5cae5023.sql =====

-- Revoke EXECUTE on SECURITY DEFINER functions from anon/authenticated/PUBLIC.
-- These functions are now only callable via server functions using service_role.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.system_check_inspect() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon, authenticated;
-- service_role keeps EXECUTE (used by server functions / admin client).
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO service_role;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO service_role;

-- ===== 20260627063238_5416b2ba-47e9-4019-a94f-3c0173b3f223.sql =====
-- Idempotent migration: minimum schema needed for build + Team Chat + Bell
-- Safe to re-run.

-- ========= ENUMS =========
DO $$ BEGIN
  DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin','lawyer','employee','client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ========= shared trigger function =========
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

-- ========= profiles =========
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
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ========= user_roles =========
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
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

-- New-user bootstrap: profile + default 'lawyer' role
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email)
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer')
  ON CONFLICT (user_id, role) DO NOTHING;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ========= employees =========
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
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user  ON public.employees(user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "employees read peers in tenant" ON public.employees;
DROP POLICY IF EXISTS "employees read peers in tenant" ON public.employees;
CREATE POLICY "employees read peers in tenant" ON public.employees
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.employees me WHERE me.user_id = auth.uid() AND me.owner_id = public.employees.owner_id));
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ========= employee_messages =========
CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_pair  ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages
  FOR SELECT TO authenticated USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages
  FOR SELECT TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      auth.uid() = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id)
    )
    AND (
      recipient_id = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = recipient_id AND e.owner_id = employee_messages.owner_id)
    )
  );

DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages
  FOR UPDATE TO authenticated
  USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);

DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages
  FOR DELETE TO authenticated USING (auth.uid() = sender_id);

ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;

-- ========= sync_tokens (Najiz extension auth) =========
CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sync_tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage sync_tokens" ON public.sync_tokens;
CREATE POLICY "owner manage sync_tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ========= najiz_sync_logs =========
CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER,
  inserted_count INTEGER,
  updated_count INTEGER,
  error_message TEXT,
  raw_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage najiz_logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner manage najiz_logs" ON public.najiz_sync_logs;
CREATE POLICY "owner manage najiz_logs" ON public.najiz_sync_logs FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ===== 20260627063457_9a0d86bb-2960-44fb-8978-169d731c987e.sql =====
-- Idempotent: complete remaining schema to match database.types.ts

-- ============ ENUMS ============
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open','in_study','closed_final','closed_non_final','appealed','archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor','commercial','execution','civil','personal_status','administrative','criminal','other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit','judgment_final','judgment_non_final','appeal_judgment','memorandum_reply','session_minutes','power_of_attorney','evidence','other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending','in_progress','completed','rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp','sms','email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft','scheduled','sent','failed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled','held','postponed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low','medium','high','urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo','in_progress','done','overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active','expired','revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============ extra column on employees ============
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "portal user reads own client" ON public.clients;
DROP POLICY IF EXISTS "portal user reads own client" ON public.clients;
CREATE POLICY "portal user reads own client" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_upd ON public.clients;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_cases_upd ON public.cases;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_sessions_upd ON public.sessions;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_tasks_upd ON public.tasks;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_documents_upd ON public.documents;
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
DROP POLICY IF EXISTS "owner manage doc_perm" ON public.document_permissions;
CREATE POLICY "owner manage doc_perm" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "user reads own doc_perm" ON public.document_permissions;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_upd ON public.executions;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_poa_owner ON public.powers_of_attorney(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage poa" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage poa" ON public.powers_of_attorney;
CREATE POLICY "owner manage poa" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_poa_upd ON public.powers_of_attorney;
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
DROP POLICY IF EXISTS "owner manage client_notif" ON public.client_notifications;
CREATE POLICY "owner manage client_notif" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_client_notif_upd ON public.client_notifications;
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
DROP POLICY IF EXISTS "owner manage portal_messages" ON public.portal_messages;
CREATE POLICY "owner manage portal_messages" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "portal user reads own messages" ON public.portal_messages;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own notifications" ON public.notifications;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_log_owner ON public.audit_log(owner_id, created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
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
DROP POLICY IF EXISTS "actor reads audit_logs" ON public.audit_logs;
CREATE POLICY "actor reads audit_logs" ON public.audit_logs FOR SELECT TO authenticated USING (auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit_logs" ON public.audit_logs;
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

-- ===== 20260627063607_0913138d-4c16-4795-82eb-7203036c07e6.sql =====
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "select tenant or thread" ON public.employee_messages;
DROP POLICY IF EXISTS "select tenant or thread" ON public.employee_messages;
CREATE POLICY "select tenant or thread" ON public.employee_messages
  FOR SELECT TO authenticated
  USING (auth.uid() = owner_id OR auth.uid() = sender_id OR auth.uid() = recipient_id);
-- ===== 20260627065438_46a935b9-c817-40dc-b9a3-b3a216dc01c7.sql =====
-- Schedule readiness check + session reminders via pg_cron + pg_net.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Idempotent: drop existing jobs by name if present, then re-create.
DO $$
DECLARE
  v_url_root text := 'https://project--ahfqftobmcssbdurutay.lovable.app';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFoZnFmdG9ibWNzc2JkdXJ1dGF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MjExODMsImV4cCI6MjA5ODA5NzE4M30._OBZBrkzEWvyxBG-Fbv3d1opSZs0jS18gFQKkzhi1iU';
BEGIN
  -- unschedule by name (no error if absent)
  PERFORM cron.unschedule(j.jobid)
  FROM cron.job j
  WHERE j.jobname IN ('lex_readiness_check', 'lex_session_reminders');

  -- Readiness check every 15 minutes
  PERFORM cron.schedule(
    'lex_readiness_check',
    '*/15 * * * *',
    format($job$
      SELECT net.http_get(
        url := %L,
        headers := jsonb_build_object('apikey', %L, 'Content-Type', 'application/json')
      );
    $job$, v_url_root || '/api/public/system-check', v_anon)
  );

  -- Session reminders every 10 minutes
  PERFORM cron.schedule(
    'lex_session_reminders',
    '*/10 * * * *',
    format($job$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object('apikey', %L, 'Content-Type', 'application/json'),
        body := '{}'::jsonb
      );
    $job$, v_url_root || '/api/public/cron/session-reminders', v_anon)
  );
END$$;

-- Refresh the cron status helper so the UI can read job state.
CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, cron
AS $$
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object(
      'jobname',  j.jobname,
      'schedule', j.schedule,
      'active',   j.active
    )),
    '[]'::jsonb
  )
  FROM cron.job j
  WHERE j.jobname LIKE 'lex_%';
$$;

GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
-- ===== 20260627065452_1108e5b5-904f-4ff7-9611-c79276f4703d.sql =====
CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, cron
AS $$
BEGIN
  -- Only admins may inspect schedule details.
  IF NOT public.has_role('admin', auth.uid()) THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN (
    SELECT COALESCE(
      jsonb_agg(jsonb_build_object(
        'jobname',  j.jobname,
        'schedule', j.schedule,
        'active',   j.active
      )),
      '[]'::jsonb
    )
    FROM cron.job j
    WHERE j.jobname LIKE 'lex_%'
  );
END$$;

REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;
-- ===== 20260627135920_1cc2da03-0855-4c2f-8e95-3394eb5419bd.sql =====
-- placeholder; see /tmp/all_migrations.sql for real content
SELECT 1;
-- ===== 20260627140327_669044a0-9871-4869-9722-760967a6663a.sql =====
DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT,
  portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other',
  status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE,
  description TEXT, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled', notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT, storage_path TEXT,
  file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issuer_id_number TEXT, agent_id_number TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT,
  residence_expiry DATE, job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (
  employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated
  USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
  WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension',
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0, inserted_count INTEGER DEFAULT 0, updated_count INTEGER DEFAULT 0,
  error_message TEXT, raw_payload JSONB, trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT, last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences
  FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'case-documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      JOIN public.cases c ON c.id = d.case_id
      JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = storage.objects.name
        AND cl.portal_user_id = auth.uid()
    )
  );
-- ===== 20260627140519_9b63b86d-0d5f-495a-a79c-90728d258ecd.sql =====
-- has_role: fix argument order to (_role, _user_id)
DROP FUNCTION IF EXISTS public.has_role(uuid, public.app_role);
DROP FUNCTION IF EXISTS public.has_role(public.app_role, uuid);
CREATE OR REPLACE FUNCTION public.has_role(_role public.app_role, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;
REVOKE EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) TO authenticated, service_role;

-- doc_permission enum
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- employee access helpers
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
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
CREATE POLICY "owner manage session_reminders" ON public.session_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
CREATE POLICY "owner manage task_reminders" ON public.task_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "owner manage doc_perm" ON public.document_permissions;
CREATE POLICY "owner manage doc_perm" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "user reads own doc_perm" ON public.document_permissions;
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

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  office_id UUID,
  title TEXT NOT NULL, message TEXT, category TEXT, link TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own notifications" ON public.notifications;
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
DROP POLICY IF EXISTS "owner manage notif_prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif_prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_log_owner ON public.audit_log(owner_id, created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
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
DROP POLICY IF EXISTS "actor reads audit_logs" ON public.audit_logs;
CREATE POLICY "actor reads audit_logs" ON public.audit_logs FOR SELECT TO authenticated USING (auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "actor inserts audit_logs" ON public.audit_logs;
CREATE POLICY "actor inserts audit_logs" ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

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
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "owner manage secrets" ON public.secure_secrets;
CREATE POLICY "owner manage secrets" ON public.secure_secrets FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- employee_messages (internal staff chat)
CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_pair ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages FOR SELECT TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      auth.uid() = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id)
    )
    AND (
      recipient_id = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = recipient_id AND e.owner_id = employee_messages.owner_id)
    )
  );
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages FOR UPDATE TO authenticated
  USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

-- client_inquiries thread
CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id uuid REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id uuid REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id uuid NOT NULL,
  author_role text NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject text, body text NOT NULL,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_parent ON public.client_inquiries(parent_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
CREATE POLICY "owner reads inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
CREATE POLICY "owner writes inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
CREATE POLICY "owner updates inquiries" ON public.client_inquiries FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries FOR DELETE TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
CREATE POLICY "client reads own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid())
);
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
CREATE POLICY "client writes own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid() AND author_role = 'client'
  AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id)
);

-- employees portal credentials
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_username TEXT;

-- link_current_user_to_portal
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

-- stub queue functions
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders() RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0; $$;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders() RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0; $$;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status() RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT '[]'::jsonb; $$;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

-- Realtime
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.client_inquiries REPLICA IDENTITY FULL;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.client_inquiries; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
-- ===== 20260627140529_a06061a0-bd39-4b88-a5be-7c66a9d3d4f7.sql =====
ALTER TABLE public.najiz_sync_logs ALTER COLUMN kind DROP NOT NULL;
ALTER TABLE public.najiz_sync_logs ALTER COLUMN kind SET DEFAULT 'sync';
-- ===== 20260627184439_65e73015-660c-449f-8e7a-c9a00f817a2d.sql =====
create extension if not exists pgcrypto with schema public;
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$ begin DO $idem$ BEGIN
  create type public.app_role as enum ('admin','lawyer','employee','client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.case_status as enum ('open','in_study','closed_final','closed_non_final','appealed','archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.case_type as enum ('labor','commercial','execution','civil','personal_status','administrative','criminal','other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.session_status as enum ('scheduled','held','postponed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.document_type as enum ('lawsuit','judgment_final','judgment_non_final','appeal_judgment','memorandum_reply','session_minutes','power_of_attorney','evidence','other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.wakalah_status as enum ('active','expired','revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.execution_status as enum ('pending','in_progress','completed','rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.task_status as enum ('todo','in_progress','done','overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.task_priority as enum ('low','medium','high','urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.notification_status as enum ('draft','scheduled','sent','failed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.notification_channel as enum ('whatsapp','sms','email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;
do $$ begin DO $idem$ BEGIN
  create type public.doc_permission as enum ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; exception when duplicate_object then null; end $$;

create or replace function public.update_updated_at_column() returns trigger language plpgsql set search_path=public as $$ begin new.updated_at=now(); return new; end $$;

create table if not exists public.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text, email text, phone text, avatar_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
grant select,insert,update on public.profiles to authenticated; grant all on public.profiles to service_role; alter table public.profiles enable row level security;
drop policy if exists "users view own profile" on public.profiles; drop policy if exists "users update own profile" on public.profiles; drop policy if exists "users insert own profile" on public.profiles;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles for select to authenticated using (auth.uid()=id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles for update to authenticated using (auth.uid()=id) with check (auth.uid()=id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles for insert to authenticated with check (auth.uid()=id);
drop trigger if exists trg_profiles_updated on public.profiles; DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
create trigger trg_profiles_updated before update on public.profiles for each row execute function public.update_updated_at_column();

create table if not exists public.user_roles (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, role public.app_role not null, created_at timestamptz not null default now(), unique(user_id,role));
grant select on public.user_roles to authenticated; grant all on public.user_roles to service_role; alter table public.user_roles enable row level security;
create or replace function public.has_role(_user_id uuid,_role public.app_role) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.user_roles where user_id=_user_id and role=_role) $$;
grant execute on function public.has_role(uuid,public.app_role) to authenticated, service_role;
drop policy if exists "users read own roles" on public.user_roles; drop policy if exists "admins read all roles" on public.user_roles;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles for select to authenticated using (auth.uid()=user_id);
DROP POLICY IF EXISTS "admins read all roles" ON public.user_roles;
CREATE POLICY "admins read all roles" ON public.user_roles for select to authenticated using (public.has_role(auth.uid(),'admin'));

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',new.email),new.email) on conflict(id) do update set email=excluded.email, full_name=coalesce(public.profiles.full_name,excluded.full_name); if not exists(select 1 from public.user_roles where user_id=new.id) then insert into public.user_roles(user_id,role) values(new.id,'lawyer') on conflict do nothing; end if; return new; end $$;
drop trigger if exists on_auth_user_created on auth.users; DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create table if not exists public.clients (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, portal_user_id uuid references auth.users(id) on delete set null, full_name text not null, national_id text, phone text, email text, address text, notes text, portal_access_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_clients_owner on public.clients(owner_id); CREATE INDEX IF NOT EXISTS if not exists idx_clients_portal on public.clients(portal_user_id); CREATE UNIQUE INDEX IF NOT EXISTS if not exists uniq_clients_owner_email on public.clients(owner_id,lower(email)) where email is not null;
grant select,insert,update,delete on public.clients to authenticated; grant all on public.clients to service_role; alter table public.clients enable row level security;
drop policy if exists "owner manage clients" on public.clients; drop policy if exists "client reads own row" on public.clients; drop policy if exists "employee reads assigned clients" on public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients for select to authenticated using (auth.uid()=portal_user_id);
drop trigger if exists trg_clients_updated on public.clients; DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
create trigger trg_clients_updated before update on public.clients for each row execute function public.update_updated_at_column();

create table if not exists public.employees (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, user_id uuid references auth.users(id) on delete set null, full_name text not null, nationality text, national_id text, phone text, email text, residence_expiry date, job_title text, qualification text, direct_manager_id uuid references public.employees(id) on delete set null, start_date date, end_date date, is_active boolean not null default true, permissions jsonb default '[]'::jsonb, assigned_cases uuid[] default array[]::uuid[], assigned_clients uuid[] default array[]::uuid[], portal_username text, portal_access_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_employees_owner on public.employees(owner_id); CREATE INDEX IF NOT EXISTS if not exists idx_employees_user on public.employees(user_id);
grant select,insert,update,delete on public.employees to authenticated; grant all on public.employees to service_role; alter table public.employees enable row level security;
drop policy if exists "owner manage employees" on public.employees; drop policy if exists "employee reads own row" on public.employees; drop policy if exists "employees read tenant roster" on public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees for select to authenticated using (auth.uid()=user_id);
DROP POLICY IF EXISTS "employees read tenant roster" ON public.employees;
CREATE POLICY "employees read tenant roster" ON public.employees for select to authenticated using (exists(select 1 from public.employees me where me.user_id=auth.uid() and me.owner_id=employees.owner_id and me.is_active));
drop trigger if exists trg_employees_updated on public.employees; DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
create trigger trg_employees_updated before update on public.employees for each row execute function public.update_updated_at_column();

create table if not exists public.cases (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, client_id uuid references public.clients(id) on delete set null, assigned_employee_id uuid references public.employees(id) on delete set null, case_number text not null, title text not null, court text, circuit_number text, judge_name text, case_type public.case_type not null default 'other', status public.case_status not null default 'open', opened_at date not null default current_date, closed_at date, description text, najiz_id text, najiz_synced_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_cases_owner on public.cases(owner_id); CREATE INDEX IF NOT EXISTS if not exists idx_cases_client on public.cases(client_id); CREATE INDEX IF NOT EXISTS if not exists idx_cases_assigned_employee on public.cases(assigned_employee_id); CREATE UNIQUE INDEX IF NOT EXISTS if not exists uniq_cases_najiz on public.cases(owner_id,najiz_id) where najiz_id is not null;
grant select,insert,update,delete on public.cases to authenticated; grant all on public.cases to service_role; alter table public.cases enable row level security;
drop policy if exists "owner manage cases" on public.cases; drop policy if exists "client reads own cases" on public.cases; drop policy if exists "employee reads assigned cases" on public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases for select to authenticated using (client_id in (select id from public.clients where portal_user_id=auth.uid()));
drop trigger if exists trg_cases_updated on public.cases; DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
create trigger trg_cases_updated before update on public.cases for each row execute function public.update_updated_at_column();

create or replace function public.employee_can_access_case(_case_id uuid,_user_id uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.employees e join public.cases c on c.id=_case_id where e.user_id=_user_id and e.is_active=true and e.owner_id=c.owner_id and (c.assigned_employee_id=e.id or c.id=any(coalesce(e.assigned_cases,array[]::uuid[])) or c.client_id=any(coalesce(e.assigned_clients,array[]::uuid[])))) $$;
create or replace function public.employee_can_access_client(_client_id uuid,_user_id uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.employees e join public.clients c on c.id=_client_id where e.user_id=_user_id and e.is_active=true and e.owner_id=c.owner_id and (c.id=any(coalesce(e.assigned_clients,array[]::uuid[])) or exists(select 1 from public.cases ca where ca.client_id=c.id and ca.id=any(coalesce(e.assigned_cases,array[]::uuid[]))))) $$;
grant execute on function public.employee_can_access_case(uuid,uuid) to authenticated, service_role; grant execute on function public.employee_can_access_client(uuid,uuid) to authenticated, service_role;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients for select to authenticated using (public.employee_can_access_client(id,auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases for select to authenticated using (public.employee_can_access_case(id,auth.uid()));
-- ===== 20260627185004_4971143f-1320-4c5a-82ff-30e96f74520a.sql =====
create table if not exists public.sessions (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, case_id uuid not null references public.cases(id) on delete cascade, session_date timestamptz not null, court text, room text, status public.session_status not null default 'scheduled', notes text, outcome text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_sessions_owner on public.sessions(owner_id); CREATE INDEX IF NOT EXISTS if not exists idx_sessions_case on public.sessions(case_id); CREATE INDEX IF NOT EXISTS if not exists idx_sessions_date on public.sessions(session_date);
grant select,insert,update,delete on public.sessions to authenticated; grant all on public.sessions to service_role; alter table public.sessions enable row level security;
drop policy if exists "owner manage sessions" on public.sessions; drop policy if exists "client reads sessions" on public.sessions; drop policy if exists "employee reads sessions" on public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions for select to authenticated using (case_id in (select id from public.cases where client_id in (select id from public.clients where portal_user_id=auth.uid())));
DROP POLICY IF EXISTS "employee reads sessions" ON public.sessions;
CREATE POLICY "employee reads sessions" ON public.sessions for select to authenticated using (public.employee_can_access_case(case_id, auth.uid()));
drop trigger if exists trg_sessions_updated on public.sessions; DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
create trigger trg_sessions_updated before update on public.sessions for each row execute function public.update_updated_at_column();

create table if not exists public.documents (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, case_id uuid references public.cases(id) on delete cascade, doc_type public.document_type not null default 'other', title text not null, description text, storage_path text, file_name text, file_size bigint, mime_type text, filed_date date, judgment_date date, court text, circuit_number text, appeal_deadline date, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_documents_owner on public.documents(owner_id); CREATE INDEX IF NOT EXISTS if not exists idx_documents_case on public.documents(case_id);
grant select,insert,update,delete on public.documents to authenticated; grant all on public.documents to service_role; alter table public.documents enable row level security;
drop policy if exists "owner manage documents" on public.documents; drop policy if exists "client reads case documents" on public.documents; drop policy if exists "employee reads assigned documents" on public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents for select to authenticated using (case_id in (select id from public.cases where client_id in (select id from public.clients where portal_user_id=auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents for select to authenticated using (case_id is not null and public.employee_can_access_case(case_id, auth.uid()));
drop trigger if exists trg_documents_updated on public.documents; DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
create trigger trg_documents_updated before update on public.documents for each row execute function public.update_updated_at_column();
create or replace function public.set_appeal_deadline() returns trigger language plpgsql set search_path=public as $$ begin if new.doc_type='judgment_non_final' and new.judgment_date is not null then new.appeal_deadline:=new.judgment_date + interval '30 days'; end if; return new; end $$;
drop trigger if exists trg_documents_appeal on public.documents; DROP TRIGGER IF EXISTS trg_documents_appeal ON public.documents;
create trigger trg_documents_appeal before insert or update on public.documents for each row execute function public.set_appeal_deadline();

create table if not exists public.document_permissions (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, document_id uuid not null references public.documents(id) on delete cascade, employee_id uuid references public.employees(id) on delete cascade, permission public.doc_permission not null default 'view', created_at timestamptz not null default now(), unique(document_id,employee_id,permission));
grant select,insert,update,delete on public.document_permissions to authenticated; grant all on public.document_permissions to service_role; alter table public.document_permissions enable row level security;
drop policy if exists "owner manage document permissions" on public.document_permissions; drop policy if exists "employee reads own document permissions" on public.document_permissions;
DROP POLICY IF EXISTS "owner manage document permissions" ON public.document_permissions;
CREATE POLICY "owner manage document permissions" ON public.document_permissions for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "employee reads own document permissions" ON public.document_permissions;
CREATE POLICY "employee reads own document permissions" ON public.document_permissions for select to authenticated using (employee_id in (select id from public.employees where user_id=auth.uid()));
create or replace function public.has_doc_permission(_case_id uuid,_user_id uuid,_perm public.doc_permission) returns boolean language sql stable security invoker set search_path=public as $$ select public.employee_can_access_case(_case_id,_user_id) or exists(select 1 from public.employees e join public.document_permissions dp on dp.employee_id=e.id join public.documents d on d.id=dp.document_id where e.user_id=_user_id and d.case_id=_case_id and dp.permission in (_perm,'manage')) $$;
revoke all on function public.has_doc_permission(uuid,uuid,public.doc_permission) from public, anon; grant execute on function public.has_doc_permission(uuid,uuid,public.doc_permission) to authenticated, service_role;

create table if not exists public.powers_of_attorney (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, client_id uuid references public.clients(id) on delete set null, wakalah_number text not null, issuer_name text, agent_name text, issuer_id_number text, agent_id_number text, issue_date date, expiry_date date, scope text, status public.wakalah_status not null default 'active', najiz_id text, najiz_synced_at timestamptz, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_powers_owner on public.powers_of_attorney(owner_id); CREATE UNIQUE INDEX IF NOT EXISTS if not exists uniq_powers_najiz on public.powers_of_attorney(owner_id,najiz_id) where najiz_id is not null;
grant select,insert,update,delete on public.powers_of_attorney to authenticated; grant all on public.powers_of_attorney to service_role; alter table public.powers_of_attorney enable row level security;
drop policy if exists "owner manage powers" on public.powers_of_attorney; drop policy if exists "client reads own powers" on public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney for select to authenticated using (client_id in (select id from public.clients where portal_user_id=auth.uid()));
drop trigger if exists trg_powers_updated on public.powers_of_attorney; DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
create trigger trg_powers_updated before update on public.powers_of_attorney for each row execute function public.update_updated_at_column();

create table if not exists public.executions (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, case_id uuid references public.cases(id) on delete set null, client_id uuid references public.clients(id) on delete set null, execution_number text not null, court text, amount numeric(14,2), debtor_name text, status public.execution_status not null default 'pending', filed_date date, najiz_id text, najiz_synced_at timestamptz, notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_executions_owner on public.executions(owner_id); CREATE UNIQUE INDEX IF NOT EXISTS if not exists uniq_executions_najiz on public.executions(owner_id,najiz_id) where najiz_id is not null;
grant select,insert,update,delete on public.executions to authenticated; grant all on public.executions to service_role; alter table public.executions enable row level security;
drop policy if exists "owner manage executions" on public.executions; drop policy if exists "client reads own executions" on public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions for select to authenticated using (client_id in (select id from public.clients where portal_user_id=auth.uid()));
drop trigger if exists trg_executions_updated on public.executions; DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
create trigger trg_executions_updated before update on public.executions for each row execute function public.update_updated_at_column();

create table if not exists public.tasks (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, employee_id uuid references public.employees(id) on delete set null, case_id uuid references public.cases(id) on delete set null, title text not null, description text, due_date date, status public.task_status not null default 'todo', priority public.task_priority not null default 'medium', completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
CREATE INDEX IF NOT EXISTS if not exists idx_tasks_owner on public.tasks(owner_id); CREATE INDEX IF NOT EXISTS if not exists idx_tasks_employee on public.tasks(employee_id); CREATE INDEX IF NOT EXISTS if not exists idx_tasks_case on public.tasks(case_id);
grant select,insert,update,delete on public.tasks to authenticated; grant all on public.tasks to service_role; alter table public.tasks enable row level security;
drop policy if exists "owner manage tasks" on public.tasks; drop policy if exists "employee read assigned tasks" on public.tasks; drop policy if exists "employee updates assigned tasks" on public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks for select to authenticated using (employee_id in (select id from public.employees where user_id=auth.uid() and is_active));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks for update to authenticated using (employee_id in (select id from public.employees where user_id=auth.uid() and is_active)) with check (employee_id in (select id from public.employees where user_id=auth.uid() and is_active));
drop trigger if exists trg_tasks_updated on public.tasks; DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
create trigger trg_tasks_updated before update on public.tasks for each row execute function public.update_updated_at_column();
-- ===== 20260627185048_d2dc7c14-a6ab-4d28-9ae3-13fac0c1a79c.sql =====
create schema if not exists private;

create or replace function private.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role);
$$;

create or replace function private.employee_can_access_case(_case_id uuid, _user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.employees e
    join public.cases c on c.id = _case_id
    where e.user_id = _user_id
      and e.is_active = true
      and e.owner_id = c.owner_id
      and (
        c.assigned_employee_id = e.id
        or c.id = any(coalesce(e.assigned_cases, array[]::uuid[]))
        or c.client_id = any(coalesce(e.assigned_clients, array[]::uuid[]))
      )
  );
$$;

create or replace function private.employee_can_access_client(_client_id uuid, _user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.employees e
    join public.clients cl on cl.id = _client_id
    where e.user_id = _user_id
      and e.is_active = true
      and e.owner_id = cl.owner_id
      and (
        _client_id = any(coalesce(e.assigned_clients, array[]::uuid[]))
        or exists (
          select 1 from public.cases c
          where c.client_id = _client_id
            and (c.assigned_employee_id = e.id or c.id = any(coalesce(e.assigned_cases, array[]::uuid[])))
        )
      )
  );
$$;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;
revoke all on function private.has_role(uuid, public.app_role) from public, anon, authenticated;
revoke all on function private.employee_can_access_case(uuid, uuid) from public, anon, authenticated;
revoke all on function private.employee_can_access_client(uuid, uuid) from public, anon, authenticated;
grant execute on function private.has_role(uuid, public.app_role) to service_role;
grant execute on function private.employee_can_access_case(uuid, uuid) to service_role;
grant execute on function private.employee_can_access_client(uuid, uuid) to service_role;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$ select private.has_role(_user_id, _role); $$;

create or replace function public.employee_can_access_case(_case_id uuid, _user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$ select private.employee_can_access_case(_case_id, _user_id); $$;

create or replace function public.employee_can_access_client(_client_id uuid, _user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$ select private.employee_can_access_client(_client_id, _user_id); $$;

revoke all on function public.has_role(uuid, public.app_role) from public, anon, authenticated;
revoke all on function public.employee_can_access_case(uuid, uuid) from public, anon, authenticated;
revoke all on function public.employee_can_access_client(uuid, uuid) from public, anon, authenticated;
grant execute on function public.has_role(uuid, public.app_role) to service_role;
grant execute on function public.employee_can_access_case(uuid, uuid) to service_role;
grant execute on function public.employee_can_access_client(uuid, uuid) to service_role;

revoke all on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to service_role;

drop policy if exists "employee reads assigned cases" on public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases for select to authenticated using (private.employee_can_access_case(id, auth.uid()));

drop policy if exists "employee reads assigned clients" on public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients for select to authenticated using (private.employee_can_access_client(id, auth.uid()));

drop policy if exists "admins read all roles" on public.user_roles;
DROP POLICY IF EXISTS "admins read all roles" ON public.user_roles;
CREATE POLICY "admins read all roles" ON public.user_roles for select to authenticated using (private.has_role(auth.uid(), 'admin'));

drop policy if exists "employee reads sessions" on public.sessions;
DROP POLICY IF EXISTS "employee reads sessions" ON public.sessions;
CREATE POLICY "employee reads sessions" ON public.sessions for select to authenticated using (private.employee_can_access_case(case_id, auth.uid()));

drop policy if exists "employee reads assigned documents" on public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents for select to authenticated using (case_id is not null and private.employee_can_access_case(case_id, auth.uid()));
-- ===== 20260627192637_e36c13e5-d2f4-46b1-bc4c-0c301d27067a.sql =====
-- ==== chunk 0: foundational types, profiles, user_roles, cases, sessions, documents ====

DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;
DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other',
  status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE,
  description TEXT, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled',
  notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT, storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (
  case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
);
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
-- ===== 20260627193443_f3c5f906-b504-4666-b1d0-6119f9bf95ae.sql =====
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;
DO $mig$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $mig$;

CREATE TABLE IF NOT EXISTS public.powers_of_attorney (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status public.wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status public.execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT, phone TEXT, email TEXT,
  residence_expiry DATE, job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE, is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.cases DROP CONSTRAINT IF EXISTS cases_assigned_employee_id_fkey;
ALTER TABLE public.cases ADD CONSTRAINT cases_assigned_employee_id_fkey FOREIGN KEY (assigned_employee_id) REFERENCES public.employees(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status public.task_status NOT NULL DEFAULT 'todo',
  priority public.task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL,
  channel public.notification_channel NOT NULL DEFAULT 'whatsapp',
  status public.notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer', 'employee')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT, user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

CREATE TABLE IF NOT EXISTS public.saved_filters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, name TEXT NOT NULL,
  filters JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, name)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  sessions JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,48]}'::jsonb,
  tasks JSONB NOT NULL DEFAULT '{"toast":true,"email":false,"lead_hours":[24]}'::jsonb,
  appeals JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,72]}'::jsonb,
  channels JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"whatsapp":false,"sms":false}'::jsonb,
  quiet_hours JSONB NOT NULL DEFAULT '{"enabled":false,"start":"22:00","end":"07:00"}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission public.doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, user_id, permission)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.secure_secrets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, key TEXT NOT NULL,
  ciphertext TEXT NOT NULL, iv TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, key)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.session_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lead_hours INT NOT NULL,
  sent_at TIMESTAMPTZ, status TEXT NOT NULL DEFAULT 'pending', error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, lead_hours)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
GRANT SELECT ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension',
  kind TEXT NOT NULL DEFAULT 'unknown',
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  error_message TEXT, raw_payload JSONB, trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT, UPDATE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE, label TEXT,
  last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.user_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  sidebar_width INTEGER NOT NULL DEFAULT 288,
  sidebar_collapsed BOOLEAN NOT NULL DEFAULT false,
  dashboard_cards JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;
GRANT ALL ON public.user_preferences TO service_role;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP POLICY IF EXISTS "admins read all roles" ON public.user_roles;
DROP POLICY IF EXISTS "admins read all roles" ON public.user_roles;
CREATE POLICY "admins read all roles" ON public.user_roles FOR SELECT TO authenticated USING (public.has_role(auth.uid(), 'admin'));

DO $mig$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.cases; EXCEPTION WHEN duplicate_object THEN NULL; WHEN others THEN NULL; END $mig$;
DO $mig$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions; EXCEPTION WHEN duplicate_object THEN NULL; WHEN others THEN NULL; END $mig$;
DO $mig$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN duplicate_object THEN NULL; WHEN others THEN NULL; END $mig$;
DO $mig$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.documents; EXCEPTION WHEN duplicate_object THEN NULL; WHEN others THEN NULL; END $mig$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;
-- ===== 20260627193539_7d4455f3-4edf-4c2e-a458-8aeaa4cbdfef.sql =====
-- ============================================================
-- employee_messages (internal staff chat)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_pair ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = sender_id
  AND (auth.uid() = owner_id OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id))
  AND (recipient_id = owner_id OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = recipient_id AND e.owner_id = employee_messages.owner_id))
);
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

DO $mig$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages; EXCEPTION WHEN duplicate_object THEN NULL; WHEN others THEN NULL; END $mig$;
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;

-- ============================================================
-- Reminder enqueue functions
-- ============================================================
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[7, 24, 48] LOOP
    WITH due AS (
      SELECT s.id AS session_id, s.owner_id, lead_h AS lh
      FROM public.sessions s
      WHERE s.status = 'scheduled'
        AND s.session_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                              AND  now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
    SELECT owner_id, session_id, lh FROM due
    ON CONFLICT (session_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT := 0;
BEGIN
  -- Placeholder: no separate task_reminders table; we surface upcoming tasks via notifications elsewhere.
  -- Returns 0 to satisfy the cron endpoint contract.
  RETURN n;
END $$;

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT  EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

-- ============================================================
-- Private schema (security-definer helpers hidden from API)
-- ============================================================
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO service_role;

CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION private.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = c.owner_id
      AND (c.assigned_employee_id = e.id
           OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[]))
           OR c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
  );
$$;

CREATE OR REPLACE FUNCTION private.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = cl.owner_id
      AND (_client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[]))
           OR EXISTS (SELECT 1 FROM public.cases c WHERE c.client_id = _client_id
                       AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))))
  );
$$;

REVOKE EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) TO service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_client(uuid, uuid) TO service_role;

-- Public wrappers (security invoker) used by RLS policies
CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, private AS $$
  SELECT private.employee_can_access_case(_case_id, _user_id);
$$;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, private AS $$
  SELECT private.employee_can_access_client(_client_id, _user_id);
$$;

-- Tighten SECURITY DEFINER grants for linter
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO service_role;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;

-- Employee read policies via public wrappers
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (public.employee_can_access_case(id, auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (public.employee_can_access_client(id, auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (public.employee_can_access_case(case_id, auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid()));
-- ===== 20260627194551_c19b1f2b-bd10-4f9c-b271-416aa4020f9e.sql =====

-- RLS policies for case-documents bucket
DROP POLICY IF EXISTS "case_documents_select" ON storage.objects;
CREATE POLICY "case_documents_select" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'case-documents' AND (
    auth.uid()::text = (storage.foldername(name))[1]
    OR EXISTS (
      SELECT 1 FROM public.cases c
      WHERE c.id::text = (storage.foldername(name))[2]
        AND (
          c.owner_id = auth.uid()
          OR public.employee_can_access_case(c.id, auth.uid())
          OR EXISTS (SELECT 1 FROM public.clients cl WHERE cl.id = c.client_id AND cl.portal_user_id = auth.uid())
        )
    )
  )
);

DROP POLICY IF EXISTS "case_documents_insert" ON storage.objects;
CREATE POLICY "case_documents_insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "case_documents_update" ON storage.objects;
CREATE POLICY "case_documents_update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1])
WITH CHECK (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "case_documents_delete" ON storage.objects;
CREATE POLICY "case_documents_delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

-- ===== 20260628035221_2f13926a-3b53-46a0-8aef-c1467ebdaf31.sql =====
CREATE TABLE IF NOT EXISTS public.test_repair_probe (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.test_repair_probe TO authenticated;
GRANT ALL ON public.test_repair_probe TO service_role;
ALTER TABLE public.test_repair_probe ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own probe" ON public.test_repair_probe;
DROP POLICY IF EXISTS "users manage own probe" ON public.test_repair_probe;
CREATE POLICY "users manage own probe" ON public.test_repair_probe FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
-- ===== 20260628040255_75a663e4-a16f-4a03-9c05-e024666e6151.sql =====
-- Full idempotent repair for the application database

-- Required enum types
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Profiles and roles
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
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
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
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP FUNCTION IF EXISTS public.has_role(uuid, public.app_role);
DROP FUNCTION IF EXISTS public.has_role(public.app_role, uuid);
CREATE OR REPLACE FUNCTION public.has_role(_role public.app_role, _user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) TO authenticated, service_role;

-- Core tenant tables
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
ALTER TABLE public.clients ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.clients ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

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
  portal_username TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_username TEXT;
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS assigned_cases UUID[] DEFAULT ARRAY[]::UUID[];
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS assigned_clients UUID[] DEFAULT ARRAY[]::UUID[];
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_number TEXT NOT NULL,
  title TEXT NOT NULL,
  court TEXT,
  circuit_number TEXT,
  judge_name TEXT,
  case_type public.case_type NOT NULL DEFAULT 'other',
  status public.case_status NOT NULL DEFAULT 'open',
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ,
  description TEXT,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS assigned_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL;
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS judge_name TEXT;
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS najiz_id TEXT;
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS najiz_synced_at TIMESTAMPTZ;
ALTER TABLE public.cases ALTER COLUMN opened_at TYPE TIMESTAMPTZ USING opened_at::timestamptz;
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = c.owner_id
      AND (
        c.assigned_employee_id = e.id
        OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[]))
        OR (c.client_id IS NOT NULL AND c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = cl.owner_id
      AND (
        cl.id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[]))
        OR EXISTS (
          SELECT 1 FROM public.cases c
          WHERE c.client_id = cl.id
            AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.set_appeal_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.doc_type = 'judgment_non_final' AND NEW.judgment_date IS NOT NULL THEN
    NEW.appeal_deadline := NEW.judgment_date + INTERVAL '30 days';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_documents_appeal ON public.documents;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_case ON public.executions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_client ON public.executions(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  due_date TIMESTAMPTZ,
  status public.task_status NOT NULL DEFAULT 'todo',
  priority public.task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.tasks ALTER COLUMN due_date TYPE TIMESTAMPTZ USING due_date::timestamptz;
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Messaging, notifications, preferences, audit, integration support
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_client ON public.client_notifications(client_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_case ON public.portal_messages(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_role TEXT NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject TEXT,
  body TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_parent ON public.client_inquiries(parent_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  content TEXT,
  body TEXT,
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT employee_messages_has_text CHECK (length(btrim(COALESCE(content, body, ''))) > 0)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_pair ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind TEXT,
  source TEXT NOT NULL DEFAULT 'najiz',
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  raw_payload JSONB,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS kind TEXT;
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS source TEXT NOT NULL DEFAULT 'najiz';
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS status TEXT NOT NULL DEFAULT 'success';
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
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
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission public.doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, user_id, permission)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id uuid, _perm public.doc_permission, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.cases c WHERE c.id = _case_id AND c.owner_id = _user_id)
  OR EXISTS (
    SELECT 1 FROM public.document_permissions dp
    WHERE dp.case_id = _case_id
      AND dp.user_id = _user_id
      AND (dp.permission = _perm OR dp.permission = 'manage')
  );
$$;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) TO authenticated, service_role;

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
GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.task_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours INT NOT NULL,
  sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, lead_hours)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;

-- RLS policies
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (public.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (public.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (public.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
CREATE POLICY "owner reads inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
CREATE POLICY "owner writes inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
CREATE POLICY "owner updates inquiries" ON public.client_inquiries FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries FOR DELETE TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
CREATE POLICY "client reads own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
CREATE POLICY "client writes own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (author_id = auth.uid() AND author_role = 'client' AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id));

DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id AND (owner_id IS NULL OR auth.uid() = owner_id OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id)));
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id OR auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
CREATE POLICY "owner manage session_reminders" ON public.session_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
CREATE POLICY "owner manage task_reminders" ON public.task_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- Update triggers
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auth and maintenance functions
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'), NEW.email)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, updated_at = now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_access_code TEXT DEFAULT NULL, _account_type TEXT DEFAULT 'client')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _uid UUID := auth.uid(); _rows INTEGER := 0;
BEGIN
  IF _uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthenticated'); END IF;
  IF _access_code IS NULL OR length(btrim(_access_code)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_code');
  END IF;
  IF _account_type = 'employee' THEN
    UPDATE public.employees SET user_id = _uid WHERE portal_access_code = _access_code AND user_id IS NULL;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  ELSE
    UPDATE public.clients SET portal_user_id = _uid WHERE portal_access_code = _access_code AND portal_user_id IS NULL;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  END IF;
  RETURN jsonb_build_object('ok', _rows > 0, 'linked', _rows);
END;
$$;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[7, 24, 48] LOOP
    WITH due AS (
      SELECT s.id AS session_id, s.owner_id, lead_h AS lh
      FROM public.sessions s
      WHERE s.status = 'scheduled'
        AND s.session_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                              AND now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
    SELECT owner_id, session_id, lh FROM due
    ON CONFLICT (session_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END;
$$;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[24, 48] LOOP
    WITH due AS (
      SELECT t.id AS task_id, t.owner_id, t.employee_id, lead_h AS lh
      FROM public.tasks t
      WHERE t.status IN ('todo', 'in_progress')
        AND t.due_date IS NOT NULL
        AND t.due_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                           AND now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.task_reminders (owner_id, task_id, employee_id, lead_hours)
    SELECT owner_id, task_id, employee_id, lh FROM due
    ON CONFLICT (task_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END;
$$;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('name','session-reminders','enabled',true,'schedule','every 5 minutes'),
    jsonb_build_object('name','task-reminders','enabled',true,'schedule','every 5 minutes')
  );
$$;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.system_check_inspect()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
  RETURN jsonb_build_object(
    'tables', COALESCE((SELECT jsonb_agg(jsonb_build_object('tablename', tablename, 'rls', rowsecurity)) FROM pg_tables WHERE schemaname = 'public'), '[]'::jsonb),
    'policies', COALESCE((SELECT jsonb_agg(jsonb_build_object('tablename', tablename, 'cnt', cnt)) FROM (SELECT tablename, count(*)::int AS cnt FROM pg_policies WHERE schemaname = 'public' GROUP BY tablename) p), '[]'::jsonb),
    'grants', COALESCE((SELECT jsonb_agg(jsonb_build_object('table_name', table_name, 'grantee', grantee, 'privilege_type', privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public'), '[]'::jsonb),
    'rpcs', COALESCE((SELECT jsonb_agg(proname) FROM pg_proc pr JOIN pg_namespace ns ON ns.oid = pr.pronamespace WHERE ns.nspname = 'public'), '[]'::jsonb),
    'publication', COALESCE((SELECT jsonb_agg(tablename) FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public'), '[]'::jsonb),
    'buckets', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'public', public)) FROM storage.buckets), '[]'::jsonb)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO service_role;

-- Storage object policies for case documents
DROP POLICY IF EXISTS "case documents owner read" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner read" ON storage.objects;
CREATE POLICY "case documents owner read" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "case documents owner insert" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner insert" ON storage.objects;
CREATE POLICY "case documents owner insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "case documents owner update" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner update" ON storage.objects;
CREATE POLICY "case documents owner update" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text) WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "case documents owner delete" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner delete" ON storage.objects;
CREATE POLICY "case documents owner delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Realtime setup where supported
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.cases; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.documents; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.portal_messages; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.client_inquiries; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages; EXCEPTION WHEN OTHERS THEN NULL; END $$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;
ALTER TABLE public.portal_messages REPLICA IDENTITY FULL;
ALTER TABLE public.client_inquiries REPLICA IDENTITY FULL;
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;
-- ===== 20260628040426_38fcd95e-5b4f-44c8-baea-8c2d7bb4c91a.sql =====
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.system_check_inspect() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO service_role;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
-- ===== 20260628140237_f264d6ea-43ed-4966-adbf-2bea83f0a422.sql =====
-- Full idempotent repair for the application database

-- Required enum types
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Profiles and roles
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
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
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
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP FUNCTION IF EXISTS public.has_role(uuid, public.app_role);
DROP FUNCTION IF EXISTS public.has_role(public.app_role, uuid);
CREATE OR REPLACE FUNCTION public.has_role(_role public.app_role, _user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) TO authenticated, service_role;

-- Core tenant tables
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
ALTER TABLE public.clients ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.clients ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_email ON public.clients(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

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
  portal_username TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_username TEXT;
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS assigned_cases UUID[] DEFAULT ARRAY[]::UUID[];
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS assigned_clients UUID[] DEFAULT ARRAY[]::UUID[];
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_user ON public.employees(user_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_email ON public.employees(lower(email));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_number TEXT NOT NULL,
  title TEXT NOT NULL,
  court TEXT,
  circuit_number TEXT,
  judge_name TEXT,
  case_type public.case_type NOT NULL DEFAULT 'other',
  status public.case_status NOT NULL DEFAULT 'open',
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ,
  description TEXT,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS assigned_employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL;
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS judge_name TEXT;
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS najiz_id TEXT;
ALTER TABLE public.cases ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS najiz_synced_at TIMESTAMPTZ;
ALTER TABLE public.cases ALTER COLUMN opened_at TYPE TIMESTAMPTZ USING opened_at::timestamptz;
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = c.owner_id
      AND (
        c.assigned_employee_id = e.id
        OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[]))
        OR (c.client_id IS NOT NULL AND c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = cl.owner_id
      AND (
        cl.id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[]))
        OR EXISTS (
          SELECT 1 FROM public.cases c
          WHERE c.client_id = cl.id
            AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL,
  court TEXT,
  room TEXT,
  session_type TEXT,
  status public.session_status NOT NULL DEFAULT 'scheduled',
  notes TEXT,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_sessions_najiz ON public.sessions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  document_type public.document_type NOT NULL DEFAULT 'other',
  file_url TEXT,
  file_name TEXT,
  file_size BIGINT,
  mime_type TEXT,
  ocr_text TEXT,
  ai_summary TEXT,
  storage_path TEXT,
  tags TEXT[],
  is_confidential BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.documents ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS storage_path TEXT;
ALTER TABLE public.documents ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS tags TEXT[];
ALTER TABLE public.documents ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS is_confidential BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
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
  status public.execution_status NOT NULL DEFAULT 'pending',
  submitted_at DATE,
  najiz_id TEXT,
  najiz_synced_at TIMESTAMPTZ,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT,
  due_date TIMESTAMPTZ,
  status public.task_status NOT NULL DEFAULT 'todo',
  priority public.task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_case ON public.tasks(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  channel public.notification_channel NOT NULL,
  subject TEXT,
  body TEXT NOT NULL,
  status public.notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer', 'employee')),
  message TEXT NOT NULL,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_messages_owner ON public.portal_messages(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_role TEXT NOT NULL CHECK (author_role IN ('client','lawyer','employee')),
  subject TEXT,
  body TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_parent ON public.client_inquiries(parent_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject TEXT,
  body TEXT,
  content TEXT,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT employee_messages_has_text CHECK (length(btrim(COALESCE(content, body, ''))) > 0)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_pair ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sync_token_id UUID,
  kind TEXT,
  source TEXT NOT NULL DEFAULT 'najiz',
  status TEXT NOT NULL DEFAULT 'success',
  received_counts JSONB NOT NULL DEFAULT '{}'::jsonb,
  inserted_counts JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_counts JSONB NOT NULL DEFAULT '{}'::jsonb,
  errors JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS kind TEXT;
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS source TEXT NOT NULL DEFAULT 'najiz';
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS status TEXT NOT NULL DEFAULT 'success';
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
GRANT SELECT, INSERT, UPDATE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT 'Najiz Extension',
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  sidebar_width INT NOT NULL DEFAULT 320,
  sidebar_collapsed BOOLEAN NOT NULL DEFAULT FALSE,
  dashboard_cards JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_preferences TO authenticated;
GRANT ALL ON public.user_preferences TO service_role;
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

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

CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission public.doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, user_id, permission)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id uuid, _perm public.doc_permission, _user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.cases c WHERE c.id = _case_id AND c.owner_id = _user_id)
    OR EXISTS (
      SELECT 1 FROM public.document_permissions dp
      WHERE dp.case_id = _case_id
        AND dp.user_id = _user_id
        AND (dp.permission = _perm OR dp.permission = 'manage')
    );
$$;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) TO authenticated, service_role;

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
GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.task_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours INT NOT NULL,
  sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (task_id, lead_hours)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;

-- RLS policies
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (public.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (public.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (public.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND public.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
CREATE POLICY "owner reads inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
CREATE POLICY "owner writes inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
CREATE POLICY "owner updates inquiries" ON public.client_inquiries FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries FOR DELETE TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
CREATE POLICY "client reads own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid()));
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
CREATE POLICY "client writes own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (author_id = auth.uid() AND author_role = 'client' AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id));

DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id AND (owner_id IS NULL OR auth.uid() = owner_id OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id)));
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id OR auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
CREATE POLICY "owner manage session_reminders" ON public.session_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
CREATE POLICY "owner manage task_reminders" ON public.task_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- Update triggers
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Auth and maintenance functions
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'), NEW.email)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email, updated_at = now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_access_code TEXT DEFAULT NULL, _account_type TEXT DEFAULT 'client')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  uid uuid := auth.uid();
  em text;
  linked uuid;
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT email INTO em FROM auth.users WHERE id = uid;
  IF lower(coalesce(_account_type, 'client')) = 'employee' THEN
    UPDATE public.employees e
    SET user_id = uid
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(em, ''))
        AND (_access_code IS NULL OR portal_access_code IS NULL OR portal_access_code = _access_code)
      ORDER BY created_at DESC LIMIT 1
    )
    RETURNING id INTO linked;
    IF linked IS NULL THEN SELECT id INTO linked FROM public.employees WHERE user_id = uid LIMIT 1; END IF;
    IF linked IS NULL THEN RETURN jsonb_build_object('linked', false, 'role', 'employee', 'reason', 'employee_not_found'); END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked);
  ELSE
    UPDATE public.clients c
    SET portal_user_id = uid
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(em, ''))
        AND (_access_code IS NULL OR portal_access_code IS NULL OR portal_access_code = _access_code)
      ORDER BY created_at DESC LIMIT 1
    )
    RETURNING id INTO linked;
    IF linked IS NULL THEN SELECT id INTO linked FROM public.clients WHERE portal_user_id = uid LIMIT 1; END IF;
    IF linked IS NULL THEN RETURN jsonb_build_object('linked', false, 'role', 'client', 'reason', 'client_not_found'); END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.set_appeal_deadline()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RETURN NEW;
END;
$$;
GRANT EXECUTE ON FUNCTION public.set_appeal_deadline() TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[7, 24, 48] LOOP
    WITH due AS (
      SELECT s.id AS session_id, s.owner_id, lead_h AS lh FROM public.sessions s
      WHERE s.status = 'scheduled'
        AND s.session_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                              AND now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
    SELECT owner_id, session_id, lh FROM due
    ON CONFLICT (session_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END;
$$;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[24, 48] LOOP
    WITH due AS (
      SELECT t.id AS task_id, t.owner_id, t.employee_id, lead_h AS lh
      FROM public.tasks t
      WHERE t.status IN ('todo', 'in_progress')
        AND t.due_date IS NOT NULL
        AND t.due_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                           AND now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.task_reminders (owner_id, task_id, employee_id, lead_hours)
    SELECT owner_id, task_id, employee_id, lh FROM due
    ON CONFLICT (task_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END;
$$;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('name','session-reminders','enabled',true,'schedule','every 5 minutes'),
    jsonb_build_object('name','task-reminders','enabled',true,'schedule','every 5 minutes')
  );
$$;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.system_check_inspect()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
  RETURN jsonb_build_object(
    'tables', COALESCE((SELECT jsonb_agg(jsonb_build_object('tablename', tablename, 'rls', rowsecurity)) FROM pg_tables WHERE schemaname = 'public'), '[]'::jsonb),
    'policies', COALESCE((SELECT jsonb_agg(jsonb_build_object('tablename', tablename, 'cnt', cnt)) FROM (SELECT tablename, count(*)::int AS cnt FROM pg_policies WHERE schemaname = 'public' GROUP BY tablename) p), '[]'::jsonb),
    'grants', COALESCE((SELECT jsonb_agg(jsonb_build_object('table_name', table_name, 'grantee', grantee, 'privilege_type', privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public'), '[]'::jsonb),
    'rpcs', COALESCE((SELECT jsonb_agg(proname) FROM pg_proc pr JOIN pg_namespace ns ON ns.oid = pr.pronamespace WHERE ns.nspname = 'public'), '[]'::jsonb),
    'publication', COALESCE((SELECT jsonb_agg(tablename) FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public'), '[]'::jsonb),
    'buckets', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', name, 'public', public)) FROM storage.buckets), '[]'::jsonb)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO service_role;

-- Storage object policies for case documents
DROP POLICY IF EXISTS "case documents owner read" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner read" ON storage.objects;
CREATE POLICY "case documents owner read" ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "case documents owner insert" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner insert" ON storage.objects;
CREATE POLICY "case documents owner insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "case documents owner update" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner update" ON storage.objects;
CREATE POLICY "case documents owner update" ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text) WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "case documents owner delete" ON storage.objects;
DROP POLICY IF EXISTS "case documents owner delete" ON storage.objects;
CREATE POLICY "case documents owner delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

-- Realtime setup where supported
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.cases; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.documents; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.portal_messages; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.client_inquiries; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages; EXCEPTION WHEN OTHERS THEN NULL; END $$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;
ALTER TABLE public.portal_messages REPLICA IDENTITY FULL;
ALTER TABLE public.client_inquiries REPLICA IDENTITY FULL;
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;

-- Apply pending hardening and compatibility fixes
ALTER TABLE public.powers_of_attorney
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS issuer_id_number TEXT,
  ADD COLUMN IF NOT EXISTS agent_id_number  TEXT;

DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages
  FOR ALL TO authenticated
  USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
  WITH CHECK (
    client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
    AND sender_id = auth.uid()
    AND sender_role = 'client'
  );

DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = actor_id);
-- ===== 20260628140512_e2c1b902-416b-4e78-9d33-ec319b605313.sql =====
ALTER TABLE public.documents
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS doc_type public.document_type NOT NULL DEFAULT 'other',
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS filed_date DATE,
  ADD COLUMN IF NOT EXISTS judgment_date DATE,
  ADD COLUMN IF NOT EXISTS court TEXT,
  ADD COLUMN IF NOT EXISTS circuit_number TEXT,
  ADD COLUMN IF NOT EXISTS appeal_deadline DATE;

UPDATE public.documents
SET doc_type = document_type
WHERE doc_type IS NULL AND document_type IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_document_type_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.doc_type IS NULL AND NEW.document_type IS NOT NULL THEN
    NEW.doc_type := NEW.document_type;
  ELSIF NEW.document_type IS NULL AND NEW.doc_type IS NOT NULL THEN
    NEW.document_type := NEW.doc_type;
  ELSIF NEW.doc_type IS DISTINCT FROM OLD.doc_type THEN
    NEW.document_type := NEW.doc_type;
  ELSIF NEW.document_type IS DISTINCT FROM OLD.document_type THEN
    NEW.doc_type := NEW.document_type;
  END IF;

  IF NEW.doc_type = 'judgment_non_final' AND NEW.judgment_date IS NOT NULL THEN
    NEW.appeal_deadline := NEW.judgment_date + INTERVAL '30 days';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documents_sync_type ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_sync_type ON public.documents;
CREATE TRIGGER trg_documents_sync_type
BEFORE INSERT OR UPDATE ON public.documents
FOR EACH ROW EXECUTE FUNCTION public.sync_document_type_columns();

ALTER TABLE public.client_notifications
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS message TEXT,
  ADD COLUMN IF NOT EXISTS template TEXT,
  ADD COLUMN IF NOT EXISTS error_message TEXT;
ALTER TABLE public.client_notifications ALTER COLUMN body DROP NOT NULL;
UPDATE public.client_notifications SET message = body WHERE message IS NULL AND body IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_client_notification_message()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.message IS NULL AND NEW.body IS NOT NULL THEN
    NEW.message := NEW.body;
  ELSIF NEW.body IS NULL AND NEW.message IS NOT NULL THEN
    NEW.body := NEW.message;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_client_notifications_sync_message ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_client_notifications_sync_message ON public.client_notifications;
CREATE TRIGGER trg_client_notifications_sync_message
BEFORE INSERT OR UPDATE ON public.client_notifications
FOR EACH ROW EXECUTE FUNCTION public.sync_client_notification_message();

ALTER TABLE public.najiz_sync_logs
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS items_count INT,
  ADD COLUMN IF NOT EXISTS inserted_count INT,
  ADD COLUMN IF NOT EXISTS updated_count INT,
  ADD COLUMN IF NOT EXISTS error_message TEXT,
  ADD COLUMN IF NOT EXISTS raw_payload JSONB;

ALTER TABLE public.sync_tokens
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS label TEXT,
  ADD COLUMN IF NOT EXISTS is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
UPDATE public.sync_tokens SET label = name WHERE label IS NULL AND name IS NOT NULL;
UPDATE public.sync_tokens SET is_revoked = TRUE WHERE revoked_at IS NOT NULL;

ALTER TABLE public.executions
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS debtor_name TEXT,
  ADD COLUMN IF NOT EXISTS filed_date DATE;
UPDATE public.executions SET filed_date = submitted_at WHERE filed_date IS NULL AND submitted_at IS NOT NULL;

ALTER TABLE public.sessions
  ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS outcome TEXT;
-- ===== 20260628144330_2ae8ab71-970a-4461-a64b-1698fe6410d1.sql =====
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN DO $idem$ BEGIN
  CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage');
EXCEPTION WHEN duplicate_object THEN NULL;
END $idem$;
-- consumed; EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
DROP POLICY IF EXISTS "users view own profile" ON public.profiles;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
DROP TRIGGER IF EXISTS trg_profiles_updated ON public.profiles;
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role app_role)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email), NEW.email);
  INSERT INTO public.user_roles (user_id, role) VALUES (NEW.id, 'lawyer');
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT,
  address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_owner ON public.clients(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
DROP TRIGGER IF EXISTS trg_clients_updated ON public.clients;
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  assigned_employee_id UUID,
  case_number TEXT NOT NULL, title TEXT NOT NULL, court TEXT, circuit_number TEXT,
  case_type case_type NOT NULL DEFAULT 'other',
  status case_status NOT NULL DEFAULT 'open',
  opened_at DATE NOT NULL DEFAULT CURRENT_DATE, closed_at DATE,
  description TEXT, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_owner ON public.cases(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
DROP TRIGGER IF EXISTS trg_cases_updated ON public.cases;
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled',
  notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_case ON public.sessions(case_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
DROP TRIGGER IF EXISTS trg_sessions_updated ON public.sessions;
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT,
  storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT,
  appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_owner ON public.documents(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
DROP TRIGGER IF EXISTS trg_documents_updated ON public.documents;
CREATE TRIGGER trg_documents_updated BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
DROP TRIGGER IF EXISTS trg_documents_appeal ON public.documents;
CREATE TRIGGER trg_documents_appeal BEFORE INSERT OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.set_appeal_deadline();

CREATE TABLE IF NOT EXISTS public.powers_of_attorney (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_powers_client ON public.powers_of_attorney(client_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
DROP TRIGGER IF EXISTS trg_powers_updated ON public.powers_of_attorney;
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT,
  amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending',
  filed_date DATE, najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX IF NOT EXISTS IF NOT EXISTS uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
DROP TRIGGER IF EXISTS trg_executions_updated ON public.executions;
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, nationality TEXT, national_id TEXT,
  phone TEXT, email TEXT, residence_expiry DATE,
  job_title TEXT, qualification TEXT,
  direct_manager_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  start_date DATE, end_date DATE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  permissions JSONB DEFAULT '[]'::jsonb,
  assigned_cases UUID[] DEFAULT ARRAY[]::UUID[],
  assigned_clients UUID[] DEFAULT ARRAY[]::UUID[],
  portal_access_code TEXT,
  portal_username TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
DROP TRIGGER IF EXISTS trg_employees_updated ON public.employees;
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  title TEXT NOT NULL, description TEXT, due_date DATE,
  status task_status NOT NULL DEFAULT 'todo',
  priority task_priority NOT NULL DEFAULT 'medium',
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
DROP TRIGGER IF EXISTS trg_tasks_updated ON public.tasks;
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.client_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  template TEXT, message TEXT NOT NULL, body TEXT,
  channel notification_channel NOT NULL DEFAULT 'whatsapp',
  status notification_status NOT NULL DEFAULT 'draft',
  scheduled_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
DROP TRIGGER IF EXISTS trg_notifs_updated ON public.client_notifications;
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.portal_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('client', 'lawyer')),
  sender_id UUID, subject TEXT, message TEXT NOT NULL,
  parent_id UUID REFERENCES public.portal_messages(id) ON DELETE CASCADE,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated
  USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
  WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension',
  kind TEXT, status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  error_message TEXT, raw_payload JSONB, trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT, name TEXT, last_used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ, revoked_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

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
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
DROP TRIGGER IF EXISTS trg_user_preferences_updated ON public.user_preferences;
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT, user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_audit_created ON public.audit_log(created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

CREATE TABLE IF NOT EXISTS public.saved_filters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, name TEXT NOT NULL,
  filters JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, name)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sf_owner_scope ON public.saved_filters(owner_id, scope);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
DROP TRIGGER IF EXISTS trg_sf_updated ON public.saved_filters;
CREATE TRIGGER trg_sf_updated BEFORE UPDATE ON public.saved_filters FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

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
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
DROP TRIGGER IF EXISTS trg_np_updated ON public.notification_preferences;
CREATE TRIGGER trg_np_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  permission doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (case_id, user_id, permission)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_docperm_case_user ON public.document_permissions(case_id, user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

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
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_secsec_owner_scope ON public.secure_secrets(owner_id, scope);
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
DROP TRIGGER IF EXISTS trg_secsec_updated ON public.secure_secrets;
CREATE TRIGGER trg_secsec_updated BEFORE UPDATE ON public.secure_secrets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.session_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lead_hours INT NOT NULL,
  sent_at TIMESTAMPTZ, status TEXT NOT NULL DEFAULT 'pending', error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (session_id, lead_hours)
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_sr_pending ON public.session_reminders(status, created_at);
GRANT SELECT ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  subject TEXT, message TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_client_inquiries_owner ON public.client_inquiries(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner manage inquiries" ON public.client_inquiries;
CREATE POLICY "owner manage inquiries" ON public.client_inquiries FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "client manage own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client manage own inquiries" ON public.client_inquiries;
CREATE POLICY "client manage own inquiries" ON public.client_inquiries FOR ALL TO authenticated
  USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
  WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
DROP TRIGGER IF EXISTS trg_client_inquiries_updated ON public.client_inquiries;
DROP TRIGGER IF EXISTS trg_client_inquiries_updated ON public.client_inquiries;
CREATE TRIGGER trg_client_inquiries_updated BEFORE UPDATE ON public.client_inquiries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE CASCADE,
  sender_id UUID, recipient_id UUID,
  subject TEXT, message TEXT NOT NULL,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage emp msgs" ON public.employee_messages;
DROP POLICY IF EXISTS "owner manage emp msgs" ON public.employee_messages;
CREATE POLICY "owner manage emp msgs" ON public.employee_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own messages" ON public.employee_messages;
DROP POLICY IF EXISTS "employee reads own messages" ON public.employee_messages;
CREATE POLICY "employee reads own messages" ON public.employee_messages FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
-- ===== 20260628144421_0a4d7691-2597-471e-a345-2185334a425f.sql =====
-- Recreate with proper schema (no data yet)
DROP TABLE IF EXISTS public.employee_messages CASCADE;
CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_emp_msg_pair  ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages
  FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages
  FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      auth.uid() = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id)
    )
    AND (
      recipient_id = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = recipient_id AND e.owner_id = employee_messages.owner_id)
    )
  );
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages
  FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages
  FOR DELETE TO authenticated USING (auth.uid() = sender_id);
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;

DROP TABLE IF EXISTS public.client_inquiries CASCADE;
CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id UUID NOT NULL,
  author_role TEXT NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject TEXT,
  body TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_parent ON public.client_inquiries(parent_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
CREATE POLICY "owner reads inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
CREATE POLICY "owner writes inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
CREATE POLICY "owner updates inquiries" ON public.client_inquiries FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries FOR DELETE TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
CREATE POLICY "client reads own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid())
);
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
CREATE POLICY "client writes own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid() AND author_role = 'client'
  AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id)
);

-- Lock down SECURITY DEFINER functions (linter warnings 1-4)
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO service_role;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
-- ===== 20260628144533_ff4e9b32-9808-4fc2-8b77-07bc0cf8b2ea.sql =====
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = actor_id);
-- ===== 20260628150230_8edf87eb-af1b-4a17-801f-5fe8a07c351d.sql =====
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.employees
      WHERE employees.id = tasks.employee_id
        AND employees.user_id = auth.uid()
        AND employees.owner_id = tasks.owner_id
    )
  );

DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.employees
      WHERE employees.id = tasks.employee_id
        AND employees.user_id = auth.uid()
        AND employees.owner_id = tasks.owner_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.employees
      WHERE employees.id = tasks.employee_id
        AND employees.user_id = auth.uid()
        AND employees.owner_id = tasks.owner_id
    )
  );

DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log
  FOR SELECT TO authenticated
  USING (auth.uid() = owner_id);
-- ===== 20260628161357_c73f9b64-c285-42a4-a365-e6e45312f944.sql =====

DROP POLICY IF EXISTS "case_documents_select_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_update_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_delete_own" ON storage.objects;

DROP POLICY IF EXISTS "case_documents_select_own" ON storage.objects;
CREATE POLICY "case_documents_select_own" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "case_documents_insert_own" ON storage.objects;
CREATE POLICY "case_documents_insert_own" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "case_documents_update_own" ON storage.objects;
CREATE POLICY "case_documents_update_own" ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
)
WITH CHECK (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "case_documents_delete_own" ON storage.objects;
CREATE POLICY "case_documents_delete_own" ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- ===== 20260628173522_fd55920a-fef2-4af3-bfdd-9c433fc5a280.sql =====
-- See /tmp/all_migrations.sql; applying combined schema

-- ===== 20260628173635_64d998f0-c4fc-4f80-a2eb-45b34de9c0c2.sql =====
GRANT ALL ON SCHEMA public TO sandbox_exec;
GRANT ALL ON ALL TABLES IN SCHEMA public TO sandbox_exec;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO sandbox_exec;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO sandbox_exec;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO sandbox_exec;
GRANT CREATE ON DATABASE postgres TO sandbox_exec;
-- ===== 20260628173658_57b2ea1f-4218-4795-87b8-3cb0d40fe671.sql =====
GRANT USAGE ON SCHEMA auth TO sandbox_exec;
GRANT REFERENCES, SELECT ON auth.users TO sandbox_exec;
-- ===== 20260628173721_6d69f215-0b84-45ce-85fd-6896e4b9f4c0.sql =====
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO sandbox_exec;
GRANT ALL ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO sandbox_exec;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO sandbox_exec;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO sandbox_exec;
-- ===== 20260628173754_18580dc0-80cb-4059-9127-156031ad39eb.sql =====
CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  EXECUTE sql;
END;
$$;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO service_role;
-- ===== 20260628173854_2bc44fd5-213b-4734-893d-3f60688bdc21.sql =====
CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN EXECUTE sql; END;
$$;
REVOKE ALL ON FUNCTION public._bootstrap_exec(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO service_role;
-- ===== 20260628174445_cf45874c-a971-4e3c-8d88-70f8191340d3.sql =====
-- Drop the bootstrap helper now that schema is applied.
DROP FUNCTION IF EXISTS public._bootstrap_exec(text);
-- Force schema cache reload
NOTIFY pgrst, 'reload schema';
-- ===== 20260628174502_07204753-5275-4f84-8702-51f93ebd545c.sql =====
CREATE TABLE IF NOT EXISTS public._types_refresh (id int);
DROP TABLE public._types_refresh;
-- ===== 20260628174736_47bbcd11-0fae-43ae-88e9-44ce433321ca.sql =====

CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL DEFAULT 'extension',
  kind TEXT NOT NULL DEFAULT 'unknown',
  status TEXT NOT NULL DEFAULT 'success',
  items_count INTEGER DEFAULT 0,
  inserted_count INTEGER DEFAULT 0,
  updated_count INTEGER DEFAULT 0,
  error_message TEXT,
  raw_payload JSONB,
  trace JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.najiz_sync_logs ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'unknown';
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX IF NOT EXISTS IF NOT EXISTS idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT, UPDATE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- ===== 20260628175047_90147e29-6fd6-4f7e-b312-5f65b2ee6f3a.sql =====

CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  EXECUTE sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERR: ' || SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public._bootstrap_exec(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO postgres, service_role;

-- ===== 20260628175136_001d55f6-25f9-4cd5-8a1a-27c7a48cc83c.sql =====

-- Drop everything in public schema and start fresh
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT CREATE ON SCHEMA public TO postgres, service_role;
GRANT ALL ON SCHEMA public TO postgres;

-- Recreate bootstrap helper
CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  EXECUTE sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERR: ' || SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public._bootstrap_exec(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO postgres, service_role;

-- ===== 20260628175216_bbb2c006-f4fd-43ca-867b-a436a0ae4b36.sql =====
GRANT USAGE ON SCHEMA public TO PUBLIC; GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO PUBLIC;
-- ===== 20260628175409_03f13a41-55de-4089-86e3-582a6961c2ec.sql =====
GRANT USAGE, CREATE ON SCHEMA public TO PUBLIC;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO PUBLIC;
SELECT has_schema_privilege('sandbox_exec','public','USAGE') as ok_sandbox;
-- ===== 20260628175500_b58e543d-8879-4e05-85ac-57a0518a9bde.sql =====

CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  EXECUTE sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERR: ' || SQLERRM;
END;
$$;
GRANT USAGE, CREATE ON SCHEMA public TO PUBLIC;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO PUBLIC;

-- ===== 20260628175536_989e2529-be81-4938-9b22-45ddc0ee0bf3.sql =====
DROP FUNCTION IF EXISTS public._bootstrap_exec(text);
DROP TABLE IF EXISTS public.test_repair_probe;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- ===== 20260628175555_78846c69-bb72-49d7-bb35-263e6f0c6571.sql =====
ALTER TABLE public.employees ADD ADD COLUMN IF NOT EXISTS IF NOT EXISTS portal_access_code TEXT;
-- ===== 20260628182550_fc46631e-c436-40b0-8692-ca34382aeeb6.sql =====

-- 1) Fix audit_log forgery: require owner_id = auth.uid() in WITH CHECK
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = actor_id AND auth.uid() = owner_id);

-- 2) Remove broad peer SELECT policies on employees (sensitive column exposure)
DROP POLICY IF EXISTS "employees read peers in tenant" ON public.employees;
DROP POLICY IF EXISTS "employees read tenant roster" ON public.employees;

-- 3) Safe directory view: peers see only non-sensitive fields, scoped to tenant.
--    SECURITY INVOKER so underlying privileges/RLS apply through view owner=postgres
--    bypass not used; we filter explicitly here.
CREATE OR REPLACE VIEW public.employees_directory
WITH (security_invoker = false) AS
SELECT e.id, e.user_id, e.owner_id, e.full_name, e.job_title, e.is_active
FROM public.employees e
WHERE
  -- Owner of the tenant
  e.owner_id = auth.uid()
  -- Self
  OR e.user_id = auth.uid()
  -- Active employee of the same tenant
  OR EXISTS (
    SELECT 1 FROM public.employees me
    WHERE me.user_id = auth.uid()
      AND me.is_active = true
      AND me.owner_id = e.owner_id
  );

REVOKE ALL ON public.employees_directory FROM PUBLIC, anon;
GRANT SELECT ON public.employees_directory TO authenticated;

-- ===== 20260628182601_0504b055-8068-4bb0-bdba-a0817a939bed.sql =====
ALTER VIEW public.employees_directory SET (security_invoker = true);
-- ===== 20260628182618_1a7f2141-fde2-43a7-96cb-f28a61ff433d.sql =====

DROP VIEW IF EXISTS public.employees_directory;

CREATE OR REPLACE FUNCTION public.get_employees_directory()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  owner_id uuid,
  full_name text,
  job_title text,
  is_active boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT e.id, e.user_id, e.owner_id, e.full_name, e.job_title, e.is_active
  FROM public.employees e
  WHERE auth.uid() IS NOT NULL
    AND (
      e.owner_id = auth.uid()
      OR e.user_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.employees me
        WHERE me.user_id = auth.uid()
          AND me.is_active = true
          AND me.owner_id = e.owner_id
      )
    );
$$;

REVOKE ALL ON FUNCTION public.get_employees_directory() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employees_directory() TO authenticated;

-- ===== 20260625151629_c05a598b-31fa-4cd9-a0a9-95a2ff07883f.sql =====

-- Storage policies for case-documents bucket
DROP POLICY IF EXISTS "owner manages own docs" ON storage.objects;
CREATE POLICY "owner manages own docs" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "client reads own case docs" ON storage.objects;
CREATE POLICY "client reads own case docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'case-documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      JOIN public.cases c ON c.id = d.case_id
      JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = storage.objects.name
        AND cl.portal_user_id = auth.uid()
    )
  );

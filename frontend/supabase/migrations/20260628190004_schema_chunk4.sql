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

CREATE TYPE public.app_role AS ENUM ('admin', 'lawyer', 'employee', 'client');
CREATE TYPE public.case_status AS ENUM ('open', 'in_study', 'closed_final', 'closed_non_final', 'appealed', 'archived');
CREATE TYPE public.case_type AS ENUM ('labor', 'commercial', 'execution', 'civil', 'personal_status', 'administrative', 'criminal', 'other');
CREATE TYPE public.session_status AS ENUM ('scheduled', 'held', 'postponed', 'cancelled');
CREATE TYPE public.document_type AS ENUM ('lawsuit', 'judgment_final', 'judgment_non_final', 'appeal_judgment', 'memorandum_reply', 'session_minutes', 'power_of_attorney', 'evidence', 'other');
CREATE TYPE public.wakalah_status AS ENUM ('active', 'expired', 'revoked');
CREATE TYPE public.execution_status AS ENUM ('pending', 'in_progress', 'completed', 'rejected');
CREATE TYPE public.task_status AS ENUM ('todo', 'in_progress', 'done', 'overdue');
CREATE TYPE public.task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE public.notification_status AS ENUM ('draft', 'scheduled', 'sent', 'failed', 'cancelled');
CREATE TYPE public.notification_channel AS ENUM ('whatsapp', 'sms', 'email');

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT, email TEXT, phone TEXT, avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE TRIGGER trg_profiles_updated BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, role)
);
GRANT SELECT ON public.user_roles TO authenticated;
GRANT ALL ON public.user_roles TO service_role;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
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
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TABLE public.clients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  portal_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  full_name TEXT NOT NULL, national_id TEXT, phone TEXT, email TEXT, address TEXT, notes TEXT, portal_access_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_clients_owner ON public.clients(owner_id);
CREATE INDEX idx_clients_portal ON public.clients(portal_user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.clients TO authenticated;
GRANT ALL ON public.clients TO service_role;
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
CREATE TRIGGER trg_clients_updated BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.cases (
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
CREATE INDEX idx_cases_owner ON public.cases(owner_id);
CREATE INDEX idx_cases_client ON public.cases(client_id);
CREATE UNIQUE INDEX uniq_cases_najiz ON public.cases(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cases TO authenticated;
GRANT ALL ON public.cases TO service_role;
ALTER TABLE public.cases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
CREATE TRIGGER trg_cases_updated BEFORE UPDATE ON public.cases FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID NOT NULL REFERENCES public.cases(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ NOT NULL, court TEXT, room TEXT,
  status session_status NOT NULL DEFAULT 'scheduled', notes TEXT, outcome TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sessions_owner ON public.sessions(owner_id);
CREATE INDEX idx_sessions_case ON public.sessions(case_id);
CREATE INDEX idx_sessions_date ON public.sessions(session_date);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sessions TO authenticated;
GRANT ALL ON public.sessions TO service_role;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  doc_type document_type NOT NULL DEFAULT 'other',
  title TEXT NOT NULL, description TEXT,
  storage_path TEXT, file_name TEXT, file_size BIGINT, mime_type TEXT,
  filed_date DATE, judgment_date DATE, court TEXT, circuit_number TEXT, appeal_deadline DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_documents_owner ON public.documents(owner_id);
CREATE INDEX idx_documents_case ON public.documents(case_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.documents TO authenticated;
GRANT ALL ON public.documents TO service_role;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
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
CREATE TRIGGER trg_documents_appeal BEFORE INSERT OR UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.set_appeal_deadline();

CREATE TABLE public.powers_of_attorney (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  wakalah_number TEXT NOT NULL, issuer_name TEXT, agent_name TEXT,
  issue_date DATE, expiry_date DATE, scope TEXT,
  status wakalah_status NOT NULL DEFAULT 'active',
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_powers_owner ON public.powers_of_attorney(owner_id);
CREATE UNIQUE INDEX uniq_powers_najiz ON public.powers_of_attorney(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.powers_of_attorney TO authenticated;
GRANT ALL ON public.powers_of_attorney TO service_role;
ALTER TABLE public.powers_of_attorney ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE TRIGGER trg_powers_updated BEFORE UPDATE ON public.powers_of_attorney FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.executions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  client_id UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  execution_number TEXT NOT NULL, court TEXT, amount NUMERIC(14,2), debtor_name TEXT,
  status execution_status NOT NULL DEFAULT 'pending', filed_date DATE,
  najiz_id TEXT, najiz_synced_at TIMESTAMPTZ, notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_executions_owner ON public.executions(owner_id);
CREATE UNIQUE INDEX uniq_executions_najiz ON public.executions(owner_id, najiz_id) WHERE najiz_id IS NOT NULL;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.executions TO authenticated;
GRANT ALL ON public.executions TO service_role;
ALTER TABLE public.executions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE TRIGGER trg_executions_updated BEFORE UPDATE ON public.executions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.employees (
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
CREATE INDEX idx_employees_owner ON public.employees(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE TRIGGER trg_employees_updated BEFORE UPDATE ON public.employees FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.tasks (
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
CREATE INDEX idx_tasks_owner ON public.tasks(owner_id);
CREATE INDEX idx_tasks_employee ON public.tasks(employee_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.tasks TO authenticated;
GRANT ALL ON public.tasks TO service_role;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));
CREATE TRIGGER trg_tasks_updated BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.client_notifications (
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
CREATE INDEX idx_notifs_owner ON public.client_notifications(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_notifications TO authenticated;
GRANT ALL ON public.client_notifications TO service_role;
ALTER TABLE public.client_notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE TRIGGER trg_notifs_updated BEFORE UPDATE ON public.client_notifications FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE public.portal_messages (
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
CREATE INDEX idx_portal_owner ON public.portal_messages(owner_id);
CREATE INDEX idx_portal_client ON public.portal_messages(client_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.portal_messages TO authenticated;
GRANT ALL ON public.portal_messages TO service_role;
ALTER TABLE public.portal_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE TABLE public.najiz_sync_logs (
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
CREATE INDEX idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id);
CREATE INDEX idx_najiz_logs_created ON public.najiz_sync_logs(created_at DESC);
GRANT SELECT, INSERT ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);

CREATE TABLE public.sync_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  label TEXT, last_used_at TIMESTAMPTZ, expires_at TIMESTAMPTZ,
  is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE public.user_preferences (
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
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE TRIGGER trg_user_preferences_updated BEFORE UPDATE ON public.user_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO authenticated, service_role;
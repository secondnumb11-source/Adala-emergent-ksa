-- Idempotent migration: minimum schema needed for build + Team Chat + Bell
-- Safe to re-run.

-- ========= ENUMS =========
DO $$ BEGIN
  CREATE TYPE public.app_role AS ENUM ('admin','lawyer','employee','client');
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
CREATE POLICY "users view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users update own profile" ON public.profiles;
CREATE POLICY "users update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id);
DROP POLICY IF EXISTS "users insert own profile" ON public.profiles;
CREATE POLICY "users insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
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
CREATE INDEX IF NOT EXISTS idx_employees_owner ON public.employees(owner_id);
CREATE INDEX IF NOT EXISTS idx_employees_user  ON public.employees(user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employees TO authenticated;
GRANT ALL ON public.employees TO service_role;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);
DROP POLICY IF EXISTS "employees read peers in tenant" ON public.employees;
CREATE POLICY "employees read peers in tenant" ON public.employees
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.employees me WHERE me.user_id = auth.uid() AND me.owner_id = public.employees.owner_id));
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
  FOR SELECT TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

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
  FOR UPDATE TO authenticated
  USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);

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
CREATE INDEX IF NOT EXISTS idx_sync_tokens_owner ON public.sync_tokens(owner_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.sync_tokens TO authenticated;
GRANT ALL ON public.sync_tokens TO service_role;
ALTER TABLE public.sync_tokens ENABLE ROW LEVEL SECURITY;
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
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage najiz_logs" ON public.najiz_sync_logs;
CREATE POLICY "owner manage najiz_logs" ON public.najiz_sync_logs FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

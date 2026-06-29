
-- Drop the definer views from previous migration
DROP VIEW IF EXISTS public.my_client_row;
DROP VIEW IF EXISTS public.my_employee_row;

-- Client credentials
CREATE TABLE public.client_portal_credentials (
  client_id uuid PRIMARY KEY REFERENCES public.clients(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL,
  portal_access_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_portal_credentials TO authenticated;
GRANT ALL ON public.client_portal_credentials TO service_role;
ALTER TABLE public.client_portal_credentials ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage client creds" ON public.client_portal_credentials
  FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE TRIGGER trg_cpc_updated BEFORE UPDATE ON public.client_portal_credentials
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Employee credentials
CREATE TABLE public.employee_portal_credentials (
  employee_id uuid PRIMARY KEY REFERENCES public.employees(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL,
  portal_access_code text,
  portal_username text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_portal_credentials TO authenticated;
GRANT ALL ON public.employee_portal_credentials TO service_role;
ALTER TABLE public.employee_portal_credentials ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manage emp creds" ON public.employee_portal_credentials
  FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE TRIGGER trg_epc_updated BEFORE UPDATE ON public.employee_portal_credentials
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Backfill
INSERT INTO public.client_portal_credentials (client_id, owner_id, portal_access_code)
  SELECT id, owner_id, portal_access_code FROM public.clients
  WHERE portal_access_code IS NOT NULL
  ON CONFLICT (client_id) DO NOTHING;

INSERT INTO public.employee_portal_credentials (employee_id, owner_id, portal_access_code, portal_username)
  SELECT id, owner_id, portal_access_code, portal_username FROM public.employees
  WHERE portal_access_code IS NOT NULL OR portal_username IS NOT NULL
  ON CONFLICT (employee_id) DO NOTHING;

-- Drop credential columns from base tables
ALTER TABLE public.clients DROP COLUMN portal_access_code;
ALTER TABLE public.employees DROP COLUMN portal_access_code, DROP COLUMN portal_username;

-- Restore safe self-read on base tables (credentials no longer present)
CREATE POLICY "client reads own row" ON public.clients
  FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
CREATE POLICY "employee reads own row" ON public.employees
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

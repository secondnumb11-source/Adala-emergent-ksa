
-- 1. audit_log: restrict reads to office owner only (not actor)
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log
  FOR SELECT USING (auth.uid() = owner_id);

-- 2. tasks: prevent employees from reassigning tasks (owner_id/case_id/employee_id)
CREATE OR REPLACE FUNCTION public.tasks_employee_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS DISTINCT FROM OLD.owner_id THEN
    IF NEW.owner_id IS DISTINCT FROM OLD.owner_id
       OR NEW.case_id IS DISTINCT FROM OLD.case_id
       OR NEW.employee_id IS DISTINCT FROM OLD.employee_id
       OR NEW.id IS DISTINCT FROM OLD.id
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'employees cannot reassign tasks or change ownership';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.tasks_employee_update_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS tasks_employee_update_guard ON public.tasks;
CREATE TRIGGER tasks_employee_update_guard
BEFORE UPDATE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.tasks_employee_update_guard();

-- 3 & 4. Remove direct client/employee self-reads on base tables (which exposed
-- portal_access_code / portal_username / permissions). Provide safe views instead.
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;

CREATE OR REPLACE VIEW public.my_client_row AS
  SELECT id, owner_id, portal_user_id, full_name, email, phone,
         national_id, address, notes, created_at, updated_at
  FROM public.clients
  WHERE portal_user_id = auth.uid();
GRANT SELECT ON public.my_client_row TO authenticated;

CREATE OR REPLACE VIEW public.my_employee_row AS
  SELECT id, owner_id, user_id, full_name, job_title, email,
         assigned_cases, created_at, updated_at
  FROM public.employees
  WHERE user_id = auth.uid();
GRANT SELECT ON public.my_employee_row TO authenticated;

-- 5. has_role: switch to SECURITY INVOKER so it isn't a definer-bypass surface.
-- Authenticated users need SELECT on their own rows in user_roles for it to work.
CREATE OR REPLACE FUNCTION public.has_role(_user_id uuid, _role app_role)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role = _role
  );
$$;

DROP POLICY IF EXISTS "users read own roles" ON public.user_roles;
CREATE POLICY "users read own roles" ON public.user_roles
  FOR SELECT USING (user_id = auth.uid());

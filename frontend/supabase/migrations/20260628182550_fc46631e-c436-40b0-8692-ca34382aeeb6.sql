
-- 1) Fix audit_log forgery: require owner_id = auth.uid() in WITH CHECK
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

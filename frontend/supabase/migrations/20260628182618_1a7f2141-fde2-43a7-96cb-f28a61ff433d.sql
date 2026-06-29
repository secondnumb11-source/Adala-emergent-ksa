
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

-- Security fix: harden public.employee_can_access_case
--
-- The version installed by migration 20260627063457 allows ANY employee
-- with NULL/empty assigned_cases to read EVERY case in their tenant, and
-- removed the is_active guard so deactivated employees keep access.
--
-- This migration restores the strict semantics from the private.* version:
--   * employee must be is_active = true
--   * employee must belong to the same owner (tenant) as the case
--   * access requires an explicit assignment via assigned_employee_id,
--     assigned_cases, OR assigned_clients

CREATE OR REPLACE FUNCTION public.employee_can_access_case(
  _case_id uuid,
  _user_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id
      AND e.is_active = true
      AND e.owner_id = c.owner_id
      AND (
        c.assigned_employee_id = e.id
        OR c.id = ANY (COALESCE(e.assigned_cases, ARRAY[]::uuid[]))
        OR c.client_id = ANY (COALESCE(e.assigned_clients, ARRAY[]::uuid[]))
      )
  );
$$;

COMMENT ON FUNCTION public.employee_can_access_case(uuid, uuid) IS
  'Returns true only when the active employee has an explicit assignment to the case within the same tenant. Hardened 2026-06-27 to remove permissive NULL/empty fallback.';
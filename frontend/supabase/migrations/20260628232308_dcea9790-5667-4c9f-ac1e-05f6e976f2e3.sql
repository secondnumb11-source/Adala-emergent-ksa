
-- get_employee_portal_code: switch to SECURITY INVOKER (employees RLS already restricts to owner)
CREATE OR REPLACE FUNCTION public.get_employee_portal_code(_employee_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path TO 'public'
AS $function$
  SELECT portal_access_code
  FROM public.employees
  WHERE id = _employee_id
    AND owner_id = auth.uid();
$function$;

-- Ensure the intentional self-service onboarding RPC remains callable by signed-in users.
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated;

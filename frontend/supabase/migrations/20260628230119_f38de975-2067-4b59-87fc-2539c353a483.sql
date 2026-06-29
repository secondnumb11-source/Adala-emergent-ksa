CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN
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
GRANT EXECUTE ON FUNCTION public.has_role(UUID, public.app_role) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id UUID, _user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.cases WHERE id = _case_id AND owner_id = _user_id)
    OR EXISTS (
      SELECT 1 FROM public.cases c
      JOIN public.employees e ON e.id = c.assigned_employee_id
      WHERE c.id = _case_id AND e.user_id = _user_id
    );
$$;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(UUID, UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id UUID, _user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM public.clients WHERE id = _client_id AND (owner_id = _user_id OR portal_user_id = _user_id))
    OR EXISTS (
      SELECT 1 FROM public.employees e
      WHERE e.user_id = _user_id AND (_client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])) OR e.owner_id IN (SELECT owner_id FROM public.clients WHERE id = _client_id))
    );
$$;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(UUID, UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id UUID, _perm public.doc_permission, _user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT public.employee_can_access_case(_case_id, _user_id)
    OR EXISTS (
      SELECT 1 FROM public.document_permissions
      WHERE case_id = _case_id AND user_id = _user_id AND permission = _perm
    );
$$;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(UUID, public.doc_permission, UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT jsonb_build_object('session_reminders', true, 'task_reminders', true);
$$;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_employees_directory()
RETURNS TABLE(id UUID, owner_id UUID, user_id UUID, full_name TEXT, job_title TEXT)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT e.id, e.owner_id, e.user_id, e.full_name, e.job_title
  FROM public.employees e
  WHERE e.owner_id = auth.uid()
     OR e.owner_id IN (SELECT owner_id FROM public.employees WHERE user_id = auth.uid())
     OR e.user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.get_employees_directory() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(TEXT, TEXT) TO service_role;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;
REVOKE EXECUTE ON FUNCTION public.system_check_inspect() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO service_role;
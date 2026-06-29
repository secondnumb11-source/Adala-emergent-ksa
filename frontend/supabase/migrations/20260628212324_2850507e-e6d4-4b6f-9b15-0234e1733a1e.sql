
-- 1) Audit logs: remove user INSERT, restrict reads
DROP POLICY IF EXISTS "actor inserts audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "actor reads audit_logs" ON public.audit_logs;
REVOKE INSERT, UPDATE, DELETE ON public.audit_logs FROM authenticated, anon;
GRANT ALL ON public.audit_logs TO service_role;
CREATE POLICY "service role writes audit_logs"
  ON public.audit_logs FOR ALL TO service_role
  USING (true) WITH CHECK (true);
CREATE POLICY "admins read audit_logs"
  ON public.audit_logs FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- 2) Storage policies for case-documents: verify real ownership
CREATE OR REPLACE FUNCTION public.can_access_case_doc_object(_name text, _user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT _user_id IS NOT NULL AND (
    -- (a) Object lives directly under the caller's own folder (owner uploading)
    (storage.foldername(_name))[1] = _user_id::text
    OR
    -- (b) Active employee whose office owner-id matches the first folder segment
    EXISTS (
      SELECT 1 FROM public.employees e
      WHERE e.user_id = _user_id
        AND e.is_active = true
        AND e.owner_id::text = (storage.foldername(_name))[1]
    )
    OR
    -- (c) A documents row links this file to a case the caller can access
    EXISTS (
      SELECT 1 FROM public.documents d
      LEFT JOIN public.cases c ON c.id = d.case_id
      LEFT JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = _name
        AND (
          d.owner_id = _user_id
          OR cl.portal_user_id = _user_id
          OR (d.case_id IS NOT NULL AND public.employee_can_access_case(d.case_id, _user_id))
        )
    )
  );
$$;
REVOKE ALL ON FUNCTION public.can_access_case_doc_object(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_case_doc_object(text, uuid) TO service_role;

DROP POLICY IF EXISTS case_documents_select_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_insert_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_update_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_delete_own ON storage.objects;

CREATE POLICY case_documents_select_verified ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'case-documents' AND public.can_access_case_doc_object(name, auth.uid()));
CREATE POLICY case_documents_insert_verified ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'case-documents' AND public.can_access_case_doc_object(name, auth.uid()));
CREATE POLICY case_documents_update_verified ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'case-documents' AND public.can_access_case_doc_object(name, auth.uid()))
  WITH CHECK (bucket_id = 'case-documents' AND public.can_access_case_doc_object(name, auth.uid()));
CREATE POLICY case_documents_delete_verified ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'case-documents' AND public.can_access_case_doc_object(name, auth.uid()));

-- 3) Lock down SECURITY DEFINER functions that should not be client-callable
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
GRANT EXECUTE ON FUNCTION public.update_updated_at_column() TO service_role;
GRANT EXECUTE ON FUNCTION public.set_appeal_deadline() TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO service_role;

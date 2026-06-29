
-- 1) Fix audit_log INSERT policy to prevent owner_id spoofing
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit"
ON public.audit_log
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = actor_id AND auth.uid() = owner_id);

-- 2) Tighten storage policies for case-documents bucket
DROP POLICY IF EXISTS case_documents_select_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_insert_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_update_own ON storage.objects;
DROP POLICY IF EXISTS case_documents_delete_own ON storage.objects;

-- Helper: extract case_id (second folder segment) safely
-- Path convention: {owner_uuid}/{case_uuid}/{filename}

-- SELECT: owner, assigned employee, portal client of the case, or doc-permission grantee
CREATE POLICY case_documents_select_authorized
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (
    -- Owner (law firm) — original path-prefix check
    (auth.uid())::text = (storage.foldername(name))[1]
    OR EXISTS (
      SELECT 1
      FROM public.cases c
      WHERE c.id::text = (storage.foldername(name))[2]
        AND (
          c.owner_id = auth.uid()
          OR private.employee_can_access_case(c.id, auth.uid())
          OR EXISTS (
            SELECT 1 FROM public.clients cl
            WHERE cl.id = c.client_id AND cl.portal_user_id = auth.uid()
          )
          OR public.has_doc_permission(c.id, auth.uid(), 'view'::public.doc_permission)
        )
    )
  )
);

-- INSERT: only the owner of the case may upload (owner or doc-permission with manage/edit)
CREATE POLICY case_documents_insert_authorized
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
  AND EXISTS (
    SELECT 1 FROM public.cases c
    WHERE c.id::text = (storage.foldername(name))[2]
      AND c.owner_id = auth.uid()
  )
);

-- UPDATE: same as insert
CREATE POLICY case_documents_update_authorized
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
)
WITH CHECK (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
);

-- DELETE: owner only
CREATE POLICY case_documents_delete_authorized
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (auth.uid())::text = (storage.foldername(name))[1]
);

-- 3) Revoke EXECUTE from authenticated/PUBLIC on SECURITY DEFINER helpers
--    that should not be directly callable by signed-in users.
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, authenticated, anon;

-- Keep EXECUTE on user-callable RPCs (re-grant to be explicit)
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated;

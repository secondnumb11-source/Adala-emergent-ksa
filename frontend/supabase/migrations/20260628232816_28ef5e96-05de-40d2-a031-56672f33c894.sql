
-- Helper: tightened access check for case-documents storage paths.
-- Path conventions:
--   {owner_id}/{case_id}/{file}            -- owner archive uploads
--   {owner_id}/tasks/{task_id}/{file}      -- employee task attachments
--   {owner_id}/chat/{user_id}/{file}       -- internal team chat attachments
CREATE OR REPLACE FUNCTION public.can_access_case_doc_path(_path text, _user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  parts text[];
  v_owner uuid;
  v_second text;
  v_case uuid;
  v_task uuid;
  v_chat_user uuid;
BEGIN
  IF _user_id IS NULL OR _path IS NULL THEN
    RETURN false;
  END IF;

  parts := storage.foldername(_path);
  IF array_length(parts, 1) IS NULL OR array_length(parts, 1) < 1 THEN
    RETURN false;
  END IF;

  BEGIN
    v_owner := parts[1]::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;

  -- Office owner has full access to their own folder.
  IF v_owner = _user_id THEN
    RETURN true;
  END IF;

  v_second := parts[2];
  IF v_second IS NULL THEN
    RETURN false;
  END IF;

  -- Employee of this office: must access a case/task/chat that belongs to office.
  IF EXISTS (SELECT 1 FROM public.employees WHERE user_id = _user_id AND owner_id = v_owner) THEN
    IF v_second = 'chat' THEN
      RETURN true; -- internal team chat within their own office
    END IF;
    IF v_second = 'tasks' THEN
      BEGIN
        v_task := parts[3]::uuid;
      EXCEPTION WHEN others THEN
        RETURN false;
      END;
      RETURN EXISTS (
        SELECT 1 FROM public.tasks t
        WHERE t.id = v_task AND t.owner_id = v_owner
      );
    END IF;
    -- Otherwise treat second segment as case_id and verify employee can access it.
    BEGIN
      v_case := v_second::uuid;
    EXCEPTION WHEN others THEN
      RETURN false;
    END;
    RETURN public.employee_can_access_case(v_case, _user_id);
  END IF;

  -- Portal client: only files for cases of THIS client within THIS office.
  BEGIN
    v_case := v_second::uuid;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;
  RETURN EXISTS (
    SELECT 1
    FROM public.cases c
    JOIN public.clients cl ON cl.id = c.client_id
    WHERE c.id = v_case
      AND c.owner_id = v_owner
      AND cl.portal_user_id = _user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_case_doc_path(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_case_doc_path(text, uuid) TO authenticated, service_role;

-- Replace storage policies for case-documents.
DROP POLICY IF EXISTS case_docs_select_office ON storage.objects;
DROP POLICY IF EXISTS case_docs_insert_office ON storage.objects;
DROP POLICY IF EXISTS case_docs_update_office ON storage.objects;
DROP POLICY IF EXISTS case_docs_delete_office ON storage.objects;

-- SELECT: owner, employees scoped to accessible case/task/chat, clients scoped to their own cases.
CREATE POLICY case_docs_select_scoped ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id = 'case-documents'
  AND public.can_access_case_doc_path(name, auth.uid())
);

-- INSERT/UPDATE/DELETE: restrict to office owner + employees of that office (no client writes).
CREATE POLICY case_docs_insert_scoped ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND (
    auth.uid() = ((storage.foldername(name))[1])::uuid
    OR EXISTS (
      SELECT 1 FROM public.employees e
      WHERE e.user_id = auth.uid()
        AND e.owner_id = ((storage.foldername(name))[1])::uuid
    )
  )
  AND public.can_access_case_doc_path(name, auth.uid())
);

CREATE POLICY case_docs_update_scoped ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (
    auth.uid() = ((storage.foldername(name))[1])::uuid
    OR EXISTS (
      SELECT 1 FROM public.employees e
      WHERE e.user_id = auth.uid()
        AND e.owner_id = ((storage.foldername(name))[1])::uuid
    )
  )
  AND public.can_access_case_doc_path(name, auth.uid())
)
WITH CHECK (
  bucket_id = 'case-documents'
  AND (
    auth.uid() = ((storage.foldername(name))[1])::uuid
    OR EXISTS (
      SELECT 1 FROM public.employees e
      WHERE e.user_id = auth.uid()
        AND e.owner_id = ((storage.foldername(name))[1])::uuid
    )
  )
  AND public.can_access_case_doc_path(name, auth.uid())
);

CREATE POLICY case_docs_delete_scoped ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (
    auth.uid() = ((storage.foldername(name))[1])::uuid
    OR EXISTS (
      SELECT 1 FROM public.employees e
      WHERE e.user_id = auth.uid()
        AND e.owner_id = ((storage.foldername(name))[1])::uuid
    )
  )
  AND public.can_access_case_doc_path(name, auth.uid())
);

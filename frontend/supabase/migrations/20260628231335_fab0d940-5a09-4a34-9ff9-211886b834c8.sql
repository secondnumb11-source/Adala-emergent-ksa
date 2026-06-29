
-- Helper: does the current user belong to the office identified by _owner_uuid?
CREATE OR REPLACE FUNCTION public.is_office_member(_owner_uuid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT auth.uid() = _owner_uuid
      OR EXISTS (SELECT 1 FROM public.employees WHERE user_id = auth.uid() AND owner_id = _owner_uuid)
      OR EXISTS (SELECT 1 FROM public.clients   WHERE portal_user_id = auth.uid() AND owner_id = _owner_uuid);
$$;

GRANT EXECUTE ON FUNCTION public.is_office_member(uuid) TO authenticated;

-- Policies on storage.objects scoped to bucket = 'case-documents'
DROP POLICY IF EXISTS "case_docs_select_office" ON storage.objects;
DROP POLICY IF EXISTS "case_docs_insert_office" ON storage.objects;
DROP POLICY IF EXISTS "case_docs_update_office" ON storage.objects;
DROP POLICY IF EXISTS "case_docs_delete_office" ON storage.objects;

CREATE POLICY "case_docs_select_office"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'case-documents'
  AND public.is_office_member( (storage.foldername(name))[1]::uuid )
);

CREATE POLICY "case_docs_insert_office"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND public.is_office_member( (storage.foldername(name))[1]::uuid )
);

CREATE POLICY "case_docs_update_office"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND public.is_office_member( (storage.foldername(name))[1]::uuid )
)
WITH CHECK (
  bucket_id = 'case-documents'
  AND public.is_office_member( (storage.foldername(name))[1]::uuid )
);

CREATE POLICY "case_docs_delete_office"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND public.is_office_member( (storage.foldername(name))[1]::uuid )
);


DROP POLICY IF EXISTS "case_documents_select_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_update_own" ON storage.objects;
DROP POLICY IF EXISTS "case_documents_delete_own" ON storage.objects;

CREATE POLICY "case_documents_select_own"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "case_documents_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "case_documents_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
)
WITH CHECK (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "case_documents_delete_own"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

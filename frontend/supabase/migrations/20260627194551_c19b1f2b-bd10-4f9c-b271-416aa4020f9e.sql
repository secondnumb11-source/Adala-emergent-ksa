
-- RLS policies for case-documents bucket
CREATE POLICY "case_documents_select" ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'case-documents' AND (
    auth.uid()::text = (storage.foldername(name))[1]
    OR EXISTS (
      SELECT 1 FROM public.cases c
      WHERE c.id::text = (storage.foldername(name))[2]
        AND (
          c.owner_id = auth.uid()
          OR public.employee_can_access_case(c.id, auth.uid())
          OR EXISTS (SELECT 1 FROM public.clients cl WHERE cl.id = c.client_id AND cl.portal_user_id = auth.uid())
        )
    )
  )
);

CREATE POLICY "case_documents_insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'case-documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "case_documents_update" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1])
WITH CHECK (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "case_documents_delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'case-documents' AND auth.uid()::text = (storage.foldername(name))[1]);


-- Storage policies for case-documents bucket
CREATE POLICY "owner manages own docs" ON storage.objects
  FOR ALL TO authenticated
  USING (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text)
  WITH CHECK (bucket_id = 'case-documents' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "client reads own case docs" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'case-documents'
    AND EXISTS (
      SELECT 1 FROM public.documents d
      JOIN public.cases c ON c.id = d.case_id
      JOIN public.clients cl ON cl.id = c.client_id
      WHERE d.storage_path = storage.objects.name
        AND cl.portal_user_id = auth.uid()
    )
  );

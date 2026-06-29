-- ============================================================================
-- إصلاح خطأ: permission denied for function has_doc_permission
-- ============================================================================
-- المشكلة:
--   سياسة SELECT على bucket "case-documents" تستدعي
--   public.has_doc_permission(...) بينما الترحيل
--   20260626223127 سحب صلاحية EXECUTE من authenticated على هذه الدالة.
--   نتيجة: كل قراءة من storage.objects تفشل برسالة الخطأ في الصورة.
--
-- الحل:
--   استبدال الاستدعاء بنسخة private.has_doc_permission المماثلة
--   (نفس المنطق، تبقى EXECUTE مفتوحة لـ authenticated).
--
-- التشغيل:
--   شغّل هذا الملف من Supabase Dashboard → SQL Editor → New query → Run.
-- ============================================================================

DROP POLICY IF EXISTS case_documents_select_authorized ON storage.objects;

CREATE POLICY case_documents_select_authorized
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'case-documents'
  AND (
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
          OR private.has_doc_permission(c.id, auth.uid(), 'view'::public.doc_permission)
        )
    )
  )
);

-- ضمان دفاعي: تأكيد أن دوال private قابلة للتنفيذ من المستخدم المسجّل.
GRANT EXECUTE ON FUNCTION private.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
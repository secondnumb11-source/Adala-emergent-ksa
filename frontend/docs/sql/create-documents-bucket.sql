-- =================================================================
-- إصلاح خطأ "Bucket not found" في قسم أرشيف المستندات والأحكام
-- =================================================================
-- شغّل هذا الملف يدوياً في:
--   Supabase Dashboard → SQL Editor
--   (المشروع: itygxzseljaokfqmpsmn)
--
-- يقوم بـ:
--   1) إنشاء storage bucket باسم "documents" (خاص — غير عام)
--   2) إضافة سياسات RLS على storage.objects بحيث:
--      - كل مستخدم يرفع/يقرأ/يعدّل/يحذف ملفاته فقط
--      - مسار الملف داخل الـ bucket: <auth.uid()>/<case_id>/<file>
-- =================================================================

-- 1) إنشاء الـ bucket إن لم يكن موجوداً
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  52428800, -- 50 MB
  ARRAY[
    'application/pdf',
    'image/png',
    'image/jpeg',
    'image/webp',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain'
  ]
)
ON CONFLICT (id) DO UPDATE
SET file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2) تفعيل RLS (افتراضياً مفعّل)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 3) إزالة سياسات قديمة بنفس الاسم لتجنب التعارض
DROP POLICY IF EXISTS "documents_select_own" ON storage.objects;
DROP POLICY IF EXISTS "documents_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "documents_update_own" ON storage.objects;
DROP POLICY IF EXISTS "documents_delete_own" ON storage.objects;

-- 4) قراءة ملفاتي
CREATE POLICY "documents_select_own"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- 5) رفع داخل مجلدي
CREATE POLICY "documents_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- 6) تعديل ملفاتي
CREATE POLICY "documents_update_own"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
)
WITH CHECK (
  bucket_id = 'documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- 7) حذف ملفاتي
CREATE POLICY "documents_delete_own"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'documents'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- =================================================================
-- بعد التشغيل: ارفع مستنداً من قسم الأرشيف — لن تظهر "Bucket not found".
-- لعرض/تنزيل مستند، استخدم في الواجهة:
--   const { data } = await supabase.storage
--     .from('documents')
--     .createSignedUrl(filePath, 3600);
-- =================================================================

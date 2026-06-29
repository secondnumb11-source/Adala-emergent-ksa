-- Fix: Grant EXECUTE permission on storage helper functions to authenticated users
-- This fixes "permission denied for function can_access_case_doc_object" error
-- when uploading documents in Archive and Employee Portal

-- Grant EXECUTE on can_access_case_doc_object to authenticated and anon roles
GRANT EXECUTE ON FUNCTION public.can_access_case_doc_object(text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_case_doc_object(text, uuid) TO anon;

-- Verify the grants
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.routine_privileges 
    WHERE routine_name = 'can_access_case_doc_object' 
    AND routine_schema = 'public'
    AND grantee = 'authenticated'
    AND privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Failed to grant EXECUTE on can_access_case_doc_object to authenticated';
  END IF;
END $$;

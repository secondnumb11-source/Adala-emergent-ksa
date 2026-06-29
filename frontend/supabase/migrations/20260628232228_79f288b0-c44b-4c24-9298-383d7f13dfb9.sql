
-- 1) read_at on portal_messages
ALTER TABLE public.portal_messages ADD COLUMN IF NOT EXISTS read_at timestamptz;
UPDATE public.portal_messages SET read_at = COALESCE(read_at, created_at)
WHERE is_read = true AND read_at IS NULL;

-- 2) Tighten client_inquiries INSERT to enforce owner_id matches client's office
DROP POLICY IF EXISTS "client manage own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client_insert_own_inquiries" ON public.client_inquiries;
CREATE POLICY "client_insert_own_inquiries" ON public.client_inquiries
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.clients c
      WHERE c.id = client_inquiries.client_id
        AND c.portal_user_id = auth.uid()
        AND c.owner_id = client_inquiries.owner_id
    )
  );
CREATE POLICY "client_read_own_inquiries" ON public.client_inquiries
  FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.clients c
      WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid())
  );

-- 3) Lock down maintenance SECURITY DEFINER fns (system / service_role only)
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.system_check_inspect() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT  EXECUTE ON FUNCTION public.enqueue_task_reminders()    TO service_role;
GRANT  EXECUTE ON FUNCTION public.system_check_inspect()      TO service_role;

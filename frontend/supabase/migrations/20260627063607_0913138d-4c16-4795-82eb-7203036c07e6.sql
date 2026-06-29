DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
DROP POLICY IF EXISTS "select tenant or thread" ON public.employee_messages;
CREATE POLICY "select tenant or thread" ON public.employee_messages
  FOR SELECT TO authenticated
  USING (auth.uid() = owner_id OR auth.uid() = sender_id OR auth.uid() = recipient_id);
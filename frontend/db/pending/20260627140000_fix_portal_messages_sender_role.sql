-- Fix: portal_msg_role_spoof
-- Prevent clients from inserting portal_messages with sender_role='lawyer' or 'employee'.
-- Tighten the WITH CHECK on the client-side RLS policy so sender_role must equal 'client'.

DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;

CREATE POLICY "client manage own portal msgs" ON public.portal_messages
  FOR ALL
  TO authenticated
  USING (
    client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
  )
  WITH CHECK (
    client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
    AND sender_id = auth.uid()
    AND sender_role = 'client'
  );

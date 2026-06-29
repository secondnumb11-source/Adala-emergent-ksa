-- Run this in Supabase SQL Editor on project qncibmkaqmaxkpzzzhsb.
-- Fixes: portal_msg_role_spoof — client could insert portal_messages with
-- sender_role = 'lawyer' or 'employee', impersonating the legal team.
-- This migration tightens WITH CHECK to require sender_role = 'client'.

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

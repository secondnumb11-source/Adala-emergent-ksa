-- Recreate with proper schema (no data yet)
DROP TABLE IF EXISTS public.employee_messages CASCADE;
CREATE TABLE public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX idx_emp_msg_pair  ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages
  FOR SELECT TO authenticated USING (auth.uid() = owner_id);
CREATE POLICY "peers read own thread" ON public.employee_messages
  FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
CREATE POLICY "sender inserts own message" ON public.employee_messages
  FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = sender_id
    AND (
      auth.uid() = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id)
    )
    AND (
      recipient_id = owner_id
      OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = recipient_id AND e.owner_id = employee_messages.owner_id)
    )
  );
CREATE POLICY "recipient marks read" ON public.employee_messages
  FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
CREATE POLICY "sender deletes own" ON public.employee_messages
  FOR DELETE TO authenticated USING (auth.uid() = sender_id);
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;

DROP TABLE IF EXISTS public.client_inquiries CASCADE;
CREATE TABLE public.client_inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id UUID NOT NULL,
  author_role TEXT NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject TEXT,
  body TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_client_inquiries_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX idx_client_inquiries_parent ON public.client_inquiries(parent_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner reads inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "owner writes inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
CREATE POLICY "owner updates inquiries" ON public.client_inquiries FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries FOR DELETE TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "client reads own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid())
);
CREATE POLICY "client writes own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid() AND author_role = 'client'
  AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id)
);

-- Lock down SECURITY DEFINER functions (linter warnings 1-4)
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, app_role) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.has_role(uuid, app_role) TO service_role;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
-- has_role: fix argument order to (_role, _user_id)
DROP FUNCTION IF EXISTS public.has_role(uuid, public.app_role);
DROP FUNCTION IF EXISTS public.has_role(public.app_role, uuid);
CREATE OR REPLACE FUNCTION public.has_role(_role public.app_role, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;
REVOKE EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(public.app_role, uuid) TO authenticated, service_role;

-- doc_permission enum
DO $$ BEGIN CREATE TYPE public.doc_permission AS ENUM ('view','upload','delete','manage'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- employee access helpers
CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id UUID, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cases c
    JOIN public.employees e ON e.owner_id = c.owner_id
    WHERE c.id = _case_id AND e.user_id = _user_id
      AND (e.assigned_cases IS NULL OR e.assigned_cases = '{}' OR c.id = ANY(e.assigned_cases))
  );
$$;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id UUID, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.clients cl
    JOIN public.employees e ON e.owner_id = cl.owner_id
    WHERE cl.id = _client_id AND e.user_id = _user_id
      AND (e.assigned_clients IS NULL OR e.assigned_clients = '{}' OR cl.id = ANY(e.assigned_clients))
  );
$$;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.session_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  lead_hours INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_at TIMESTAMPTZ, error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.session_reminders TO authenticated;
GRANT ALL ON public.session_reminders TO service_role;
ALTER TABLE public.session_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage session_reminders" ON public.session_reminders;
CREATE POLICY "owner manage session_reminders" ON public.session_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.task_reminders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id UUID NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id UUID REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  sent_at TIMESTAMPTZ, error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;
ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage task_reminders" ON public.task_reminders;
CREATE POLICY "owner manage task_reminders" ON public.task_reminders FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.document_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE CASCADE,
  permission public.doc_permission NOT NULL DEFAULT 'view',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_permissions TO authenticated;
GRANT ALL ON public.document_permissions TO service_role;
ALTER TABLE public.document_permissions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage doc_perm" ON public.document_permissions;
CREATE POLICY "owner manage doc_perm" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP POLICY IF EXISTS "user reads own doc_perm" ON public.document_permissions;
CREATE POLICY "user reads own doc_perm" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.has_doc_permission(_case_id UUID, _perm public.doc_permission, _user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.document_permissions dp
    WHERE dp.user_id = _user_id
      AND (dp.case_id IS NULL OR dp.case_id = _case_id)
      AND (dp.permission = _perm OR dp.permission = 'manage')
  );
$$;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, public.doc_permission, uuid) TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  office_id UUID,
  title TEXT NOT NULL, message TEXT, category TEXT, link TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notifications TO authenticated;
GRANT ALL ON public.notifications TO service_role;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own notifications" ON public.notifications;
CREATE POLICY "users manage own notifications" ON public.notifications FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  channels JSONB NOT NULL DEFAULT '{}'::jsonb,
  quiet_hours JSONB NOT NULL DEFAULT '{}'::jsonb,
  sessions JSONB NOT NULL DEFAULT '{}'::jsonb,
  tasks JSONB NOT NULL DEFAULT '{}'::jsonb,
  appeals JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notif_prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif_prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  entity_type TEXT NOT NULL, entity_id UUID,
  action TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT, user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_log_owner ON public.audit_log(owner_id, created_at DESC);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id OR auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  office_id UUID, actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  entity TEXT, entity_id UUID, action TEXT NOT NULL,
  details JSONB, ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT ON public.audit_logs TO authenticated;
GRANT ALL ON public.audit_logs TO service_role;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "actor reads audit_logs" ON public.audit_logs;
CREATE POLICY "actor reads audit_logs" ON public.audit_logs FOR SELECT TO authenticated USING (auth.uid() = actor_id);
DROP POLICY IF EXISTS "actor inserts audit_logs" ON public.audit_logs;
CREATE POLICY "actor inserts audit_logs" ON public.audit_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

CREATE TABLE IF NOT EXISTS public.saved_filters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, name TEXT NOT NULL,
  filters JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.saved_filters TO authenticated;
GRANT ALL ON public.saved_filters TO service_role;
ALTER TABLE public.saved_filters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE TABLE IF NOT EXISTS public.secure_secrets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  scope TEXT NOT NULL, key TEXT NOT NULL,
  ciphertext TEXT NOT NULL, iv TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (owner_id, scope, key)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.secure_secrets TO authenticated;
GRANT ALL ON public.secure_secrets TO service_role;
ALTER TABLE public.secure_secrets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage secrets" ON public.secure_secrets;
CREATE POLICY "owner manage secrets" ON public.secure_secrets FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

-- employee_messages (internal staff chat)
CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_emp_msg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_emp_msg_pair ON public.employee_messages(sender_id, recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_emp_msg_recipient ON public.employee_messages(recipient_id, is_read);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads tenant chat" ON public.employee_messages;
CREATE POLICY "owner reads tenant chat" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "peers read own thread" ON public.employee_messages;
CREATE POLICY "peers read own thread" ON public.employee_messages FOR SELECT TO authenticated
  USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages FOR INSERT TO authenticated
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
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages FOR UPDATE TO authenticated
  USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

-- client_inquiries thread
CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  client_id uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id uuid REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id uuid REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id uuid NOT NULL,
  author_role text NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject text, body text NOT NULL,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_parent ON public.client_inquiries(parent_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads inquiries" ON public.client_inquiries;
CREATE POLICY "owner reads inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner writes inquiries" ON public.client_inquiries;
CREATE POLICY "owner writes inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
CREATE POLICY "owner updates inquiries" ON public.client_inquiries FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries FOR DELETE TO authenticated USING (owner_id = auth.uid());
DROP POLICY IF EXISTS "client reads own inquiries" ON public.client_inquiries;
CREATE POLICY "client reads own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid())
);
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
CREATE POLICY "client writes own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid() AND author_role = 'client'
  AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id)
);

-- employees portal credentials
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS portal_username TEXT;

-- link_current_user_to_portal
CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_access_code TEXT DEFAULT NULL, _account_type TEXT DEFAULT 'client')
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid UUID := auth.uid(); _rows INTEGER := 0;
BEGIN
  IF _uid IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'unauthenticated'); END IF;
  IF _access_code IS NULL OR length(btrim(_access_code)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'missing_code');
  END IF;
  IF _account_type = 'employee' THEN
    UPDATE public.employees SET user_id = _uid
      WHERE portal_access_code = _access_code AND user_id IS NULL;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  ELSE
    UPDATE public.clients SET portal_user_id = _uid
      WHERE portal_access_code = _access_code AND portal_user_id IS NULL;
    GET DIAGNOSTICS _rows = ROW_COUNT;
  END IF;
  RETURN jsonb_build_object('ok', _rows > 0, 'linked', _rows);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;

-- stub queue functions
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders() RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0; $$;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders() RETURNS INTEGER LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0; $$;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status() RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT '[]'::jsonb; $$;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

-- Realtime
ALTER TABLE public.notifications REPLICA IDENTITY FULL;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.client_inquiries REPLICA IDENTITY FULL;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.client_inquiries; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
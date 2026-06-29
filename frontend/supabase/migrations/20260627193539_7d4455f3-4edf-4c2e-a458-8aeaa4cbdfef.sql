-- ============================================================
-- employee_messages (internal staff chat)
-- ============================================================
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
CREATE POLICY "peers read own thread" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() = sender_id OR auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender inserts own message" ON public.employee_messages;
CREATE POLICY "sender inserts own message" ON public.employee_messages FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = sender_id
  AND (auth.uid() = owner_id OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = auth.uid() AND e.owner_id = employee_messages.owner_id))
  AND (recipient_id = owner_id OR EXISTS (SELECT 1 FROM public.employees e WHERE e.user_id = recipient_id AND e.owner_id = employee_messages.owner_id))
);
DROP POLICY IF EXISTS "recipient marks read" ON public.employee_messages;
CREATE POLICY "recipient marks read" ON public.employee_messages FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);
DROP POLICY IF EXISTS "sender deletes own" ON public.employee_messages;
CREATE POLICY "sender deletes own" ON public.employee_messages FOR DELETE TO authenticated USING (auth.uid() = sender_id);

DO $mig$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.employee_messages; EXCEPTION WHEN duplicate_object THEN NULL; WHEN others THEN NULL; END $mig$;
ALTER TABLE public.employee_messages REPLICA IDENTITY FULL;

-- ============================================================
-- Reminder enqueue functions
-- ============================================================
CREATE OR REPLACE FUNCTION public.enqueue_session_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE total INT := 0; lead_h INT; ins INT;
BEGIN
  FOREACH lead_h IN ARRAY ARRAY[7, 24, 48] LOOP
    WITH due AS (
      SELECT s.id AS session_id, s.owner_id, lead_h AS lh
      FROM public.sessions s
      WHERE s.status = 'scheduled'
        AND s.session_date BETWEEN now() + (lead_h || ' hours')::interval - interval '30 minutes'
                              AND  now() + (lead_h || ' hours')::interval + interval '30 minutes'
    )
    INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
    SELECT owner_id, session_id, lh FROM due
    ON CONFLICT (session_id, lead_hours) DO NOTHING;
    GET DIAGNOSTICS ins = ROW_COUNT;
    total := total + ins;
  END LOOP;
  RETURN total;
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT := 0;
BEGIN
  -- Placeholder: no separate task_reminders table; we surface upcoming tasks via notifications elsewhere.
  -- Returns 0 to satisfy the cron endpoint contract.
  RETURN n;
END $$;

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT  EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;

-- ============================================================
-- Private schema (security-definer helpers hidden from API)
-- ============================================================
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO service_role;

CREATE OR REPLACE FUNCTION private.has_role(_user_id uuid, _role public.app_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = _user_id AND role = _role);
$$;

CREATE OR REPLACE FUNCTION private.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.cases c ON c.id = _case_id
    WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = c.owner_id
      AND (c.assigned_employee_id = e.id
           OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[]))
           OR c.client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[])))
  );
$$;

CREATE OR REPLACE FUNCTION private.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.employees e
    JOIN public.clients cl ON cl.id = _client_id
    WHERE e.user_id = _user_id AND e.is_active = true AND e.owner_id = cl.owner_id
      AND (_client_id = ANY(COALESCE(e.assigned_clients, ARRAY[]::uuid[]))
           OR EXISTS (SELECT 1 FROM public.cases c WHERE c.client_id = _client_id
                       AND (c.assigned_employee_id = e.id OR c.id = ANY(COALESCE(e.assigned_cases, ARRAY[]::uuid[])))))
  );
$$;

REVOKE EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION private.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.has_role(uuid, public.app_role) TO service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_case(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION private.employee_can_access_client(uuid, uuid) TO service_role;

-- Public wrappers (security invoker) used by RLS policies
CREATE OR REPLACE FUNCTION public.employee_can_access_case(_case_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, private AS $$
  SELECT private.employee_can_access_case(_case_id, _user_id);
$$;

CREATE OR REPLACE FUNCTION public.employee_can_access_client(_client_id uuid, _user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path = public, private AS $$
  SELECT private.employee_can_access_client(_client_id, _user_id);
$$;

-- Tighten SECURITY DEFINER grants for linter
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO service_role;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.employee_can_access_case(uuid, uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.employee_can_access_client(uuid, uuid) TO authenticated, service_role;

-- Employee read policies via public wrappers
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (public.employee_can_access_case(id, auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (public.employee_can_access_client(id, auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (public.employee_can_access_case(case_id, auth.uid()));
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND public.employee_can_access_case(case_id, auth.uid()));
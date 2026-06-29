
-- 1. audit_log: revoke direct INSERT from clients
DROP POLICY IF EXISTS "users insert own audit log" ON public.audit_log;
REVOKE INSERT ON public.audit_log FROM authenticated, anon;
-- service_role retains ALL via existing grant

-- 2. portal_messages: validate owner_id matches the client's true owner on client insert
DROP POLICY IF EXISTS "client manage own portal messages" ON public.portal_messages;

CREATE POLICY "client select own portal messages"
ON public.portal_messages FOR SELECT TO authenticated
USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

CREATE POLICY "client insert own portal messages"
ON public.portal_messages FOR INSERT TO authenticated
WITH CHECK (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
  AND owner_id = (SELECT owner_id FROM public.clients WHERE id = portal_messages.client_id)
);

CREATE POLICY "client update own portal messages"
ON public.portal_messages FOR UPDATE TO authenticated
USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))
WITH CHECK (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
  AND owner_id = (SELECT owner_id FROM public.clients WHERE id = portal_messages.client_id)
);

CREATE POLICY "client delete own portal messages"
ON public.portal_messages FOR DELETE TO authenticated
USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

-- 3. employee_messages: INSERT must have sender_id = auth.uid()
DROP POLICY IF EXISTS "employees manage own messages" ON public.employee_messages;

CREATE POLICY "employee select own messages"
ON public.employee_messages FOR SELECT TO authenticated
USING (auth.uid() = sender_id OR auth.uid() = recipient_id OR auth.uid() = owner_id);

CREATE POLICY "employee insert own messages"
ON public.employee_messages FOR INSERT TO authenticated
WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "employee update own messages"
ON public.employee_messages FOR UPDATE TO authenticated
USING (auth.uid() = sender_id OR auth.uid() = recipient_id OR auth.uid() = owner_id)
WITH CHECK (auth.uid() = sender_id OR auth.uid() = owner_id);

CREATE POLICY "employee delete own messages"
ON public.employee_messages FOR DELETE TO authenticated
USING (auth.uid() = sender_id OR auth.uid() = owner_id);

-- 4. employees: hide portal_access_code from regular authenticated SELECT
REVOKE SELECT (portal_access_code) ON public.employees FROM authenticated, anon;

-- Owner-only function to retrieve a portal access code when needed
CREATE OR REPLACE FUNCTION public.get_employee_portal_code(_employee_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT portal_access_code
  FROM public.employees
  WHERE id = _employee_id
    AND owner_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_employee_portal_code(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_portal_code(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.link_current_user_to_portal(_account_type text DEFAULT NULL, _access_code text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  user_email text;
  acct text := lower(coalesce(_account_type, ''));
  code text := nullif(trim(coalesce(_access_code, '')), '');
  linked_id uuid;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT email INTO user_email FROM auth.users WHERE id = uid;
  IF acct NOT IN ('client', 'employee') THEN
    SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1;
    IF linked_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
      DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
      RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
    END IF;
    SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1;
    IF linked_id IS NOT NULL THEN
      INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
      DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
      RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked_id);
    END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'lawyer') ON CONFLICT DO NOTHING;
    RETURN jsonb_build_object('linked', true, 'role', 'lawyer');
  END IF;
  IF acct = 'client' THEN
    UPDATE public.clients c SET portal_user_id = uid
    WHERE c.id = (
      SELECT id FROM public.clients
      WHERE (portal_user_id IS NULL OR portal_user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC LIMIT 1
    ) RETURNING c.id INTO linked_id;
    IF linked_id IS NULL THEN SELECT id INTO linked_id FROM public.clients WHERE portal_user_id = uid LIMIT 1; END IF;
    IF linked_id IS NULL THEN RETURN jsonb_build_object('linked', false, 'role', 'client', 'reason', 'client_not_found'); END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'client') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'client', 'id', linked_id);
  END IF;
  IF acct = 'employee' THEN
    UPDATE public.employees e SET user_id = uid
    WHERE e.id = (
      SELECT id FROM public.employees
      WHERE (user_id IS NULL OR user_id = uid)
        AND lower(coalesce(email, '')) = lower(coalesce(user_email, ''))
        AND (code IS NULL OR portal_access_code IS NULL OR portal_access_code = code)
      ORDER BY created_at DESC LIMIT 1
    ) RETURNING e.id INTO linked_id;
    IF linked_id IS NULL THEN SELECT id INTO linked_id FROM public.employees WHERE user_id = uid LIMIT 1; END IF;
    IF linked_id IS NULL THEN RETURN jsonb_build_object('linked', false, 'role', 'employee', 'reason', 'employee_not_found'); END IF;
    INSERT INTO public.user_roles (user_id, role) VALUES (uid, 'employee') ON CONFLICT DO NOTHING;
    DELETE FROM public.user_roles WHERE user_id = uid AND role = 'lawyer';
    RETURN jsonb_build_object('linked', true, 'role', 'employee', 'id', linked_id);
  END IF;
  RETURN jsonb_build_object('linked', false);
END;
$$;

DROP POLICY IF EXISTS "owner manage clients" ON public.clients;
DROP POLICY IF EXISTS "client reads own row" ON public.clients;
DROP POLICY IF EXISTS "employee reads assigned clients" ON public.clients;
CREATE POLICY "owner manage clients" ON public.clients FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own row" ON public.clients FOR SELECT TO authenticated USING (auth.uid() = portal_user_id);
CREATE POLICY "employee reads assigned clients" ON public.clients FOR SELECT TO authenticated USING (private.employee_can_access_client(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage cases" ON public.cases;
DROP POLICY IF EXISTS "client reads own cases" ON public.cases;
DROP POLICY IF EXISTS "employee reads assigned cases" ON public.cases;
CREATE POLICY "owner manage cases" ON public.cases FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own cases" ON public.cases FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
CREATE POLICY "employee reads assigned cases" ON public.cases FOR SELECT TO authenticated USING (private.employee_can_access_case(id, auth.uid()));

DROP POLICY IF EXISTS "owner manage sessions" ON public.sessions;
DROP POLICY IF EXISTS "client reads sessions" ON public.sessions;
DROP POLICY IF EXISTS "employee reads assigned sessions" ON public.sessions;
CREATE POLICY "owner manage sessions" ON public.sessions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads sessions" ON public.sessions FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
CREATE POLICY "employee reads assigned sessions" ON public.sessions FOR SELECT TO authenticated USING (private.employee_can_access_case(case_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage documents" ON public.documents;
DROP POLICY IF EXISTS "client reads case documents" ON public.documents;
DROP POLICY IF EXISTS "employee reads assigned documents" ON public.documents;
CREATE POLICY "owner manage documents" ON public.documents FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads case documents" ON public.documents FOR SELECT TO authenticated USING (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())));
CREATE POLICY "employee reads assigned documents" ON public.documents FOR SELECT TO authenticated USING (case_id IS NOT NULL AND (private.employee_can_access_case(case_id, auth.uid()) OR private.has_doc_permission(case_id, auth.uid(), 'view')));

DROP POLICY IF EXISTS "owner manage powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "client reads own powers" ON public.powers_of_attorney;
DROP POLICY IF EXISTS "employee reads assigned powers" ON public.powers_of_attorney;
CREATE POLICY "owner manage powers" ON public.powers_of_attorney FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));
CREATE POLICY "employee reads assigned powers" ON public.powers_of_attorney FOR SELECT TO authenticated USING (client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid()));

DROP POLICY IF EXISTS "owner manage executions" ON public.executions;
DROP POLICY IF EXISTS "client reads own executions" ON public.executions;
DROP POLICY IF EXISTS "employee reads assigned executions" ON public.executions;
CREATE POLICY "owner manage executions" ON public.executions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) OR (case_id IN (SELECT id FROM public.cases WHERE client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()))));
CREATE POLICY "employee reads assigned executions" ON public.executions FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner manage employees" ON public.employees;
DROP POLICY IF EXISTS "employee reads own row" ON public.employees;
CREATE POLICY "owner manage employees" ON public.employees FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "employee reads own row" ON public.employees FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner manage tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "owner manage tasks" ON public.tasks FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "employee read assigned tasks" ON public.tasks FOR SELECT TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));
CREATE POLICY "employee updates assigned tasks" ON public.tasks FOR UPDATE TO authenticated USING (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())) WITH CHECK (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage notifs" ON public.client_notifications;
DROP POLICY IF EXISTS "client reads own notifs" ON public.client_notifications;
CREATE POLICY "owner manage notifs" ON public.client_notifications FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client reads own notifs" ON public.client_notifications FOR SELECT TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()));

DROP POLICY IF EXISTS "owner manage portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "client manage own portal msgs" ON public.portal_messages;
DROP POLICY IF EXISTS "employee reads assigned portal msgs" ON public.portal_messages;
CREATE POLICY "owner manage portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client manage own portal msgs" ON public.portal_messages FOR ALL TO authenticated USING (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())) WITH CHECK (client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid()) AND sender_id = auth.uid());
CREATE POLICY "employee reads assigned portal msgs" ON public.portal_messages FOR SELECT TO authenticated USING ((client_id IS NOT NULL AND private.employee_can_access_client(client_id, auth.uid())) OR (case_id IS NOT NULL AND private.employee_can_access_case(case_id, auth.uid())));

DROP POLICY IF EXISTS "owner reads own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner inserts own logs" ON public.najiz_sync_logs;
DROP POLICY IF EXISTS "owner updates own logs" ON public.najiz_sync_logs;
CREATE POLICY "owner reads own logs" ON public.najiz_sync_logs FOR SELECT TO authenticated USING (auth.uid() = owner_id);
CREATE POLICY "owner inserts own logs" ON public.najiz_sync_logs FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "owner updates own logs" ON public.najiz_sync_logs FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage own tokens" ON public.sync_tokens;
CREATE POLICY "owner manage own tokens" ON public.sync_tokens FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "users manage own preferences" ON public.user_preferences;
CREATE POLICY "users manage own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
CREATE POLICY "actor inserts audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

DROP POLICY IF EXISTS "owner manage saved_filters" ON public.saved_filters;
CREATE POLICY "owner manage saved_filters" ON public.saved_filters FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner manage doc perms" ON public.document_permissions;
DROP POLICY IF EXISTS "grantee reads doc perms" ON public.document_permissions;
CREATE POLICY "owner manage doc perms" ON public.document_permissions FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "grantee reads doc perms" ON public.document_permissions FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "service_role only" ON public.secure_secrets;
CREATE POLICY "service_role only" ON public.secure_secrets FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "owner reads reminders" ON public.session_reminders;
CREATE POLICY "owner reads reminders" ON public.session_reminders FOR SELECT TO authenticated USING (auth.uid() = owner_id);

DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.cases; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.sessions; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
DO $$ BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.documents; EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.cases REPLICA IDENTITY FULL;
ALTER TABLE public.sessions REPLICA IDENTITY FULL;
ALTER TABLE public.tasks REPLICA IDENTITY FULL;
ALTER TABLE public.documents REPLICA IDENTITY FULL;

REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO authenticated, service_role;
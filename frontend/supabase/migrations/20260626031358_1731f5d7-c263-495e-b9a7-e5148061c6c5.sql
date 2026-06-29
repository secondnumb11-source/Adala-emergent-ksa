CREATE OR REPLACE FUNCTION public.enqueue_session_reminders() RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE((np.sessions->'lead_hours')::jsonb, '[24,48]'::jsonb) AS lead_hours
    FROM public.notification_preferences np
  ), expanded AS (
    SELECT s.id AS session_id, s.owner_id, s.session_date, (lh::text)::int AS lead_hours
    FROM public.sessions s
    LEFT JOIN prefs p ON p.owner_id = s.owner_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.lead_hours, '[24,48]'::jsonb)) AS lh
    WHERE s.status = 'scheduled' AND s.session_date > now()
  ), to_insert AS (
    SELECT e.owner_id, e.session_id, e.lead_hours
    FROM expanded e
    WHERE e.session_date - (e.lead_hours || ' hours')::interval <= now() + interval '15 minutes'
      AND e.session_date - (e.lead_hours || ' hours')::interval > now() - interval '1 hour'
  )
  INSERT INTO public.session_reminders (owner_id, session_id, lead_hours)
  SELECT owner_id, session_id, lead_hours FROM to_insert
  ON CONFLICT (session_id, lead_hours) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
REVOKE EXECUTE ON FUNCTION public.update_updated_at_column() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.set_appeal_deadline() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;
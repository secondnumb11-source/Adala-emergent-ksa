-- Schedule readiness check + session reminders via pg_cron + pg_net.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Idempotent: drop existing jobs by name if present, then re-create.
DO $$
DECLARE
  v_url_root text := 'https://project--ahfqftobmcssbdurutay.lovable.app';
  v_anon text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFoZnFmdG9ibWNzc2JkdXJ1dGF5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI1MjExODMsImV4cCI6MjA5ODA5NzE4M30._OBZBrkzEWvyxBG-Fbv3d1opSZs0jS18gFQKkzhi1iU';
BEGIN
  -- unschedule by name (no error if absent)
  PERFORM cron.unschedule(j.jobid)
  FROM cron.job j
  WHERE j.jobname IN ('lex_readiness_check', 'lex_session_reminders');

  -- Readiness check every 15 minutes
  PERFORM cron.schedule(
    'lex_readiness_check',
    '*/15 * * * *',
    format($job$
      SELECT net.http_get(
        url := %L,
        headers := jsonb_build_object('apikey', %L, 'Content-Type', 'application/json')
      );
    $job$, v_url_root || '/api/public/system-check', v_anon)
  );

  -- Session reminders every 10 minutes
  PERFORM cron.schedule(
    'lex_session_reminders',
    '*/10 * * * *',
    format($job$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object('apikey', %L, 'Content-Type', 'application/json'),
        body := '{}'::jsonb
      );
    $job$, v_url_root || '/api/public/cron/session-reminders', v_anon)
  );
END$$;

-- Refresh the cron status helper so the UI can read job state.
CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public, cron
AS $$
  SELECT COALESCE(
    jsonb_agg(jsonb_build_object(
      'jobname',  j.jobname,
      'schedule', j.schedule,
      'active',   j.active
    )),
    '[]'::jsonb
  )
  FROM cron.job j
  WHERE j.jobname LIKE 'lex_%';
$$;

GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
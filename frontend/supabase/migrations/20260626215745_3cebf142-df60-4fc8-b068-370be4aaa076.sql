CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS TABLE (
  jobid bigint, jobname text, schedule text, active boolean,
  last_start timestamptz, last_status text, last_message text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, cron, extensions
AS $$
  SELECT j.jobid, j.jobname, j.schedule, j.active,
    r.start_time AS last_start, r.status AS last_status, r.return_message AS last_message
  FROM cron.job j
  LEFT JOIN LATERAL (
    SELECT start_time, status, return_message
    FROM cron.job_run_details d
    WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1
  ) r ON true
  WHERE EXISTS (SELECT 1 FROM public.user_roles ur WHERE ur.user_id = auth.uid() AND ur.role = 'admin');
$$;
REVOKE ALL ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated;

DO $$ BEGIN
  PERFORM cron.unschedule('enqueue-session-reminders');
EXCEPTION WHEN OTHERS THEN NULL; END $$;

SELECT cron.schedule(
  'enqueue-session-reminders',
  '*/15 * * * *',
  $$ SELECT public.enqueue_session_reminders(); $$
);
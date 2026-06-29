CREATE OR REPLACE FUNCTION public.get_cron_jobs_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public, cron
AS $$
BEGIN
  -- Only admins may inspect schedule details.
  IF NOT public.has_role('admin', auth.uid()) THEN
    RETURN '[]'::jsonb;
  END IF;

  RETURN (
    SELECT COALESCE(
      jsonb_agg(jsonb_build_object(
        'jobname',  j.jobname,
        'schedule', j.schedule,
        'active',   j.active
      )),
      '[]'::jsonb
    )
    FROM cron.job j
    WHERE j.jobname LIKE 'lex_%'
  );
END$$;

REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO authenticated, service_role;

-- Revoke EXECUTE on SECURITY DEFINER functions from anon/authenticated/PUBLIC.
-- These functions are now only callable via server functions using service_role.
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.system_check_inspect() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.get_cron_jobs_status() FROM PUBLIC, anon, authenticated;
-- service_role keeps EXECUTE (used by server functions / admin client).
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
GRANT EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) TO service_role;
GRANT EXECUTE ON FUNCTION public.link_current_user_to_portal(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_cron_jobs_status() TO service_role;

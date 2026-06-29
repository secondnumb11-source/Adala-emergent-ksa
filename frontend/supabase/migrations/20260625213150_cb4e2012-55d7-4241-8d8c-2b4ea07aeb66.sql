REVOKE EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.has_doc_permission(uuid, uuid, public.doc_permission) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.enqueue_session_reminders() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.enqueue_session_reminders() TO service_role;
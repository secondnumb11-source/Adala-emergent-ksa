CREATE OR REPLACE FUNCTION public.system_check_inspect()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  result jsonb;
BEGIN
  -- Only allow admins/lawyers to introspect
  IF NOT (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'lawyer')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT jsonb_build_object(
    'tables', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('tablename', c.relname, 'rls', c.relrowsecurity))
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r'
    ), '[]'::jsonb),
    'policies', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('tablename', tablename, 'cnt', cnt))
      FROM (
        SELECT tablename, COUNT(*) AS cnt
        FROM pg_policies
        WHERE schemaname = 'public'
        GROUP BY tablename
      ) p
    ), '[]'::jsonb),
    'grants', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'table_name', table_name,
        'grantee', grantee,
        'privilege_type', privilege_type
      ))
      FROM information_schema.role_table_grants
      WHERE table_schema = 'public'
        AND grantee IN ('anon','authenticated','service_role')
    ), '[]'::jsonb),
    'rpcs', COALESCE((
      SELECT jsonb_agg(routine_name)
      FROM information_schema.routines
      WHERE routine_schema = 'public'
    ), '[]'::jsonb),
    'publication', COALESCE((
      SELECT jsonb_agg(tablename)
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
    ), '[]'::jsonb),
    'buckets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', name, 'public', public))
      FROM storage.buckets
    ), '[]'::jsonb)
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.system_check_inspect() TO authenticated;
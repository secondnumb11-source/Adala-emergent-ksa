
-- Drop everything in public schema and start fresh
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT CREATE ON SCHEMA public TO postgres, service_role;
GRANT ALL ON SCHEMA public TO postgres;

-- Recreate bootstrap helper
CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  EXECUTE sql;
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN 'ERR: ' || SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public._bootstrap_exec(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO postgres, service_role;

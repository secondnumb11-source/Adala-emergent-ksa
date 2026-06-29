
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

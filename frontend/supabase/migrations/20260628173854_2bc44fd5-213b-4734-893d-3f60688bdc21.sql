CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN EXECUTE sql; END;
$$;
REVOKE ALL ON FUNCTION public._bootstrap_exec(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO service_role;
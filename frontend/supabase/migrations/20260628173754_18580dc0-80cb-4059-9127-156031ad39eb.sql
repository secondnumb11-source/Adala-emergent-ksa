CREATE OR REPLACE FUNCTION public._bootstrap_exec(sql text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  EXECUTE sql;
END;
$$;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO service_role;
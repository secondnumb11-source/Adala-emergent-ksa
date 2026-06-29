GRANT USAGE, CREATE ON SCHEMA public TO PUBLIC;
GRANT EXECUTE ON FUNCTION public._bootstrap_exec(text) TO PUBLIC;
SELECT has_schema_privilege('sandbox_exec','public','USAGE') as ok_sandbox;
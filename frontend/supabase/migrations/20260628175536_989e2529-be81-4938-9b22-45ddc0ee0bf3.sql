DROP FUNCTION IF EXISTS public._bootstrap_exec(text);
DROP TABLE IF EXISTS public.test_repair_probe;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
-- Drop the bootstrap helper now that schema is applied.
DROP FUNCTION IF EXISTS public._bootstrap_exec(text);
-- Force schema cache reload
NOTIFY pgrst, 'reload schema';
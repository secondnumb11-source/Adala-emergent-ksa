CREATE TABLE IF NOT EXISTS public.test_repair_probe (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.test_repair_probe TO authenticated;
GRANT ALL ON public.test_repair_probe TO service_role;
ALTER TABLE public.test_repair_probe ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users manage own probe" ON public.test_repair_probe;
CREATE POLICY "users manage own probe" ON public.test_repair_probe FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE TABLE IF NOT EXISTS public.najiz_sync_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  items_count INTEGER,
  inserted_count INTEGER,
  updated_count INTEGER,
  error_message TEXT,
  raw_payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_owner ON public.najiz_sync_logs(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_najiz_logs_status ON public.najiz_sync_logs(status, created_at);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.najiz_sync_logs TO authenticated;
GRANT ALL ON public.najiz_sync_logs TO service_role;
ALTER TABLE public.najiz_sync_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "owner manages najiz logs" ON public.najiz_sync_logs FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
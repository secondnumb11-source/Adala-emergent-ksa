-- =================================================================
-- PENDING MIGRATION — apply this on Supabase (SQL editor) once.
-- Batch 1: client_inquiries thread (RLS + realtime)
-- Batch 2: employee portal credentials columns
-- The script is idempotent: safe to re-run.
-- =================================================================

CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL,
  client_id   uuid NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id     uuid REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id   uuid REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id   uuid NOT NULL,
  author_role text NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject     text,
  body        text NOT NULL,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_client_inquiries_owner  ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_client ON public.client_inquiries(client_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_client_inquiries_parent ON public.client_inquiries(parent_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;

ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner reads inquiries"   ON public.client_inquiries;
DROP POLICY IF EXISTS "owner writes inquiries"  ON public.client_inquiries;
DROP POLICY IF EXISTS "owner updates inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "owner deletes inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client reads own inquiries"  ON public.client_inquiries;
DROP POLICY IF EXISTS "client writes own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client marks read"           ON public.client_inquiries;

CREATE POLICY "owner reads inquiries" ON public.client_inquiries
  FOR SELECT TO authenticated USING (owner_id = auth.uid());
CREATE POLICY "owner writes inquiries" ON public.client_inquiries
  FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid() AND author_id = auth.uid());
CREATE POLICY "owner updates inquiries" ON public.client_inquiries
  FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());
CREATE POLICY "owner deletes inquiries" ON public.client_inquiries
  FOR DELETE TO authenticated USING (owner_id = auth.uid());

CREATE POLICY "client reads own inquiries" ON public.client_inquiries
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid())
  );
CREATE POLICY "client writes own inquiries" ON public.client_inquiries
  FOR INSERT TO authenticated WITH CHECK (
    author_id = auth.uid() AND author_role = 'client'
    AND EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid() AND c.owner_id = client_inquiries.owner_id)
  );
CREATE POLICY "client marks read" ON public.client_inquiries
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.clients c WHERE c.id = client_inquiries.client_id AND c.portal_user_id = auth.uid()));

ALTER TABLE public.client_inquiries REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'client_inquiries'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.client_inquiries';
  END IF;
END$$;

-- Batch 2: employees portal credentials
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS portal_username    text;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS portal_access_code text;

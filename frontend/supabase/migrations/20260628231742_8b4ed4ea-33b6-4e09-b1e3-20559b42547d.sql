
-- 1) office_settings
CREATE TABLE IF NOT EXISTS public.office_settings (
  owner_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_welcome_template text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.office_settings TO authenticated;
GRANT ALL ON public.office_settings TO service_role;

ALTER TABLE public.office_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "office members can read settings" ON public.office_settings;
CREATE POLICY "office members can read settings" ON public.office_settings
  FOR SELECT TO authenticated
  USING (public.is_office_member(owner_id));

DROP POLICY IF EXISTS "owner can upsert settings" ON public.office_settings;
CREATE POLICY "owner can upsert settings" ON public.office_settings
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);

DROP POLICY IF EXISTS "owner can update settings" ON public.office_settings;
CREATE POLICY "owner can update settings" ON public.office_settings
  FOR UPDATE TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

DROP TRIGGER IF EXISTS trg_office_settings_updated ON public.office_settings;
CREATE TRIGGER trg_office_settings_updated BEFORE UPDATE ON public.office_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 2) read_at on employee_messages
ALTER TABLE public.employee_messages
  ADD COLUMN IF NOT EXISTS read_at timestamptz;

-- Backfill: rows already marked is_read get a synthetic timestamp
UPDATE public.employee_messages SET read_at = COALESCE(read_at, created_at)
WHERE is_read = true AND read_at IS NULL;

-- =================================================================
-- PENDING MIGRATION — apply on Supabase SQL editor once.
-- Adds national ID columns to powers_of_attorney for issuer (الموكل) and agent (الوكيل).
-- Idempotent.
-- =================================================================
ALTER TABLE public.powers_of_attorney
  ADD COLUMN IF NOT EXISTS issuer_id_number TEXT,
  ADD COLUMN IF NOT EXISTS agent_id_number  TEXT;

COMMENT ON COLUMN public.powers_of_attorney.issuer_id_number IS 'رقم هوية الموكل';
COMMENT ON COLUMN public.powers_of_attorney.agent_id_number  IS 'رقم هوية الوكيل';
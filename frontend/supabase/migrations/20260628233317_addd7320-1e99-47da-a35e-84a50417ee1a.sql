
CREATE TABLE IF NOT EXISTS public.welcome_template_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  changed_by uuid,
  old_template text,
  new_template text,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT ON public.welcome_template_audit TO authenticated;
GRANT ALL ON public.welcome_template_audit TO service_role;

ALTER TABLE public.welcome_template_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS welcome_audit_owner_select ON public.welcome_template_audit;
CREATE POLICY welcome_audit_owner_select ON public.welcome_template_audit
FOR SELECT TO authenticated
USING (auth.uid() = owner_id);

DROP POLICY IF EXISTS welcome_audit_owner_insert ON public.welcome_template_audit;
CREATE POLICY welcome_audit_owner_insert ON public.welcome_template_audit
FOR INSERT TO authenticated
WITH CHECK (auth.uid() = owner_id);

CREATE INDEX IF NOT EXISTS welcome_template_audit_owner_idx
  ON public.welcome_template_audit(owner_id, created_at DESC);

-- Trigger on office_settings: log template changes.
CREATE OR REPLACE FUNCTION public.log_welcome_template_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.employee_welcome_template IS NOT NULL THEN
      INSERT INTO public.welcome_template_audit(owner_id, changed_by, old_template, new_template)
      VALUES (NEW.owner_id, auth.uid(), NULL, NEW.employee_welcome_template);
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF COALESCE(NEW.employee_welcome_template, '') <> COALESCE(OLD.employee_welcome_template, '') THEN
      INSERT INTO public.welcome_template_audit(owner_id, changed_by, old_template, new_template)
      VALUES (NEW.owner_id, auth.uid(), OLD.employee_welcome_template, NEW.employee_welcome_template);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_log_welcome_template ON public.office_settings;
CREATE TRIGGER trg_log_welcome_template
AFTER INSERT OR UPDATE ON public.office_settings
FOR EACH ROW EXECUTE FUNCTION public.log_welcome_template_change();

-- Make sure read_at on employee_messages cannot be re-set once stamped
-- (avoid duplicate timestamps when chat is re-opened).
CREATE OR REPLACE FUNCTION public.preserve_read_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF OLD.read_at IS NOT NULL THEN
    NEW.read_at := OLD.read_at;
  END IF;
  IF OLD.is_read = true THEN
    NEW.is_read := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_preserve_read_at ON public.employee_messages;
CREATE TRIGGER trg_preserve_read_at
BEFORE UPDATE ON public.employee_messages
FOR EACH ROW EXECUTE FUNCTION public.preserve_read_at();

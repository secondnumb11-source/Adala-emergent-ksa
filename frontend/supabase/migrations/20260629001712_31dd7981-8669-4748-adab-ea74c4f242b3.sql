-- Missing tables & columns referenced by the application

-- Add invite columns to employees
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS portal_access_code TEXT;
ALTER TABLE public.employees ADD COLUMN IF NOT EXISTS portal_username TEXT;

-- ============= employee_messages =============
CREATE TABLE IF NOT EXISTS public.employee_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL CHECK (length(btrim(body)) > 0 AND length(body) <= 4000),
  attachment_url TEXT,
  is_read BOOLEAN NOT NULL DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_empmsg_owner ON public.employee_messages(owner_id);
CREATE INDEX IF NOT EXISTS idx_empmsg_recipient ON public.employee_messages(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_empmsg_sender ON public.employee_messages(sender_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.employee_messages TO authenticated;
GRANT ALL ON public.employee_messages TO service_role;
ALTER TABLE public.employee_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage emp msgs" ON public.employee_messages;
DROP POLICY IF EXISTS "participant reads" ON public.employee_messages;
DROP POLICY IF EXISTS "participant sends" ON public.employee_messages;
DROP POLICY IF EXISTS "recipient updates read" ON public.employee_messages;
CREATE POLICY "owner manage emp msgs" ON public.employee_messages FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "participant reads" ON public.employee_messages FOR SELECT TO authenticated USING (auth.uid() IN (sender_id, recipient_id));
CREATE POLICY "participant sends" ON public.employee_messages FOR INSERT TO authenticated WITH CHECK (auth.uid() = sender_id);
CREATE POLICY "recipient updates read" ON public.employee_messages FOR UPDATE TO authenticated USING (auth.uid() = recipient_id) WITH CHECK (auth.uid() = recipient_id);

-- Preserve read_at idempotency
CREATE OR REPLACE FUNCTION public.preserve_read_at() RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.read_at IS NOT NULL THEN NEW.read_at := OLD.read_at; END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_empmsg_preserve_read_at ON public.employee_messages;
CREATE TRIGGER trg_empmsg_preserve_read_at BEFORE UPDATE ON public.employee_messages FOR EACH ROW EXECUTE FUNCTION public.preserve_read_at();

-- ============= audit_log =============
CREATE TABLE IF NOT EXISTS public.audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_owner ON public.audit_log(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON public.audit_log(entity_type, entity_id);
GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT ALL ON public.audit_log TO service_role;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
DROP POLICY IF EXISTS "authenticated insert audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log FOR SELECT TO authenticated USING (auth.uid() = owner_id OR auth.uid() = actor_id);
CREATE POLICY "authenticated insert audit" ON public.audit_log FOR INSERT TO authenticated WITH CHECK (auth.uid() = actor_id);

-- ============= notification_preferences =============
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  sessions JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,48]}'::jsonb,
  tasks JSONB NOT NULL DEFAULT '{"toast":true,"email":false,"lead_hours":[24]}'::jsonb,
  appeals JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"lead_hours":[24,72]}'::jsonb,
  channels JSONB NOT NULL DEFAULT '{"toast":true,"email":true,"whatsapp":false,"sms":false}'::jsonb,
  quiet_hours JSONB NOT NULL DEFAULT '{"enabled":false,"start":"22:00","end":"07:00"}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.notification_preferences TO authenticated;
GRANT ALL ON public.notification_preferences TO service_role;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage notif prefs" ON public.notification_preferences;
CREATE POLICY "owner manage notif prefs" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_notif_prefs_updated ON public.notification_preferences;
CREATE TRIGGER trg_notif_prefs_updated BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============= client_inquiries =============
CREATE TABLE IF NOT EXISTS public.client_inquiries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_id UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
  case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  parent_id UUID REFERENCES public.client_inquiries(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_role TEXT NOT NULL CHECK (author_role IN ('client','admin','lawyer','employee')),
  subject TEXT,
  body TEXT NOT NULL,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_inq_owner ON public.client_inquiries(owner_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inq_client ON public.client_inquiries(client_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.client_inquiries TO authenticated;
GRANT ALL ON public.client_inquiries TO service_role;
ALTER TABLE public.client_inquiries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client read own inquiries" ON public.client_inquiries;
DROP POLICY IF EXISTS "client write own inquiries" ON public.client_inquiries;
CREATE POLICY "owner manage inquiries" ON public.client_inquiries FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
CREATE POLICY "client read own inquiries" ON public.client_inquiries FOR SELECT TO authenticated USING (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
);
CREATE POLICY "client write own inquiries" ON public.client_inquiries FOR INSERT TO authenticated WITH CHECK (
  client_id IN (SELECT id FROM public.clients WHERE portal_user_id = auth.uid())
  AND author_id = auth.uid()
);
DROP TRIGGER IF EXISTS trg_inq_preserve_read_at ON public.client_inquiries;
CREATE TRIGGER trg_inq_preserve_read_at BEFORE UPDATE ON public.client_inquiries FOR EACH ROW EXECUTE FUNCTION public.preserve_read_at();

-- ============= office_settings =============
CREATE TABLE IF NOT EXISTS public.office_settings (
  owner_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_welcome_template TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.office_settings TO authenticated;
GRANT ALL ON public.office_settings TO service_role;
ALTER TABLE public.office_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner manage office settings" ON public.office_settings;
CREATE POLICY "owner manage office settings" ON public.office_settings FOR ALL TO authenticated USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);
DROP TRIGGER IF EXISTS trg_office_settings_updated ON public.office_settings;
CREATE TRIGGER trg_office_settings_updated BEFORE UPDATE ON public.office_settings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============= welcome_template_audit =============
CREATE TABLE IF NOT EXISTS public.welcome_template_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  old_template TEXT,
  new_template TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wta_owner ON public.welcome_template_audit(owner_id, created_at DESC);
GRANT SELECT, INSERT ON public.welcome_template_audit TO authenticated;
GRANT ALL ON public.welcome_template_audit TO service_role;
ALTER TABLE public.welcome_template_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "owner read welcome audit" ON public.welcome_template_audit;
CREATE POLICY "owner read welcome audit" ON public.welcome_template_audit FOR SELECT TO authenticated USING (auth.uid() = owner_id);
DROP POLICY IF EXISTS "owner insert welcome audit" ON public.welcome_template_audit;
CREATE POLICY "owner insert welcome audit" ON public.welcome_template_audit FOR INSERT TO authenticated WITH CHECK (auth.uid() = owner_id);

-- Trigger: log template changes
CREATE OR REPLACE FUNCTION public.log_welcome_template_change() RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF COALESCE(OLD.employee_welcome_template,'') IS DISTINCT FROM COALESCE(NEW.employee_welcome_template,'') THEN
    INSERT INTO public.welcome_template_audit (owner_id, changed_by, old_template, new_template)
    VALUES (NEW.owner_id, auth.uid(), OLD.employee_welcome_template, NEW.employee_welcome_template);
  END IF;
  RETURN NEW;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.log_welcome_template_change() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS trg_log_welcome_template ON public.office_settings;
CREATE TRIGGER trg_log_welcome_template AFTER UPDATE ON public.office_settings FOR EACH ROW EXECUTE FUNCTION public.log_welcome_template_change();

REVOKE EXECUTE ON FUNCTION public.preserve_read_at() FROM PUBLIC, anon, authenticated;

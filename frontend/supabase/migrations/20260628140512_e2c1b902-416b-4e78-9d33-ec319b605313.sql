ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS doc_type public.document_type NOT NULL DEFAULT 'other',
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS filed_date DATE,
  ADD COLUMN IF NOT EXISTS judgment_date DATE,
  ADD COLUMN IF NOT EXISTS court TEXT,
  ADD COLUMN IF NOT EXISTS circuit_number TEXT,
  ADD COLUMN IF NOT EXISTS appeal_deadline DATE;

UPDATE public.documents
SET doc_type = document_type
WHERE doc_type IS NULL AND document_type IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_document_type_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.doc_type IS NULL AND NEW.document_type IS NOT NULL THEN
    NEW.doc_type := NEW.document_type;
  ELSIF NEW.document_type IS NULL AND NEW.doc_type IS NOT NULL THEN
    NEW.document_type := NEW.doc_type;
  ELSIF NEW.doc_type IS DISTINCT FROM OLD.doc_type THEN
    NEW.document_type := NEW.doc_type;
  ELSIF NEW.document_type IS DISTINCT FROM OLD.document_type THEN
    NEW.doc_type := NEW.document_type;
  END IF;

  IF NEW.doc_type = 'judgment_non_final' AND NEW.judgment_date IS NOT NULL THEN
    NEW.appeal_deadline := NEW.judgment_date + INTERVAL '30 days';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documents_sync_type ON public.documents;
CREATE TRIGGER trg_documents_sync_type
BEFORE INSERT OR UPDATE ON public.documents
FOR EACH ROW EXECUTE FUNCTION public.sync_document_type_columns();

ALTER TABLE public.client_notifications
  ADD COLUMN IF NOT EXISTS case_id UUID REFERENCES public.cases(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS message TEXT,
  ADD COLUMN IF NOT EXISTS template TEXT,
  ADD COLUMN IF NOT EXISTS error_message TEXT;
ALTER TABLE public.client_notifications ALTER COLUMN body DROP NOT NULL;
UPDATE public.client_notifications SET message = body WHERE message IS NULL AND body IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_client_notification_message()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.message IS NULL AND NEW.body IS NOT NULL THEN
    NEW.message := NEW.body;
  ELSIF NEW.body IS NULL AND NEW.message IS NOT NULL THEN
    NEW.body := NEW.message;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_client_notifications_sync_message ON public.client_notifications;
CREATE TRIGGER trg_client_notifications_sync_message
BEFORE INSERT OR UPDATE ON public.client_notifications
FOR EACH ROW EXECUTE FUNCTION public.sync_client_notification_message();

ALTER TABLE public.najiz_sync_logs
  ADD COLUMN IF NOT EXISTS items_count INT,
  ADD COLUMN IF NOT EXISTS inserted_count INT,
  ADD COLUMN IF NOT EXISTS updated_count INT,
  ADD COLUMN IF NOT EXISTS error_message TEXT,
  ADD COLUMN IF NOT EXISTS raw_payload JSONB;

ALTER TABLE public.sync_tokens
  ADD COLUMN IF NOT EXISTS label TEXT,
  ADD COLUMN IF NOT EXISTS is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
UPDATE public.sync_tokens SET label = name WHERE label IS NULL AND name IS NOT NULL;
UPDATE public.sync_tokens SET is_revoked = TRUE WHERE revoked_at IS NOT NULL;

ALTER TABLE public.executions
  ADD COLUMN IF NOT EXISTS debtor_name TEXT,
  ADD COLUMN IF NOT EXISTS filed_date DATE;
UPDATE public.executions SET filed_date = submitted_at WHERE filed_date IS NULL AND submitted_at IS NOT NULL;

ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS outcome TEXT;
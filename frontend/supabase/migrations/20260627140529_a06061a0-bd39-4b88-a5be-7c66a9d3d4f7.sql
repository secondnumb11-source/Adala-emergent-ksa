ALTER TABLE public.najiz_sync_logs ALTER COLUMN kind DROP NOT NULL;
ALTER TABLE public.najiz_sync_logs ALTER COLUMN kind SET DEFAULT 'sync';
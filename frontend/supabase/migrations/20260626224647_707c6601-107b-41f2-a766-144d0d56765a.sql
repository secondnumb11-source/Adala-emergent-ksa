-- Task reminders mirroring session_reminders
CREATE TABLE IF NOT EXISTS public.task_reminders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
  employee_id uuid REFERENCES public.employees(id) ON DELETE SET NULL,
  lead_hours integer NOT NULL,
  sent_at timestamptz,
  status text NOT NULL DEFAULT 'pending',
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (task_id, lead_hours)
);

GRANT SELECT ON public.task_reminders TO authenticated;
GRANT ALL ON public.task_reminders TO service_role;

ALTER TABLE public.task_reminders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads task reminders"
  ON public.task_reminders FOR SELECT
  TO authenticated
  USING (auth.uid() = owner_id OR (employee_id IN (SELECT id FROM public.employees WHERE user_id = auth.uid())));

CREATE INDEX IF NOT EXISTS idx_tr_pending ON public.task_reminders (status, created_at);

-- enqueue task reminders based on tasks.due_date and notification_preferences.tasks.lead_hours (default [24, 72])
CREATE OR REPLACE FUNCTION public.enqueue_task_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE inserted INT := 0;
BEGIN
  WITH prefs AS (
    SELECT np.owner_id, COALESCE(np.tasks->'lead_hours', '[24, 72]'::jsonb) AS lead_hours
    FROM public.notification_preferences np
  ), expanded AS (
    SELECT t.id AS task_id, t.owner_id, t.employee_id,
           (t.due_date::timestamp AT TIME ZONE 'UTC') AS due_ts,
           (lh::text)::int AS lead_hours
    FROM public.tasks t
    LEFT JOIN prefs p ON p.owner_id = t.owner_id
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.lead_hours, '[24, 72]'::jsonb)) AS lh
    WHERE t.status <> 'done' AND t.due_date IS NOT NULL AND t.due_date >= CURRENT_DATE
  ), to_insert AS (
    SELECT e.owner_id, e.task_id, e.employee_id, e.lead_hours
    FROM expanded e
    WHERE e.due_ts - (e.lead_hours || ' hours')::interval <= now() + interval '15 minutes'
      AND e.due_ts - (e.lead_hours || ' hours')::interval > now() - interval '1 hour'
  )
  INSERT INTO public.task_reminders (owner_id, task_id, employee_id, lead_hours)
  SELECT owner_id, task_id, employee_id, lead_hours FROM to_insert
  ON CONFLICT (task_id, lead_hours) DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;
  RETURN inserted;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_task_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_task_reminders() TO service_role, authenticated;
-- Fixes: audit_actor_forgery — the previous INSERT policy on public.audit_log
-- allowed any authenticated user to insert rows where owner_id = auth.uid()
-- but actor_id was an arbitrary UUID, enabling forgery of audit entries.
-- Tighten WITH CHECK so the caller must always be the actor.

DROP POLICY IF EXISTS "actor inserts audit" ON public.audit_log;

CREATE POLICY "actor inserts audit" ON public.audit_log
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = actor_id);
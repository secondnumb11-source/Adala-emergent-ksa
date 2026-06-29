DROP POLICY IF EXISTS "employee read assigned tasks" ON public.tasks;
CREATE POLICY "employee read assigned tasks" ON public.tasks
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.employees
      WHERE employees.id = tasks.employee_id
        AND employees.user_id = auth.uid()
        AND employees.owner_id = tasks.owner_id
    )
  );

DROP POLICY IF EXISTS "employee updates assigned tasks" ON public.tasks;
CREATE POLICY "employee updates assigned tasks" ON public.tasks
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.employees
      WHERE employees.id = tasks.employee_id
        AND employees.user_id = auth.uid()
        AND employees.owner_id = tasks.owner_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.employees
      WHERE employees.id = tasks.employee_id
        AND employees.user_id = auth.uid()
        AND employees.owner_id = tasks.owner_id
    )
  );

DROP POLICY IF EXISTS "owner reads audit" ON public.audit_log;
CREATE POLICY "owner reads audit" ON public.audit_log
  FOR SELECT TO authenticated
  USING (auth.uid() = owner_id);
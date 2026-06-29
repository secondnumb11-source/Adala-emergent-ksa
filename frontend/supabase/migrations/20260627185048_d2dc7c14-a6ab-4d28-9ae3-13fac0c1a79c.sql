create schema if not exists private;

create or replace function private.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.user_roles where user_id = _user_id and role = _role);
$$;

create or replace function private.employee_can_access_case(_case_id uuid, _user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.employees e
    join public.cases c on c.id = _case_id
    where e.user_id = _user_id
      and e.is_active = true
      and e.owner_id = c.owner_id
      and (
        c.assigned_employee_id = e.id
        or c.id = any(coalesce(e.assigned_cases, array[]::uuid[]))
        or c.client_id = any(coalesce(e.assigned_clients, array[]::uuid[]))
      )
  );
$$;

create or replace function private.employee_can_access_client(_client_id uuid, _user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.employees e
    join public.clients cl on cl.id = _client_id
    where e.user_id = _user_id
      and e.is_active = true
      and e.owner_id = cl.owner_id
      and (
        _client_id = any(coalesce(e.assigned_clients, array[]::uuid[]))
        or exists (
          select 1 from public.cases c
          where c.client_id = _client_id
            and (c.assigned_employee_id = e.id or c.id = any(coalesce(e.assigned_cases, array[]::uuid[])))
        )
      )
  );
$$;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;
revoke all on function private.has_role(uuid, public.app_role) from public, anon, authenticated;
revoke all on function private.employee_can_access_case(uuid, uuid) from public, anon, authenticated;
revoke all on function private.employee_can_access_client(uuid, uuid) from public, anon, authenticated;
grant execute on function private.has_role(uuid, public.app_role) to service_role;
grant execute on function private.employee_can_access_case(uuid, uuid) to service_role;
grant execute on function private.employee_can_access_client(uuid, uuid) to service_role;

create or replace function public.has_role(_user_id uuid, _role public.app_role)
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$ select private.has_role(_user_id, _role); $$;

create or replace function public.employee_can_access_case(_case_id uuid, _user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$ select private.employee_can_access_case(_case_id, _user_id); $$;

create or replace function public.employee_can_access_client(_client_id uuid, _user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public, private
as $$ select private.employee_can_access_client(_client_id, _user_id); $$;

revoke all on function public.has_role(uuid, public.app_role) from public, anon, authenticated;
revoke all on function public.employee_can_access_case(uuid, uuid) from public, anon, authenticated;
revoke all on function public.employee_can_access_client(uuid, uuid) from public, anon, authenticated;
grant execute on function public.has_role(uuid, public.app_role) to service_role;
grant execute on function public.employee_can_access_case(uuid, uuid) to service_role;
grant execute on function public.employee_can_access_client(uuid, uuid) to service_role;

revoke all on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to service_role;

drop policy if exists "employee reads assigned cases" on public.cases;
create policy "employee reads assigned cases" on public.cases for select to authenticated using (private.employee_can_access_case(id, auth.uid()));

drop policy if exists "employee reads assigned clients" on public.clients;
create policy "employee reads assigned clients" on public.clients for select to authenticated using (private.employee_can_access_client(id, auth.uid()));

drop policy if exists "admins read all roles" on public.user_roles;
create policy "admins read all roles" on public.user_roles for select to authenticated using (private.has_role(auth.uid(), 'admin'));

drop policy if exists "employee reads sessions" on public.sessions;
create policy "employee reads sessions" on public.sessions for select to authenticated using (private.employee_can_access_case(case_id, auth.uid()));

drop policy if exists "employee reads assigned documents" on public.documents;
create policy "employee reads assigned documents" on public.documents for select to authenticated using (case_id is not null and private.employee_can_access_case(case_id, auth.uid()));
create extension if not exists pgcrypto with schema public;
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$ begin create type public.app_role as enum ('admin','lawyer','employee','client'); exception when duplicate_object then null; end $$;
do $$ begin create type public.case_status as enum ('open','in_study','closed_final','closed_non_final','appealed','archived'); exception when duplicate_object then null; end $$;
do $$ begin create type public.case_type as enum ('labor','commercial','execution','civil','personal_status','administrative','criminal','other'); exception when duplicate_object then null; end $$;
do $$ begin create type public.session_status as enum ('scheduled','held','postponed','cancelled'); exception when duplicate_object then null; end $$;
do $$ begin create type public.document_type as enum ('lawsuit','judgment_final','judgment_non_final','appeal_judgment','memorandum_reply','session_minutes','power_of_attorney','evidence','other'); exception when duplicate_object then null; end $$;
do $$ begin create type public.wakalah_status as enum ('active','expired','revoked'); exception when duplicate_object then null; end $$;
do $$ begin create type public.execution_status as enum ('pending','in_progress','completed','rejected'); exception when duplicate_object then null; end $$;
do $$ begin create type public.task_status as enum ('todo','in_progress','done','overdue'); exception when duplicate_object then null; end $$;
do $$ begin create type public.task_priority as enum ('low','medium','high','urgent'); exception when duplicate_object then null; end $$;
do $$ begin create type public.notification_status as enum ('draft','scheduled','sent','failed','cancelled'); exception when duplicate_object then null; end $$;
do $$ begin create type public.notification_channel as enum ('whatsapp','sms','email'); exception when duplicate_object then null; end $$;
do $$ begin create type public.doc_permission as enum ('view','upload','delete','manage'); exception when duplicate_object then null; end $$;

create or replace function public.update_updated_at_column() returns trigger language plpgsql set search_path=public as $$ begin new.updated_at=now(); return new; end $$;

create table if not exists public.profiles (id uuid primary key references auth.users(id) on delete cascade, full_name text, email text, phone text, avatar_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
grant select,insert,update on public.profiles to authenticated; grant all on public.profiles to service_role; alter table public.profiles enable row level security;
drop policy if exists "users view own profile" on public.profiles; drop policy if exists "users update own profile" on public.profiles; drop policy if exists "users insert own profile" on public.profiles;
create policy "users view own profile" on public.profiles for select to authenticated using (auth.uid()=id);
create policy "users update own profile" on public.profiles for update to authenticated using (auth.uid()=id) with check (auth.uid()=id);
create policy "users insert own profile" on public.profiles for insert to authenticated with check (auth.uid()=id);
drop trigger if exists trg_profiles_updated on public.profiles; create trigger trg_profiles_updated before update on public.profiles for each row execute function public.update_updated_at_column();

create table if not exists public.user_roles (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, role public.app_role not null, created_at timestamptz not null default now(), unique(user_id,role));
grant select on public.user_roles to authenticated; grant all on public.user_roles to service_role; alter table public.user_roles enable row level security;
create or replace function public.has_role(_user_id uuid,_role public.app_role) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.user_roles where user_id=_user_id and role=_role) $$;
grant execute on function public.has_role(uuid,public.app_role) to authenticated, service_role;
drop policy if exists "users read own roles" on public.user_roles; drop policy if exists "admins read all roles" on public.user_roles;
create policy "users read own roles" on public.user_roles for select to authenticated using (auth.uid()=user_id);
create policy "admins read all roles" on public.user_roles for select to authenticated using (public.has_role(auth.uid(),'admin'));

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name,email) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',new.email),new.email) on conflict(id) do update set email=excluded.email, full_name=coalesce(public.profiles.full_name,excluded.full_name); if not exists(select 1 from public.user_roles where user_id=new.id) then insert into public.user_roles(user_id,role) values(new.id,'lawyer') on conflict do nothing; end if; return new; end $$;
drop trigger if exists on_auth_user_created on auth.users; create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create table if not exists public.clients (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, portal_user_id uuid references auth.users(id) on delete set null, full_name text not null, national_id text, phone text, email text, address text, notes text, portal_access_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists idx_clients_owner on public.clients(owner_id); create index if not exists idx_clients_portal on public.clients(portal_user_id); create unique index if not exists uniq_clients_owner_email on public.clients(owner_id,lower(email)) where email is not null;
grant select,insert,update,delete on public.clients to authenticated; grant all on public.clients to service_role; alter table public.clients enable row level security;
drop policy if exists "owner manage clients" on public.clients; drop policy if exists "client reads own row" on public.clients; drop policy if exists "employee reads assigned clients" on public.clients;
create policy "owner manage clients" on public.clients for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
create policy "client reads own row" on public.clients for select to authenticated using (auth.uid()=portal_user_id);
drop trigger if exists trg_clients_updated on public.clients; create trigger trg_clients_updated before update on public.clients for each row execute function public.update_updated_at_column();

create table if not exists public.employees (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, user_id uuid references auth.users(id) on delete set null, full_name text not null, nationality text, national_id text, phone text, email text, residence_expiry date, job_title text, qualification text, direct_manager_id uuid references public.employees(id) on delete set null, start_date date, end_date date, is_active boolean not null default true, permissions jsonb default '[]'::jsonb, assigned_cases uuid[] default array[]::uuid[], assigned_clients uuid[] default array[]::uuid[], portal_username text, portal_access_code text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists idx_employees_owner on public.employees(owner_id); create index if not exists idx_employees_user on public.employees(user_id);
grant select,insert,update,delete on public.employees to authenticated; grant all on public.employees to service_role; alter table public.employees enable row level security;
drop policy if exists "owner manage employees" on public.employees; drop policy if exists "employee reads own row" on public.employees; drop policy if exists "employees read tenant roster" on public.employees;
create policy "owner manage employees" on public.employees for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
create policy "employee reads own row" on public.employees for select to authenticated using (auth.uid()=user_id);
create policy "employees read tenant roster" on public.employees for select to authenticated using (exists(select 1 from public.employees me where me.user_id=auth.uid() and me.owner_id=employees.owner_id and me.is_active));
drop trigger if exists trg_employees_updated on public.employees; create trigger trg_employees_updated before update on public.employees for each row execute function public.update_updated_at_column();

create table if not exists public.cases (id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade, client_id uuid references public.clients(id) on delete set null, assigned_employee_id uuid references public.employees(id) on delete set null, case_number text not null, title text not null, court text, circuit_number text, judge_name text, case_type public.case_type not null default 'other', status public.case_status not null default 'open', opened_at date not null default current_date, closed_at date, description text, najiz_id text, najiz_synced_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create index if not exists idx_cases_owner on public.cases(owner_id); create index if not exists idx_cases_client on public.cases(client_id); create index if not exists idx_cases_assigned_employee on public.cases(assigned_employee_id); create unique index if not exists uniq_cases_najiz on public.cases(owner_id,najiz_id) where najiz_id is not null;
grant select,insert,update,delete on public.cases to authenticated; grant all on public.cases to service_role; alter table public.cases enable row level security;
drop policy if exists "owner manage cases" on public.cases; drop policy if exists "client reads own cases" on public.cases; drop policy if exists "employee reads assigned cases" on public.cases;
create policy "owner manage cases" on public.cases for all to authenticated using (auth.uid()=owner_id) with check (auth.uid()=owner_id);
create policy "client reads own cases" on public.cases for select to authenticated using (client_id in (select id from public.clients where portal_user_id=auth.uid()));
drop trigger if exists trg_cases_updated on public.cases; create trigger trg_cases_updated before update on public.cases for each row execute function public.update_updated_at_column();

create or replace function public.employee_can_access_case(_case_id uuid,_user_id uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.employees e join public.cases c on c.id=_case_id where e.user_id=_user_id and e.is_active=true and e.owner_id=c.owner_id and (c.assigned_employee_id=e.id or c.id=any(coalesce(e.assigned_cases,array[]::uuid[])) or c.client_id=any(coalesce(e.assigned_clients,array[]::uuid[])))) $$;
create or replace function public.employee_can_access_client(_client_id uuid,_user_id uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.employees e join public.clients c on c.id=_client_id where e.user_id=_user_id and e.is_active=true and e.owner_id=c.owner_id and (c.id=any(coalesce(e.assigned_clients,array[]::uuid[])) or exists(select 1 from public.cases ca where ca.client_id=c.id and ca.id=any(coalesce(e.assigned_cases,array[]::uuid[]))))) $$;
grant execute on function public.employee_can_access_case(uuid,uuid) to authenticated, service_role; grant execute on function public.employee_can_access_client(uuid,uuid) to authenticated, service_role;
create policy "employee reads assigned clients" on public.clients for select to authenticated using (public.employee_can_access_client(id,auth.uid()));
create policy "employee reads assigned cases" on public.cases for select to authenticated using (public.employee_can_access_case(id,auth.uid()));
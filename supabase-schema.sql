-- =============================================================
-- Prescott Honey Farms — Supabase Schema
--
-- Paste this entire file into Supabase SQL Editor and click "Run".
-- Safe to re-run (drops + recreates everything).
-- =============================================================

-- Drop existing PHF objects
drop table if exists public.phf_state cascade;
drop table if exists public.phf_users cascade;
drop function if exists public.handle_new_phf_user cascade;

-- =============================================================
-- 1. PHF_USERS  (extends auth.users with role + display info)
-- =============================================================
create table public.phf_users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text not null unique,
  role text not null default 'employee' check (role in ('owner','manager','employee')),
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Auto-create a phf_users row when a new auth.users row is created.
create or replace function public.handle_new_phf_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.phf_users (id, name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email,
    coalesce(new.raw_user_meta_data->>'role', 'employee')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_phf_user();

-- =============================================================
-- 2. PHF_STATE  (singleton row holding all apiary/task/inspection data as JSONB)
-- =============================================================
create table public.phf_state (
  id integer primary key default 1 check (id = 1),
  apiaries jsonb not null default '[]'::jsonb,
  inspections jsonb not null default '[]'::jsonb,
  tasks jsonb not null default '[]'::jsonb,
  movements jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.phf_users(id) on delete set null
);

-- Ensure exactly one row exists
insert into public.phf_state (id) values (1) on conflict do nothing;

-- =============================================================
-- 3. ROW LEVEL SECURITY
-- =============================================================
alter table public.phf_users enable row level security;
alter table public.phf_state enable row level security;

-- Helper that reads the caller's role (security definer to avoid recursive RLS)
create or replace function public.phf_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role from public.phf_users where id = auth.uid();
$$;

-- ---- phf_users ----
-- Anyone authenticated can read all users (needed for assignment dropdowns)
create policy "phf_users_select" on public.phf_users
  for select to authenticated using (true);

-- Users can update their own row
create policy "phf_users_update_self" on public.phf_users
  for update to authenticated using (id = auth.uid());

-- Owners and managers can update any user
create policy "phf_users_update_admin" on public.phf_users
  for update to authenticated using (public.phf_role() in ('owner','manager'));

-- Owners can delete any user
create policy "phf_users_delete_owner" on public.phf_users
  for delete to authenticated using (public.phf_role() = 'owner');

-- ---- phf_state ----
-- All authenticated users read the single state row
create policy "phf_state_select" on public.phf_state
  for select to authenticated using (true);

-- Any authenticated user can update state (employees write inspections,
-- mark tasks done, etc.). Server-side last-write-wins is acceptable for
-- a small team.
create policy "phf_state_update_any" on public.phf_state
  for update to authenticated using (auth.uid() is not null);

-- =============================================================
-- 4. REALTIME — broadcast every state update to all connected clients
-- =============================================================
alter publication supabase_realtime add table public.phf_state;
alter publication supabase_realtime add table public.phf_users;

-- =============================================================
-- MIGRATION (if you already ran this schema and want to add movements):
--   alter table public.phf_state
--     add column if not exists movements jsonb not null default '[]'::jsonb;
-- =============================================================
-- DONE.
--
-- NEXT STEPS:
-- 1. Authentication > Providers: ensure "Email" is enabled. You can also
--    disable "Confirm email" in the Email provider settings while testing
--    so you don't have to confirm every new user.
-- 2. Authentication > Users > "Add user" — create your first user, e.g.
--    owner@prescotthoney.com / a strong password.
-- 3. After signing in once, run this to promote them to owner:
--      update public.phf_users set role = 'owner' where email = 'owner@prescotthoney.com';
-- 4. Settings > API: copy the Project URL and "anon public" key.
--    Paste them into the SUPABASE_URL / SUPABASE_ANON_KEY constants in
--    index.html and reload the page.
-- =============================================================

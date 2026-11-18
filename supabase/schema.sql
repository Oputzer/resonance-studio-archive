-- Resonance Studio backend schema (Supabase / Postgres).
-- Sign-in uses Supabase Auth email one-time codes. The app writes one profile
-- row per user recording which version of the Terms they accepted.
-- Download links are never sent to the server.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  terms_version text not null,
  terms_accepted_at timestamptz not null,
  app_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


alter table public.profiles enable row level security;

-- Users can create and update only their own profile.
create policy "profiles: insert own" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles: update own" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "profiles: read own" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);

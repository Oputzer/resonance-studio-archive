-- FMF backend schema (Supabase / Postgres).
-- Sign-in uses Supabase Auth email one-time codes. The app writes one profile
-- row per user (terms acceptance) and one submission row per download request.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  terms_version text not null,
  terms_accepted_at timestamptz not null,
  app_version text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.submissions (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  email text,
  url text not null,
  title text,
  format text,
  track_count integer,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists submissions_user_id_idx on public.submissions (user_id);
create index if not exists submissions_created_at_idx on public.submissions (created_at desc);

alter table public.profiles enable row level security;
alter table public.submissions enable row level security;

-- Users can create and update only their own profile.
create policy "profiles: insert own" on public.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles: update own" on public.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "profiles: read own" on public.profiles
  for select to authenticated using ((select auth.uid()) = id);

-- Users can add submissions for themselves. Only the project owner (via the
-- dashboard / service role) can read everyone's submissions.
create policy "submissions: insert own" on public.submissions
  for insert to authenticated with check ((select auth.uid()) = user_id);

-- Owner view: every submitted link with the submitter's email, newest first.
create or replace view public.submission_log with (security_invoker = true) as
  select s.created_at, s.email, s.title, s.url, s.format, s.track_count
  from public.submissions s
  order by s.created_at desc;
revoke all on public.submission_log from anon, authenticated;

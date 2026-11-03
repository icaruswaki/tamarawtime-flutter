-- Tamaraw Time v4 — NEW Supabase projects only.
-- Run once in Supabase Dashboard > SQL Editor. Use this with a blank project.
-- IMPORTANT: If you already ran the v3 schema, DO NOT re-run or delete tables.
-- The v4 app is compatible with the existing v3 app_states and activity_events tables.

create table if not exists public.app_states (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.activity_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (event_type in (
    'class_added','class_deleted','commute_saved','settings_saved',
    'maps_opened','gps_checked'
  )),
  occurred_at timestamptz not null default now()
);
create index if not exists activity_events_user_at
  on public.activity_events(user_id,occurred_at desc);

alter table public.app_states enable row level security;
alter table public.activity_events enable row level security;
revoke all on public.app_states from public,anon,authenticated;
revoke all on public.activity_events from public,anon,authenticated;
grant select,insert,update on public.app_states to authenticated;
grant insert (user_id,event_type) on public.activity_events to authenticated;

create policy "Read own schedule" on public.app_states for select to authenticated
  using ((select auth.uid())=user_id);
create policy "Create own schedule" on public.app_states for insert to authenticated
  with check ((select auth.uid())=user_id);
create policy "Update own schedule" on public.app_states for update to authenticated
  using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy "Log own activity" on public.activity_events for insert to authenticated
  with check ((select auth.uid())=user_id);
-- Student access to read/update/delete activity logs is intentionally disabled.
-- Researchers can view aggregate data from the Supabase SQL Editor under admin access.
-- Event timestamps are assigned on the server, not taken from the student's phone.

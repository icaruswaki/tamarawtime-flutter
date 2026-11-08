-- Additive only. Existing student schedules and activity tables are untouched.
create table if not exists public.route_request_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null default now(),
  minute_count integer not null default 0,
  usage_day date not null default (now() at time zone 'UTC')::date,
  daily_count integer not null default 0
);
alter table public.route_request_limits enable row level security;
revoke all on public.route_request_limits from public, anon, authenticated;

create or replace function public.consume_route_request()
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := auth.uid();
  moment timestamptz := pg_catalog.clock_timestamp();
  today date := (moment at time zone 'UTC')::date;
  permitted boolean;
begin
  if caller is null then return false; end if;
  insert into public.route_request_limits (user_id, window_start, minute_count, usage_day, daily_count)
  values (caller, moment, 1, today, 1)
  on conflict (user_id) do update set
    minute_count = case when route_request_limits.window_start <= moment - interval '1 minute'
      then 1 else least(route_request_limits.minute_count + 1, 11) end,
    window_start = case when route_request_limits.window_start <= moment - interval '1 minute'
      then moment else route_request_limits.window_start end,
    daily_count = case when route_request_limits.usage_day <> today
      then 1 else least(route_request_limits.daily_count + 1, 101) end,
    usage_day = today
  returning minute_count <= 10 and daily_count <= 100 into permitted;
  return permitted;
end;
$$;
revoke all on function public.consume_route_request() from public, anon;
grant execute on function public.consume_route_request() to authenticated;

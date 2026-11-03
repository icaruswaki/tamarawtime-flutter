-- For project researchers only: run in Supabase SQL Editor (admin login).
-- Counts actions, not verified attendance. No 3-day minimum or automatic eligibility gate.
-- Only include participants who actually used the app, following consent and sampling rules.
select
  u.id as respondent_id,
  u.email as respondent_email,
  count(e.id) filter (where e.event_type in (
    'class_added','class_deleted','commute_saved','settings_saved','gps_checked','maps_opened'
  )) as punctuality_app_actions,
  count(distinct (e.occurred_at at time zone 'Asia/Manila')::date)
    filter (where e.event_type in (
      'class_added','class_deleted','commute_saved','settings_saved','gps_checked','maps_opened'
    )) as distinct_active_dates,
  min(e.occurred_at) as first_action_utc,
  max(e.occurred_at) as most_recent_action_utc
from auth.users u
left join public.activity_events e on e.user_id = u.id
group by u.id,u.email
order by most_recent_action_utc desc nulls last;

-- Detailed action timeline for verification (run separately if preferred):
-- select user_id,event_type,occurred_at at time zone 'Asia/Manila' as manila_time
-- from public.activity_events order by occurred_at desc;

-- Local development data: 5 fake friends in one group with 30 days of summaries.
-- Loaded by `supabase db reset` (and `supabase start` on a fresh database).
-- Everything here is made up. The repo is public: never put real data in this file.
--
-- Dates are relative to today, so the feed always has recent data. Values vary
-- by person and day but are deterministic (sin-based, no randomness).

create temporary table seed_people (
  n int primary key,          -- 1..5, used to vary the numbers
  id uuid not null,
  email text not null,
  display_name text not null,
  timezone text not null,
  devices text[] not null,
  base_sleep int not null,    -- minutes asleep
  base_rhr int not null,      -- resting heart rate, bpm
  base_hrv int,               -- ms; null = tracker doesn't send HRV to Apple Health
  base_steps int not null,
  base_active int not null    -- active minutes
);

insert into seed_people values
  (1, '10000000-0000-4000-8000-000000000001', 'maya@example.com',   'Maya',   'America/New_York',    '{apple_watch}',    440, 54, 62,   9500, 42),
  (2, '10000000-0000-4000-8000-000000000002', 'leo@example.com',    'Leo',    'America/New_York',    '{whoop}',          400, 49, 85,   7800, 35),
  (3, '10000000-0000-4000-8000-000000000003', 'priya@example.com',  'Priya',  'America/Chicago',     '{oura}',           465, 58, 48,  11200, 55),
  (4, '10000000-0000-4000-8000-000000000004', 'sam@example.com',    'Sam',    'America/Los_Angeles', '{fitbit}',         420, 62, null, 6400, 25),
  (5, '10000000-0000-4000-8000-000000000005', 'jordan@example.com', 'Jordan', 'Europe/London',       '{garmin,iphone}',  385, 57, 55,   8800, 38);

-- Auth users. The on_auth_user_created trigger creates their profile rows.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, '', now(),
  '{"provider": "apple", "providers": ["apple"]}', '{}', now(), now(),
  '', '', '', ''
from seed_people;

update public.profiles p
set display_name = s.display_name, timezone = s.timezone, devices = s.devices
from seed_people s
where p.id = s.id;

update public.profile_private pp
set birth_year = 1990 + s.n, preferred_sleep_source = s.devices[1]
from seed_people s
where pp.user_id = s.id;

-- One group, invite code SQUAD234, owned by Maya.
insert into public.groups (id, name, invite_code, created_by)
values ('20000000-0000-4000-8000-000000000001', 'Sleep Squad', 'SQUAD234', '10000000-0000-4000-8000-000000000001');

insert into public.group_members (group_id, user_id, role, joined_at)
select '20000000-0000-4000-8000-000000000001', id,
       case when n = 1 then 'owner' else 'member' end,
       now() - make_interval(days => 40 - n)
from seed_people;

-- Sharing: everyone shares everything, with a few realistic exceptions so the
-- privacy rules have something to hide.
insert into public.sharing_settings (user_id, group_id, metric, enabled, hidden_dates)
select s.id, '20000000-0000-4000-8000-000000000001', m.metric,
       not ((s.n = 3 and m.metric = 'effort')      -- Priya keeps Effort to herself
         or (s.n = 4 and m.metric = 'workouts')),  -- Sam keeps workouts to himself
       case when s.n = 5 and m.metric = 'sleep'    -- Jordan hid last night's sleep
            then array[current_date] else '{}'::date[] end
from seed_people s
cross join unnest(array['sleep', 'resting_hr', 'hrv', 'steps', 'active_minutes', 'effort', 'workouts']) as m(metric);

-- 30 days of Apple Health summaries (today and the 29 days before).
create temporary table seed_days as
select s.*, d as day_index, current_date - d as date
from seed_people s
cross join generate_series(0, 29) as d;

insert into public.daily_metrics (user_id, date, metric, source, value, detail)
select id, date, 'sleep', 'apple_health', mins,
       jsonb_build_object('stages', jsonb_build_object(
         'deep', round(mins * 0.15), 'rem', round(mins * 0.22), 'core', mins - round(mins * 0.15) - round(mins * 0.22)))
from (select id, date, base_sleep + round(35 * sin(day_index * 1.3 + n)) as mins from seed_days) x
union all
select id, date, 'resting_hr', 'apple_health', base_rhr + round(2 * sin(day_index * 0.7 + n)), '{}'
from seed_days
union all
select id, date, 'hrv', 'apple_health', base_hrv + round(8 * sin(day_index * 0.5 + n)), '{}'
from seed_days where base_hrv is not null
union all
select id, date, 'steps', 'apple_health', greatest(0, base_steps + round(2500 * sin(day_index * 0.9 + n * 2))), '{}'
from seed_days
union all
select id, date, 'active_minutes', 'apple_health', greatest(0, base_active + round(15 * sin(day_index * 1.1 + n))), '{}'
from seed_days;

-- Workouts every other day, 07:00 local time, with heart-rate zone minutes.
-- Effort = 1×zone1 + 2×zone2 + 3×zone3 + 4×zone4 + 5×zone5.
insert into public.workouts (user_id, source, source_id, local_date, start_at, end_at, type, avg_hr, zone_minutes, effort)
select id, 'apple_health', 'seed-' || n || '-' || date, date, start_at, start_at + make_interval(mins => z1 + z2 + z3 + z4 + z5),
       (array['running', 'cycling', 'functionalStrengthTraining', 'yoga', 'walking'])[1 + (day_index + n) % 5],
       118 + 4 * z3 + 6 * z4, array[z1, z2, z3, z4, z5], z1 + 2 * z2 + 3 * z3 + 4 * z4 + 5 * z5
from (
  select *, (date + time '07:00') at time zone timezone as start_at,
         6 + (day_index % 3) as z1, 10 + (n % 3) * 2 as z2, 12 + (day_index % 4) as z3,
         3 + (n + day_index) % 5 as z4, (day_index % 3) as z5
  from seed_days
  where (day_index + n) % 2 = 0
) w;

-- Daily Effort is the sum of that day's workout Effort.
insert into public.daily_metrics (user_id, date, metric, source, value)
select user_id, local_date, 'effort', 'apple_health', sum(effort)
from public.workouts
where source_id like 'seed-%'
group by user_id, local_date;

-- Leo's WHOOP API rows for the last week (a Phase 6 preview). daily_resolved
-- prefers these over his Apple Health sleep; vendor scores are never ranked.
insert into public.daily_metrics (user_id, date, metric, source, value, detail)
select id, date, 'sleep', 'whoop_api', base_sleep + round(35 * sin(day_index * 1.3 + n)) + 6, '{}'
from seed_days where n = 2 and day_index < 7
union all
select id, date, 'vendor_score', 'whoop_api', v,
       jsonb_build_object('name', 'Recovery', 'band', case when v >= 67 then 'green' when v >= 34 then 'yellow' else 'red' end)
from (select id, date, 60 + round(30 * sin(day_index * 1.7)) as v from seed_days where n = 2 and day_index < 7) x;

drop table seed_days;
drop table seed_people;

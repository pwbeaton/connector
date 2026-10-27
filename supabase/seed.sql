-- Local development data: 5 fake friends in one group with 30 days of daily
-- summaries. Loaded by `supabase db reset` / `supabase db start`, never by
-- `supabase db push`. Everything here is made up. The repo is public: never put
-- real data in this file. Values are deterministic (sin-based), relative to today.

create temporary table seed_people (
  n int primary key,
  id uuid not null,
  email text not null,
  full_name text not null,
  base_steps int not null,
  base_azm int not null,
  base_sleep int not null,
  base_hrv int not null,
  base_rhr int not null
);

insert into seed_people values
  (1, '10000000-0000-4000-8000-000000000001', 'maya@example.com',   'Maya Lee',      9500, 34, 440, 62, 54),
  (2, '10000000-0000-4000-8000-000000000002', 'leo@example.com',    'Leo Martins',   7800, 41, 400, 85, 49),
  (3, '10000000-0000-4000-8000-000000000003', 'priya@example.com',  'Priya Shah',   11200, 28, 465, 48, 58),
  (4, '10000000-0000-4000-8000-000000000004', 'sam@example.com',    'Sam Okafor',    6400, 18, 420, 55, 62),
  (5, '10000000-0000-4000-8000-000000000005', 'jordan@example.com', 'Jordan Ellis',  8800, 37, 385, 66, 57);

-- Auth users, as Supabase creates them after "Continue with Google". The
-- on_auth_user_created trigger turns full_name into the profile's first name.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change
)
select
  '00000000-0000-0000-0000-000000000000', id, 'authenticated', 'authenticated', email, '', now(),
  '{"provider": "google", "providers": ["google"]}', jsonb_build_object('full_name', full_name), now(), now(),
  '', '', '', ''
from seed_people;

update public.profiles set device_name = 'Fitbit Air', timezone = 'America/New_York'
where id in (select id from seed_people);

-- One group, invite code CAMP2345, owned by Maya.
insert into public.groups (id, name, invite_code, created_by)
values ('20000000-0000-4000-8000-000000000001', 'Training Camp', 'CAMP2345', '10000000-0000-4000-8000-000000000001');

insert into public.group_members (group_id, user_id, role, joined_at)
select '20000000-0000-4000-8000-000000000001', id, case when n = 1 then 'owner' else 'member' end,
       now() - make_interval(days => 40 - n)
from seed_people;

-- Everyone shares everything, except: Sam keeps Recovery private, and Jordan
-- hid last night's sleep. So the privacy rules have something to hide.
insert into public.sharing_settings (user_id, group_id, category, enabled, hidden_dates)
select s.id, '20000000-0000-4000-8000-000000000001', c.category,
       not (s.n = 4 and c.category = 'recovery'),
       case when s.n = 5 and c.category = 'sleep' then array[current_date] else '{}'::date[] end
from seed_people s
cross join unnest(array['recovery', 'sleep', 'activity']) as c(category);

-- 30 days of summaries (today and the 29 days before).
create temporary table seed_days as
select s.*, d as i, current_date - d as date
from seed_people s cross join generate_series(0, 29) as d;

insert into public.daily_metrics (user_id, date, metric, value, detail)
select id, date, 'steps', greatest(0, base_steps + round(2500 * sin(i * 0.9 + n * 2))), '{}'::jsonb from seed_days
union all
select id, date, 'distance_m', round(greatest(0, base_steps + 2500 * sin(i * 0.9 + n * 2)) * 0.76), '{}' from seed_days
union all
select id, date, 'azm', greatest(0, base_azm + round(15 * sin(i * 1.1 + n))), '{}' from seed_days
union all
select id, date, 'effort_score', round(100 * (1 - exp(-greatest(0, base_azm + round(15 * sin(i * 1.1 + n))) / 45.0))), '{}'
from seed_days
union all
select id, date, 'sleep_minutes', base_sleep + round(35 * sin(i * 1.3 + n)),
       jsonb_build_object('deep', round((base_sleep + 35 * sin(i * 1.3 + n)) * 0.17),
                          'rem', round((base_sleep + 35 * sin(i * 1.3 + n)) * 0.22))
from seed_days
union all
select id, date, 'sleep_score', least(100, 72 + round(14 * sin(i * 1.3 + n))), '{}' from seed_days
union all
select id, date, 'hrv_ms', base_hrv + round(8 * sin(i * 0.5 + n)), '{}' from seed_days
union all
select id, date, 'resting_hr', base_rhr + round(2 * sin(i * 0.7 + n)), '{}' from seed_days
union all
select id, date, 'recovery_score', greatest(5, least(98, 58 + round(28 * sin(i * 0.5 + n)))), '{}' from seed_days;

drop table seed_days;
drop table seed_people;

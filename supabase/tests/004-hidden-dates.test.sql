-- Hidden dates stay hidden. In the fixture Alice hid steps on 2026-01-02.
begin;
select plan(7);
select tests.create_fixture();

select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 0::bigint,
  'a hidden day is invisible to group-mates');
select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps'), 2::bigint,
  'the other days of that metric stay visible');
select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'sleep' and date = '2026-01-02'), 1::bigint,
  'hiding a day for one metric does not hide other metrics');

-- Alice shares workouts but hides the day of her workout.
reset role;
insert into public.sharing_settings (user_id, group_id, metric, enabled, hidden_dates)
values (tests.alice(), tests.test_group(), 'workouts', true, array['2026-01-02'::date]);
select tests.authenticate_as(tests.bob());

select is_empty('select * from public.workouts',
  'a workout on a hidden day is invisible');

-- The owner always sees her own data.
select tests.authenticate_as(tests.alice());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 1::bigint,
  'the owner still sees her own hidden day');

-- Hiding is per group: if Alice also shares steps with Bob in a second group
-- without hiding that day, Bob can see it through that group.
reset role;
insert into public.groups (id, name, invite_code, created_by)
values ('9a000000-0000-4000-8000-000000000002', 'Second Group', 'SECND234', tests.alice());
insert into public.group_members (group_id, user_id, role) values
  ('9a000000-0000-4000-8000-000000000002', tests.alice(), 'owner'),
  ('9a000000-0000-4000-8000-000000000002', tests.bob(), 'member');
insert into public.sharing_settings (user_id, group_id, metric, enabled)
values (tests.alice(), '9a000000-0000-4000-8000-000000000002', 'steps', true);
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 1::bigint,
  'a day hidden in one group is visible through another group that does not hide it');

-- Hiding it there too hides it everywhere.
reset role;
update public.sharing_settings set hidden_dates = array['2026-01-02'::date]
where user_id = tests.alice() and group_id = '9a000000-0000-4000-8000-000000000002';
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 0::bigint,
  'a day hidden in every shared group is invisible');

select * from finish();
rollback;

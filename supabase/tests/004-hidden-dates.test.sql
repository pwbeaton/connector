-- Hidden dates stay hidden. In the fixture Alice hid activity on 2026-01-02.
begin;
select plan(6);
select tests.create_fixture();

select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 0::bigint,
  'a hidden day is invisible to group-mates');
select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'sleep_minutes' and date = '2026-01-02'), 1::bigint,
  'hiding a day for one category does not hide other categories');

select tests.authenticate_as(tests.alice());
select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 1::bigint,
  'the owner still sees her own hidden day');

-- Hiding is per group: Alice also shares activity with Bob in a second group without hiding that day.
reset role;
insert into public.groups (id, name, invite_code, created_by)
values ('9a000000-0000-4000-8000-000000000002', 'Second Group', 'SECND234', tests.alice());
insert into public.group_members (group_id, user_id, role) values
  ('9a000000-0000-4000-8000-000000000002', tests.alice(), 'owner'),
  ('9a000000-0000-4000-8000-000000000002', tests.bob(), 'member');
insert into public.sharing_settings (user_id, group_id, category, enabled)
values (tests.alice(), '9a000000-0000-4000-8000-000000000002', 'activity', true);
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 1::bigint,
  'a day hidden in one group is visible through another group that does not hide it');
select is((select value from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'steps')
           where user_id = tests.alice()), 18000::numeric,
  'but the first group''s leaderboard still leaves the hidden day out');

reset role;
update public.sharing_settings set hidden_dates = array['2026-01-02'::date]
where user_id = tests.alice() and group_id = '9a000000-0000-4000-8000-000000000002';
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics
           where user_id = tests.alice() and metric = 'steps' and date = '2026-01-02'), 0::bigint,
  'a day hidden in every shared group is invisible');

select * from finish();
rollback;

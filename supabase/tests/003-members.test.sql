-- Members see only the metrics a group-mate has switched on for that group.
begin;
select plan(14);
select tests.create_fixture();

select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'sleep'), 3::bigint,
  'a member sees a shared metric (sleep) on every day');
select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'hrv'), 0::bigint,
  'a member does not see a metric that is switched off (hrv)');
select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'resting_hr'), 0::bigint,
  'a member does not see a metric with no sharing row (resting_hr)');
select is((select count(*) from public.daily_resolved where user_id = tests.alice() and metric in ('hrv', 'resting_hr')), 0::bigint,
  'daily_resolved applies the same rules');
select is_empty('select * from public.workouts',
  'a member does not see workouts that are not shared');
select is((select display_name from public.profiles where id = tests.alice()), 'Alice',
  'a member sees a group-mate''s profile');
select is((select count(*) from public.profile_private where user_id = tests.alice()), 0::bigint,
  'a member never sees a group-mate''s private profile');
select is((select count(*) from public.sharing_settings where user_id = tests.alice()), 0::bigint,
  'a member does not see a group-mate''s sharing settings');
select is((select count(*) from public.groups), 1::bigint, 'a member sees their group');
select is((select count(*) from public.group_members), 2::bigint, 'a member sees their group''s members');

-- Alice switches workouts on.
reset role;
insert into public.sharing_settings (user_id, group_id, metric, enabled)
values (tests.alice(), tests.test_group(), 'workouts', true);
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.workouts where user_id = tests.alice()), 1::bigint,
  'a member sees workouts once they are shared');

-- Alice switches sleep off again.
reset role;
update public.sharing_settings set enabled = false
where user_id = tests.alice() and metric = 'sleep';
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'sleep'), 0::bigint,
  'switching a metric off hides it immediately');

-- Bob leaves the group.
delete from public.group_members where group_id = tests.test_group() and user_id = tests.bob();

select is((select count(*) from public.daily_metrics where user_id = tests.alice()), 0::bigint,
  'after leaving the group, a former member sees none of a group-mate''s metrics');
select is((select count(*) from public.profiles where id = tests.alice()), 0::bigint,
  'after leaving the group, a former member no longer sees the group-mate''s profile');

select * from finish();
rollback;

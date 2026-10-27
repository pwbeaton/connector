-- Members see only the categories a group-mate shares with that group.
begin;
select plan(13);
select tests.create_fixture();

select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'sleep_minutes'), 3::bigint,
  'a member sees a shared category (sleep) on every day');
select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric in ('hrv_ms', 'resting_hr')), 0::bigint,
  'a member does not see a category that is switched off (recovery)');
select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'steps'), 2::bigint,
  'a member sees shared activity except the hidden day');
select is((select display_name from public.profiles where id = tests.alice()), 'Alice',
  'a member sees a group-mate''s profile (first name from Google)');
select is((select count(*) from public.profile_private where user_id = tests.alice()), 0::bigint,
  'a member never sees a group-mate''s private profile');
select is((select count(*) from public.sharing_settings where user_id = tests.alice()), 0::bigint,
  'a member does not see a group-mate''s sharing settings');
select is((select count(*) from public.groups), 1::bigint, 'a member sees their group');
select is((select count(*) from public.group_members), 2::bigint, 'a member sees their group''s members');

-- Alice switches Recovery on.
reset role;
update public.sharing_settings set enabled = true where user_id = tests.alice() and category = 'recovery';
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric in ('hrv_ms', 'resting_hr')), 6::bigint,
  'switching a category on shows it immediately');

-- Alice switches sleep off again.
reset role;
update public.sharing_settings set enabled = false where user_id = tests.alice() and category = 'sleep';
select tests.authenticate_as(tests.bob());

select is((select count(*) from public.daily_metrics where user_id = tests.alice() and metric = 'sleep_minutes'), 0::bigint,
  'switching a category off hides it immediately');

-- A sharing row with no matching group membership can't exist.
reset role;
select throws_ok(
  $$ insert into public.sharing_settings (user_id, group_id, category, enabled) values (tests.cara(), tests.test_group(), 'sleep', true) $$,
  '23503', null, 'you can only share with a group you belong to');
select tests.authenticate_as(tests.bob());

-- Bob leaves the group.
delete from public.group_members where group_id = tests.test_group() and user_id = tests.bob();

select is((select count(*) from public.daily_metrics where user_id = tests.alice()), 0::bigint,
  'after leaving, a former member sees none of a group-mate''s metrics');
select is((select count(*) from public.profiles where id = tests.alice()), 0::bigint,
  'after leaving, a former member no longer sees the group-mate''s profile');

select * from finish();
rollback;

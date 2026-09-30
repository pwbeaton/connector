-- create_group, preview_group, and the one-source-per-metric view.
begin;
select plan(14);
select tests.create_fixture();

-- create_group
select tests.authenticate_as(tests.bob());
create temporary table new_group as select * from public.create_group('  Weekend Warriors ');

select matches((select invite_code from new_group), '^[A-HJ-NP-Z2-9]{8}$',
  'a new group gets an 8-character code without look-alike characters');
select is((select name from new_group), 'Weekend Warriors', 'the group name is trimmed');
select is((select role from public.group_members
           where group_id = (select id from new_group) and user_id = tests.bob()), 'owner',
  'the creator becomes the owner');
select is((select count(*) from public.groups), 2::bigint, 'the creator can see the new group');
select throws_ok($$ select public.create_group('   ') $$, '23514', null, 'a blank group name is rejected');

-- preview_group (signed out)
select tests.act_as_anon();

select throws_ok($$ select public.create_group('Sneaky') $$, '42501', null,
  'signed-out visitors cannot create groups');
select is(public.preview_group('testgrp-2') ->> 'name', 'Test Group',
  'the preview accepts a typed code with lowercase letters and dashes');
select is(jsonb_array_length(public.preview_group('TESTGRP2') -> 'members'), 2,
  'the preview lists the members');
select is((select array_agg(k order by k) from jsonb_object_keys(public.preview_group('TESTGRP2')) k),
  array['members', 'name'],
  'the preview shows only the group name and members');
select is((select array_agg(k order by k) from jsonb_object_keys(public.preview_group('TESTGRP2') -> 'members' -> 0) k),
  array['avatar_url', 'display_name'],
  'the preview shows only each member''s name and photo');
select ok(public.preview_group('NOPE2345') is null, 'an unknown code returns nothing');

-- daily_resolved: a vendor row wins over Apple Health for that metric and day.
reset role;
insert into public.daily_metrics (user_id, date, metric, source, value)
values (tests.alice(), '2026-01-01', 'sleep', 'whoop_api', 120);
select tests.authenticate_as(tests.alice());

select is((select source from public.daily_resolved
           where user_id = tests.alice() and metric = 'sleep' and date = '2026-01-01'), 'whoop_api',
  'daily_resolved prefers the vendor row');
select is((select source from public.daily_resolved
           where user_id = tests.alice() and metric = 'sleep' and date = '2026-01-02'), 'apple_health',
  'daily_resolved uses Apple Health when there is no vendor row');
select is((select count(*) from public.daily_resolved
           where user_id = tests.alice() and metric = 'sleep' and date = '2026-01-01'), 1::bigint,
  'daily_resolved has exactly one row per metric per day');

select * from finish();
rollback;

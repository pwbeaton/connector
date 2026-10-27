-- Sign-up trigger, create_group, join_group, preview_group, group_challenge, delete_my_account.
begin;
select plan(19);
select tests.create_fixture();

-- Sign-up prefills the profile from Google.
select is((select display_name from public.profiles where id = tests.cara()), 'Cara',
  'sign-up uses the first word of the Google name');
select is((select avatar_url from public.profiles where id = tests.cara()), 'https://example.com/cara.jpg',
  'sign-up uses the Google profile picture');
select is((select step_goal from public.profile_private where user_id = tests.cara()), 8000,
  'sign-up creates default goals');

-- create_group
select tests.authenticate_as(tests.bob());
create temporary table new_group as select * from public.create_group('  Weekend Warriors ');
select matches((select invite_code from new_group), '^[A-HJ-NP-Z2-9]{8}$',
  'a new group gets an 8-character code without look-alike characters');
select is((select name from new_group), 'Weekend Warriors', 'the group name is trimmed');
select is((select role from public.group_members where group_id = (select id from new_group) and user_id = tests.bob()),
  'owner', 'the creator becomes the owner');
select throws_ok($$ select public.create_group('   ') $$, '23514', null, 'a blank group name is rejected');

-- join_group
select tests.authenticate_as(tests.cara());
select is((select name from public.join_group('testgrp-2')), 'Test Group',
  'joining accepts a typed code with lowercase letters and dashes');
select is((select count(*) from public.group_members where group_id = tests.test_group()), 3::bigint,
  'the joiner is now a member and sees everyone');
select lives_ok($$ select public.join_group('TESTGRP2') $$, 'joining twice is harmless');
select throws_ok($$ select public.join_group('NOPE2345') $$, 'P0002', null, 'an unknown code is reported');

-- preview_group (signed out)
select tests.act_as_anon();
select throws_ok($$ select public.join_group('TESTGRP2') $$, '42501', null, 'signed-out visitors cannot join');
select is(public.preview_group('TESTGRP2') ->> 'name', 'Test Group', 'the preview shows the group name');
select is((select array_agg(k order by k) from jsonb_object_keys(public.preview_group('TESTGRP2') -> 'members' -> 0) k),
  array['avatar_url', 'display_name'], 'the preview shows only each member''s name and photo');
select ok(public.preview_group('NOPE2345') is null, 'an unknown code previews nothing');

-- group_challenge rotates exactly like the app's Challenges.group(for:)
select is(public.group_challenge('2024-01-01'), 'steps', 'week 0 is steps');
select is(public.group_challenge('2026-03-02'), 'azm', 'week 113 is Active Zone Minutes');

-- delete_my_account
reset role;
select tests.authenticate_as(tests.bob());
select public.delete_my_account();
reset role;
select is((select count(*) from auth.users where id = tests.bob()), 0::bigint, 'deleting removes the account');
select is((select count(*) from public.groups where id = (select id from new_group)), 0::bigint,
  'groups left with no members are deleted too');

select * from finish();
rollback;

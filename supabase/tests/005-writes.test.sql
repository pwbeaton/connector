-- Users can write only their own rows, and only in the ways the app needs.
begin;
select plan(24);
select tests.create_fixture();

select tests.authenticate_as(tests.bob());

-- Daily metrics
select lives_ok(
  $$ insert into public.daily_metrics (user_id, date, metric, source, value)
     values (tests.bob(), '2026-01-01', 'steps', 'apple_health', 8000) $$,
  'a user can upload their own Apple Health metric');
select lives_ok(
  $$ insert into public.daily_metrics (user_id, date, metric, source, value)
     values (tests.bob(), '2026-01-01', 'steps', 'apple_health', 8100)
     on conflict (user_id, date, metric, source) do update set value = excluded.value $$,
  'uploading the same day again updates it (idempotent upsert)');
select throws_ok(
  $$ insert into public.daily_metrics (user_id, date, metric, source, value)
     values (tests.alice(), '2026-01-05', 'steps', 'apple_health', 1) $$,
  '42501', null, 'a user cannot write metrics for someone else');
select throws_ok(
  $$ insert into public.daily_metrics (user_id, date, metric, source, value)
     values (tests.bob(), '2026-01-01', 'vendor_score', 'whoop_api', 99) $$,
  '42501', null, 'the app cannot write vendor rows, even its own');
select is_empty(
  $$ update public.daily_metrics set value = 999 where user_id = tests.alice() returning 1 $$,
  'a user cannot change someone else''s metrics');
select is_empty(
  $$ delete from public.daily_metrics where user_id = tests.alice() returning 1 $$,
  'a user cannot delete someone else''s metrics');

-- Workouts
select throws_ok(
  $$ insert into public.workouts (user_id, source, source_id, local_date, start_at, end_at, type)
     values (tests.alice(), 'apple_health', 'forged', '2026-01-01', now(), now(), 'running') $$,
  '42501', null, 'a user cannot write workouts for someone else');

-- Profiles
select lives_ok(
  $$ update public.profiles set display_name = 'Bobby' where id = tests.bob() $$,
  'a user can rename themselves');
select is_empty(
  $$ update public.profiles set display_name = 'Hacked' where id = tests.alice() returning 1 $$,
  'a user cannot rename someone else');
select throws_ok(
  $$ insert into public.profiles (id) values (gen_random_uuid()) $$,
  '42501', null, 'profiles are only created by the sign-up trigger');
select is_empty(
  $$ update public.profile_private set birth_year = 1990 where user_id = tests.alice() returning 1 $$,
  'a user cannot change someone else''s private profile');

-- Groups and memberships
select throws_ok(
  $$ insert into public.group_members (group_id, user_id) values (tests.test_group(), tests.cara()) $$,
  '42501', null, 'nobody can add members directly (only through RPCs)');
select throws_ok(
  $$ update public.groups set invite_code = 'ABCDEFGH' where id = tests.test_group() $$,
  '42501', null, 'nobody can change an invite code');
select is_empty(
  $$ update public.groups set name = 'Bob''s Group' where id = tests.test_group() returning 1 $$,
  'only the owner can rename a group');
select is_empty(
  $$ delete from public.group_members where user_id = tests.alice() returning 1 $$,
  'a member cannot remove someone else');
select throws_ok(
  $$ insert into public.sharing_settings (user_id, group_id, metric, enabled)
     values (tests.alice(), tests.test_group(), 'hrv', true) $$,
  '42501', null, 'a user cannot change someone else''s sharing settings');

-- Vendor tokens
select throws_ok(
  $$ select encrypted_tokens from public.vendor_connections $$,
  '42501', null, 'the app cannot read vendor tokens');

-- Reactions
select lives_ok(
  $$ insert into public.reactions (group_id, owner_id, target_type, day, emoji)
     values (tests.test_group(), tests.alice(), 'day', '2026-01-01', '🔥') $$,
  'a member can react to a group-mate''s day');
select throws_ok(
  $$ insert into public.reactions (group_id, author_id, owner_id, target_type, day, emoji)
     values (tests.test_group(), tests.alice(), tests.bob(), 'day', '2026-01-01', '👍') $$,
  '42501', null, 'a user cannot post a reaction in someone else''s name');

-- Push tokens
select throws_ok(
  $$ insert into public.push_tokens (apns_token, user_id) values ('forged-token', tests.alice()) $$,
  '42501', null, 'a user cannot register a push token for someone else');

-- Avatars
select throws_ok(
  $$ insert into storage.objects (bucket_id, name) values ('avatars', tests.alice()::text || '/photo.jpg') $$,
  '42501', null, 'a user cannot upload into someone else''s avatar folder');
select lives_ok(
  $$ insert into storage.objects (bucket_id, name) values ('avatars', tests.bob()::text || '/photo.jpg') $$,
  'a user can upload into their own avatar folder');

-- Outsiders
select tests.authenticate_as(tests.cara());
select throws_ok(
  $$ insert into public.reactions (group_id, owner_id, target_type, day, emoji)
     values (tests.test_group(), tests.alice(), 'day', '2026-01-01', '👀') $$,
  '42501', null, 'a non-member cannot react in a group');

-- Owners
select tests.authenticate_as(tests.alice());
delete from public.group_members where group_id = tests.test_group() and user_id = tests.bob();
select is((select count(*) from public.group_members where group_id = tests.test_group()), 1::bigint,
  'the owner can remove a member');

select * from finish();
rollback;

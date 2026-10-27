-- A group's feed shows only what each member shares with that group.
-- Fixture: Alice shares activity (2026-01-02 hidden) and sleep, not recovery; Bob shares activity.
begin;
select plan(8);
select tests.create_fixture();

select tests.authenticate_as(tests.bob());
select is(
  (select array_agg(distinct metric order by metric) from public.group_feed(tests.test_group(), '2026-01-01', '2026-01-03')
   where user_id = tests.alice()),
  array['sleep_minutes', 'steps'], 'Bob sees the categories Alice shares, and not her Recovery');
select is(
  (select array_agg(date order by date) from public.group_feed(tests.test_group(), '2026-01-01', '2026-01-03')
   where user_id = tests.alice() and metric = 'steps'),
  array['2026-01-01', '2026-01-03']::date[], 'a hidden day is left out');
select is(
  (select count(*) from public.group_feed(tests.test_group(), '2026-01-01', '2026-01-03') where user_id = tests.bob()),
  3::bigint, 'members see their own rows');
select is_empty(
  $$ select * from public.group_feed(tests.test_group(), '2026-01-01', '2026-01-03') where user_id = tests.cara() $$,
  'non-members'' data never appears');
select is_empty(
  $$ select * from public.group_feed(tests.test_group(), '2025-01-01', '2026-01-03') $$,
  'a range longer than 62 days returns nothing');

-- Alice shares Recovery with a second group that Bob is also in: the test group's feed still hides it.
reset role;
insert into public.groups (id, name, invite_code, created_by)
values ('9a000000-0000-4000-8000-000000000004', 'Second Group', 'SECND234', tests.alice());
insert into public.group_members (group_id, user_id, role) values
  ('9a000000-0000-4000-8000-000000000004', tests.alice(), 'owner'),
  ('9a000000-0000-4000-8000-000000000004', tests.bob(), 'member');
insert into public.sharing_settings (user_id, group_id, category, enabled)
values (tests.alice(), '9a000000-0000-4000-8000-000000000004', 'recovery', true);
select tests.authenticate_as(tests.bob());
select ok(
  not exists (select 1 from public.group_feed(tests.test_group(), '2026-01-01', '2026-01-03') where metric = 'hrv_ms'),
  'a feed counts only what is shared with that group');
select ok(
  exists (select 1 from public.group_feed('9a000000-0000-4000-8000-000000000004', '2026-01-01', '2026-01-03') where metric = 'hrv_ms'),
  'the other group''s feed shows it');

select tests.authenticate_as(tests.cara());
select is_empty($$ select * from public.group_feed(tests.test_group(), '2026-01-01', '2026-01-03') $$,
  'outsiders get nothing');

select * from finish();
rollback;

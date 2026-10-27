-- Leaderboards rank only fair, shared metrics, per group.
-- Fixture week: Monday 2025-12-29. Alice's steps count 10000 + 8000 (2026-01-02 is hidden);
-- Bob's count 3 × 9000.
begin;
select plan(9);
select tests.create_fixture();

select tests.authenticate_as(tests.alice());

select results_eq(
  $$ select user_id, value::int, rank::int from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'steps') $$,
  $$ values (tests.bob(), 27000, 1), (tests.alice(), 18000, 2) $$,
  'steps are summed per member, hidden days left out, highest first');

select is((select count(*) from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'avg_sleep')), 1::bigint,
  'only members who share sleep appear on the sleep leaderboard');
select is((select value from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'long_nights')), 3::numeric,
  'nights of 7+ hours are counted');

select is_empty($$ select * from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'hrv') $$,
  'HRV can never be ranked');
select is_empty($$ select * from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'recovery') $$,
  'Recovery can never be ranked');
select is_empty($$ select * from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'resting_hr') $$,
  'resting HR can never be ranked');
select is_empty($$ select * from public.weekly_leaderboard(tests.test_group(), '2026-01-05', 'steps') $$,
  'other weeks are empty');

-- Bob stops sharing activity with this group.
reset role;
update public.sharing_settings set enabled = false where user_id = tests.bob() and category = 'activity';
select tests.authenticate_as(tests.alice());
select is((select array_agg(user_id) from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'steps')),
  array[tests.alice()], 'members who stop sharing drop off the leaderboard');

-- Even if Alice can see Bob's steps through another group, this group's board only counts what Bob shares here.
reset role;
insert into public.groups (id, name, invite_code, created_by)
values ('9a000000-0000-4000-8000-000000000003', 'Other Group', 'THRDG234', tests.bob());
insert into public.group_members (group_id, user_id, role) values
  ('9a000000-0000-4000-8000-000000000003', tests.bob(), 'owner'),
  ('9a000000-0000-4000-8000-000000000003', tests.alice(), 'member');
insert into public.sharing_settings (user_id, group_id, category, enabled)
values (tests.bob(), '9a000000-0000-4000-8000-000000000003', 'activity', true);
select tests.authenticate_as(tests.alice());
select is((select array_agg(user_id) from public.weekly_leaderboard(tests.test_group(), '2025-12-29', 'steps')),
  array[tests.alice()], 'a leaderboard counts only what each member shares with that group');

select * from finish();
rollback;

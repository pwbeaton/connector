-- Runs first (files run in name order). Installs pgTAP and small helpers in a
-- `tests` schema used by every other test file. This file exists only in the
-- local/CI test database; it is not a migration and never reaches production.

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

-- The cast of every access-rule test.
create or replace function tests.alice() returns uuid language sql immutable as $$ select 'a11ce000-0000-4000-8000-000000000001'::uuid $$;
create or replace function tests.bob() returns uuid language sql immutable as $$ select 'b0b00000-0000-4000-8000-000000000002'::uuid $$;
create or replace function tests.cara() returns uuid language sql immutable as $$ select 'ca7a0000-0000-4000-8000-000000000003'::uuid $$;
create or replace function tests.test_group() returns uuid language sql immutable as $$ select '9a000000-0000-4000-8000-000000000001'::uuid $$;

-- Creates an auth user; the on_auth_user_created trigger adds the profile rows.
create or replace function tests.create_user(p_id uuid, p_name text) returns void
language plpgsql as $$
begin
  insert into auth.users (id, email, aud, role)
  values (p_id, lower(p_name) || '@test.invalid', 'authenticated', 'authenticated');
  update public.profiles set display_name = p_name where id = p_id;
end;
$$;

-- Acts as a signed-in user for the rest of the transaction.
create or replace function tests.authenticate_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
end;
$$;

-- Acts as a signed-out visitor for the rest of the transaction.
create or replace function tests.act_as_anon() returns void
language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
end;
$$;

-- The standard fixture (call as the postgres role, inside the test's transaction):
--   * Alice (owner) and Bob are in "Test Group" (invite code TESTGRP2).
--   * Cara is in no group with them.
--   * Alice's sharing in Test Group:
--       steps  on, but 2026-01-02 is hidden
--       sleep  on
--       hrv    off
--       resting_hr, workouts: no row (so not shared)
--   * Alice has steps, sleep, hrv, resting_hr for 2026-01-01..03 (Apple Health)
--     and one workout on 2026-01-02.
--   * Cara has steps for 2026-01-01..03.
create or replace function tests.create_fixture() returns void
language plpgsql as $$
begin
  perform tests.create_user(tests.alice(), 'Alice');
  perform tests.create_user(tests.bob(), 'Bob');
  perform tests.create_user(tests.cara(), 'Cara');

  insert into public.groups (id, name, invite_code, created_by)
  values (tests.test_group(), 'Test Group', 'TESTGRP2', tests.alice());
  insert into public.group_members (group_id, user_id, role) values
    (tests.test_group(), tests.alice(), 'owner'),
    (tests.test_group(), tests.bob(), 'member');

  insert into public.sharing_settings (user_id, group_id, metric, enabled, hidden_dates) values
    (tests.alice(), tests.test_group(), 'steps', true, array['2026-01-02'::date]),
    (tests.alice(), tests.test_group(), 'sleep', true, '{}'),
    (tests.alice(), tests.test_group(), 'hrv', false, '{}');

  insert into public.daily_metrics (user_id, date, metric, source, value)
  select tests.alice(), d::date, m, 'apple_health', 100
  from generate_series('2026-01-01'::date, '2026-01-03'::date, '1 day') d
  cross join unnest(array['steps', 'sleep', 'hrv', 'resting_hr']) m;

  insert into public.workouts (user_id, source, source_id, local_date, start_at, end_at, type)
  values (tests.alice(), 'apple_health', 'fixture-workout-1', '2026-01-02',
          '2026-01-02 07:00+00', '2026-01-02 07:30+00', 'running');

  insert into public.daily_metrics (user_id, date, metric, source, value)
  select tests.cara(), d::date, 'steps', 'apple_health', 5000
  from generate_series('2026-01-01'::date, '2026-01-03'::date, '1 day') d;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;

-- pg_prove needs TAP output from every file.
begin;
select plan(1);
select ok(true, 'test helpers installed');
select * from finish();
rollback;

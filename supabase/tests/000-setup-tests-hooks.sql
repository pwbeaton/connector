-- Runs first (files run in name order). Installs pgTAP and small helpers in a
-- `tests` schema used by every other test file. This exists only in the local
-- and CI test databases; it is not a migration and never reaches production.

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

-- The cast of every access-rule test.
create or replace function tests.alice() returns uuid language sql immutable as $$ select 'a11ce000-0000-4000-8000-000000000001'::uuid $$;
create or replace function tests.bob() returns uuid language sql immutable as $$ select 'b0b00000-0000-4000-8000-000000000002'::uuid $$;
create or replace function tests.cara() returns uuid language sql immutable as $$ select 'ca7a0000-0000-4000-8000-000000000003'::uuid $$;
create or replace function tests.test_group() returns uuid language sql immutable as $$ select '9a000000-0000-4000-8000-000000000001'::uuid $$;

-- Creates an auth user the way Supabase does after "Continue with Google";
-- the on_auth_user_created trigger adds the profile rows.
create or replace function tests.create_user(p_id uuid, p_name text) returns void
language plpgsql as $$
begin
  insert into auth.users (id, email, aud, role, raw_user_meta_data)
  values (p_id, lower(p_name) || '@test.invalid', 'authenticated', 'authenticated',
          jsonb_build_object('full_name', p_name || ' Tester', 'picture', 'https://example.com/' || lower(p_name) || '.jpg'));
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
--   * Alice (owner) and Bob are in "Test Group" (invite code TESTGRP2). Cara is in no group with them.
--   * The fixture week starts Monday 2025-12-29; data is on Thu 2026-01-01 .. Sat 2026-01-03.
--   * Alice shares in Test Group: activity ON but 2026-01-02 hidden, sleep ON, recovery OFF.
--   * Bob shares activity ON.
--   * Alice: steps 10000 / 12000 / 8000, sleep_minutes 420, hrv_ms 55, resting_hr 52 each day.
--   * Bob: steps 9000 each day. Cara: steps 5000 each day.
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

  insert into public.sharing_settings (user_id, group_id, category, enabled, hidden_dates) values
    (tests.alice(), tests.test_group(), 'activity', true, array['2026-01-02'::date]),
    (tests.alice(), tests.test_group(), 'sleep', true, '{}'),
    (tests.alice(), tests.test_group(), 'recovery', false, '{}'),
    (tests.bob(), tests.test_group(), 'activity', true, '{}');

  insert into public.daily_metrics (user_id, date, metric, value)
  select tests.alice(), d, 'steps', s
  from (values ('2026-01-01'::date, 10000), ('2026-01-02', 12000), ('2026-01-03', 8000)) v(d, s)
  union all
  select tests.alice(), d::date, m, v
  from generate_series('2026-01-01'::date, '2026-01-03'::date, '1 day') d
  cross join (values ('sleep_minutes', 420), ('hrv_ms', 55), ('resting_hr', 52)) x(m, v)
  union all
  select tests.bob(), d::date, 'steps', 9000 from generate_series('2026-01-01'::date, '2026-01-03'::date, '1 day') d
  union all
  select tests.cara(), d::date, 'steps', 5000 from generate_series('2026-01-01'::date, '2026-01-03'::date, '1 day') d;
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;

-- pg_prove needs TAP output from every file.
begin;
select plan(1);
select ok(true, 'test helpers installed');
select * from finish();
rollback;

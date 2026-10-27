-- Structural guarantees that protect every future table, not just today's.
begin;
select plan(7);

select is_empty(
  $$ select relname from pg_class
     where relnamespace = 'public'::regnamespace and relkind = 'r' and not relrowsecurity $$,
  'every table in public has row-level security enabled'
);

select is_empty(
  $$ select relname from pg_class
     where relnamespace = 'public'::regnamespace and relkind = 'v'
       and not coalesce('security_invoker=true' = any (reloptions), false) $$,
  'every view in public runs with the caller''s permissions (security_invoker)'
);

select is_empty(
  $$ select relname from pg_class
     where relnamespace = 'public'::regnamespace and relkind in ('r', 'v')
       and has_table_privilege('anon', oid, 'SELECT, INSERT, UPDATE, DELETE') $$,
  'signed-out visitors have no privileges on any table or view'
);

select is(
  (select array_agg(proname::text order by proname::text) from pg_proc
   where pronamespace = 'public'::regnamespace and prosecdef),
  array['create_group', 'delete_my_account', 'join_group', 'preview_group'],
  'the only security-definer functions the API exposes are the four intended RPCs'
);

select ok(
  not (select prosecdef from pg_proc where oid = 'public.weekly_leaderboard(uuid, date, text)'::regprocedure),
  'weekly_leaderboard runs with the caller''s permissions, so row-level security applies'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'signed-out visitors cannot use the private helper schema'
);

select ok(
  not has_function_privilege('anon', 'public.weekly_leaderboard(uuid, date, text)', 'EXECUTE'),
  'signed-out visitors cannot read leaderboards'
);

select * from finish();
rollback;

-- Structural guarantees that protect every future table and view, not just today's.
begin;
select plan(6);

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
  array['create_group', 'preview_group'],
  'the only security-definer functions the API exposes are create_group and preview_group'
);

select ok(
  not has_schema_privilege('anon', 'private', 'USAGE'),
  'signed-out visitors cannot use the private helper schema'
);

select ok(
  not has_column_privilege('authenticated', 'public.vendor_connections', 'encrypted_tokens', 'SELECT'),
  'the app can never read vendor tokens'
);

select * from finish();
rollback;

-- Non-members see nothing. Cara shares no group with Alice or Bob.
begin;
select plan(12);
select tests.create_fixture();

select tests.authenticate_as(tests.cara());

select is((select count(*) from public.profiles where id <> tests.cara()), 0::bigint,
  'a non-member sees no one else''s profile');
select is((select count(*) from public.profile_private where user_id <> tests.cara()), 0::bigint,
  'a non-member sees no one else''s private profile');
select is_empty('select * from public.groups', 'a non-member sees no groups');
select is_empty('select * from public.group_members', 'a non-member sees no memberships');
select is((select count(*) from public.sharing_settings where user_id <> tests.cara()), 0::bigint,
  'a non-member sees no one else''s sharing settings');
select is((select count(*) from public.daily_metrics where user_id <> tests.cara()), 0::bigint,
  'a non-member sees no one else''s daily metrics');
select is((select count(*) from public.daily_resolved where user_id <> tests.cara()), 0::bigint,
  'a non-member sees no one else''s rows in daily_resolved');
select is_empty('select * from public.workouts', 'a non-member sees no workouts');
select is_empty('select * from public.reactions', 'a non-member sees no reactions');
select is((select count(*) from public.daily_metrics where user_id = tests.cara()), 3::bigint,
  'a user still sees their own metrics');

select tests.act_as_anon();

select throws_ok('select * from public.daily_metrics', '42501', null,
  'a signed-out visitor cannot read daily_metrics at all');
select throws_ok('select * from public.profiles', '42501', null,
  'a signed-out visitor cannot read profiles at all');

select * from finish();
rollback;

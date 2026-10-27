-- V1 schema: friends comparing Fitbit Air "training camp" stats.
--
-- Principle: private by default. Row-level security (RLS) is on for every
-- table. Someone else's data is readable only through private.can_view():
-- you share a group, the owner shares that category (recovery | sleep |
-- activity) with that group, and the day isn't hidden.
-- supabase/tests/*.test.sql prove these rules.
--
-- Conventions:
--   * Policies are `to authenticated`; signed-out visitors get no table privileges.
--   * `(select auth.uid())` is evaluated once per query instead of once per row.
--   * Helper functions live in the `private` schema, which the API doesn't expose.
--   * Only daily summaries are stored here; raw health data stays on the phone.

create schema private;
grant usage on schema private to authenticated;

-- ===========================================================================
-- Tables
-- ===========================================================================

-- What group-mates may see about you. Created at sign-up from your Google profile.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 40),
  avatar_url text check (char_length(avatar_url) <= 500),
  timezone text not null default 'UTC' check (char_length(timezone) <= 64),
  device_name text check (char_length(device_name) <= 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Only you can see these.
create table public.profile_private (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  sleep_goal_minutes int not null default 450 check (sleep_goal_minutes between 240 and 720),
  step_goal int not null default 8000 check (step_goal between 1000 and 50000),
  units text not null default 'imperial' check (units in ('imperial', 'metric'))
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  -- 8 characters with no look-alikes (no 0/O/1/I). Set by create_group().
  invite_code text not null unique check (invite_code ~ '^[A-HJ-NP-Z2-9]{8}$'),
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_id_idx on public.group_members (user_id);

-- One row per (user, group, category). No row means "not shared".
create table public.sharing_settings (
  user_id uuid not null,
  group_id uuid not null,
  category text not null check (category in ('recovery', 'sleep', 'activity')),
  enabled boolean not null default false,
  hidden_dates date[] not null default '{}',
  primary key (user_id, group_id, category),
  -- Settings only exist for groups you belong to; leaving deletes them.
  foreign key (group_id, user_id) references public.group_members (group_id, user_id) on delete cascade
);

-- One row per metric per day, so RLS can hide individual categories.
create table public.daily_metrics (
  user_id uuid not null references public.profiles (id) on delete cascade,
  date date not null,
  metric text not null check (metric in (
    'recovery_score', 'hrv_ms', 'resting_hr',          -- recovery
    'sleep_score', 'sleep_minutes',                    -- sleep
    'effort_score', 'azm', 'steps', 'distance_m'       -- activity
  )),
  value numeric not null check (value >= 0),
  -- Small extras such as sleep stages. The size cap keeps raw samples out.
  detail jsonb not null default '{}' check (pg_column_size(detail) <= 2048),
  synced_at timestamptz not null default now(),
  primary key (user_id, date, metric)
);

-- A reaction on someone's day card, made inside one group and visible only there.
create table public.reactions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  day date not null,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  unique (group_id, author_id, owner_id, day, emoji)
);
create index reactions_owner_id_day_idx on public.reactions (owner_id, day);

-- ===========================================================================
-- Helper functions (security definer: they read tables the caller can't)
-- ===========================================================================

-- Which sharing category a metric belongs to.
create function private.metric_category(metric text)
returns text
language sql immutable set search_path = ''
as $$
  select case
    when metric in ('recovery_score', 'hrv_ms', 'resting_hr') then 'recovery'
    when metric in ('sleep_score', 'sleep_minutes') then 'sleep'
    else 'activity'
  end;
$$;

create function private.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.group_members where group_id = p_group_id and user_id = p_user_id);
$$;

create function private.is_group_owner(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members where group_id = p_group_id and user_id = p_user_id and role = 'owner'
  );
$$;

create function private.shares_group(p_user_a uuid, p_user_b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members a
    join public.group_members b on b.group_id = a.group_id
    where a.user_id = p_user_a and b.user_id = p_user_b
  );
$$;

-- Does `owner` share `category` with `group` on `day`? (category null = any category)
create function private.shared_in_group(owner uuid, group_id uuid, category text, day date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.sharing_settings s
    where s.user_id = shared_in_group.owner
      and s.group_id = shared_in_group.group_id
      and (shared_in_group.category is null or s.category = shared_in_group.category)
      and s.enabled
      and not (shared_in_group.day = any (s.hidden_dates))
  );
$$;

-- The one rule for reading someone else's data: true when the viewer is the
-- owner, or when they share a group in which the owner shares `category` and
-- `day` isn't hidden. Pass category = null to mean "any category".
create function private.can_view(viewer uuid, owner uuid, category text, day date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(viewer = owner, false) or exists (
    select 1
    from public.group_members viewer_membership
    join public.group_members owner_membership on owner_membership.group_id = viewer_membership.group_id
    where viewer_membership.user_id = can_view.viewer
      and owner_membership.user_id = can_view.owner
      and private.shared_in_group(can_view.owner, owner_membership.group_id, can_view.category, can_view.day)
  );
$$;

-- Random 8-character invite code from an alphabet without look-alikes.
create function private.new_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 characters
  code text;
begin
  loop
    code := '';
    for i in 1..8 loop
      -- 256 is a multiple of 32, so every character is equally likely.
      code := code || substr(alphabet, 1 + get_byte(extensions.gen_random_bytes(1), 0) % 32, 1);
    end loop;
    exit when not exists (select 1 from public.groups where invite_code = code);
  end loop;
  return code;
end;
$$;

-- Normalizes a typed code: "sq-uad 234" → "SQUAD234".
create function private.normalize_invite_code(code text)
returns text
language sql immutable set search_path = ''
as $$
  select upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'));
$$;

grant execute on all functions in schema private to authenticated;

-- ===========================================================================
-- Triggers
-- ===========================================================================

-- Every new user gets profile rows, prefilled from their Google account
-- (Supabase stores Google's name and picture in raw_user_meta_data).
create function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  full_name text := coalesce(meta ->> 'full_name', meta ->> 'name', '');
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    left(coalesce(nullif(meta ->> 'given_name', ''), split_part(full_name, ' ', 1)), 40),
    left(coalesce(meta ->> 'avatar_url', meta ->> 'picture'), 500)
  );
  insert into public.profile_private (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create function private.set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at := now(); return new; end; $$;

create function private.set_synced_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.synced_at := now(); return new; end; $$;

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger daily_metrics_set_synced_at before update on public.daily_metrics
  for each row execute function private.set_synced_at();

-- ===========================================================================
-- Row-level security
-- ===========================================================================

alter table public.profiles enable row level security;
alter table public.profile_private enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.sharing_settings enable row level security;
alter table public.daily_metrics enable row level security;
alter table public.reactions enable row level security;

-- Signed-out visitors get nothing. The Join screen uses public.preview_group().
revoke all on all tables in schema public from anon;

-- profiles: you and your group-mates can read; you can edit your own.
create policy "Read own and group-mates' profiles" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or private.shares_group((select auth.uid()), id));
create policy "Update own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke insert, update, delete on public.profiles from authenticated;
grant update (display_name, avatar_url, timezone, device_name) on public.profiles to authenticated;

-- profile_private: only you.
create policy "Read own private profile" on public.profile_private
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Update own private profile" on public.profile_private
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke insert, update, delete on public.profile_private from authenticated;
grant update (sleep_goal_minutes, step_goal, units) on public.profile_private to authenticated;

-- groups: members read; create and join through RPCs; the owner may rename or delete.
create policy "Members read their groups" on public.groups
  for select to authenticated using (private.is_group_member(id, (select auth.uid())));
create policy "Owners rename groups" on public.groups
  for update to authenticated
  using (private.is_group_owner(id, (select auth.uid())))
  with check (private.is_group_owner(id, (select auth.uid())));
create policy "Owners delete groups" on public.groups
  for delete to authenticated using (private.is_group_owner(id, (select auth.uid())));
revoke insert, update on public.groups from authenticated;
grant update (name) on public.groups to authenticated;

-- group_members: members see each other; joining only through RPCs; you may
-- leave, and an owner may remove members.
create policy "Members read their group's members" on public.group_members
  for select to authenticated using (private.is_group_member(group_id, (select auth.uid())));
create policy "Leave a group or remove a member as owner" on public.group_members
  for delete to authenticated
  using (user_id = (select auth.uid()) or private.is_group_owner(group_id, (select auth.uid())));
revoke insert, update on public.group_members from authenticated;

-- sharing_settings: only you.
create policy "Read own sharing settings" on public.sharing_settings
  for select to authenticated using (user_id = (select auth.uid()));
create policy "Create own sharing settings" on public.sharing_settings
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Update own sharing settings" on public.sharing_settings
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Delete own sharing settings" on public.sharing_settings
  for delete to authenticated using (user_id = (select auth.uid()));

-- daily_metrics: read through can_view(); write only your own.
create policy "Read metrics you are allowed to see" on public.daily_metrics
  for select to authenticated
  using (private.can_view((select auth.uid()), user_id, private.metric_category(metric), date));
create policy "Insert own metrics" on public.daily_metrics
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "Update own metrics" on public.daily_metrics
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Delete own metrics" on public.daily_metrics
  for delete to authenticated using (user_id = (select auth.uid()));

-- reactions: visible to members of the reaction's group who can see the card.
create policy "Read reactions in your groups on cards you can see" on public.reactions
  for select to authenticated
  using (
    private.is_group_member(group_id, (select auth.uid()))
    and (author_id = (select auth.uid()) or private.can_view((select auth.uid()), owner_id, null, day))
  );
create policy "React to cards you can see" on public.reactions
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and private.is_group_member(group_id, (select auth.uid()))
    and private.is_group_member(group_id, owner_id)
    and private.can_view((select auth.uid()), owner_id, null, day)
  );
create policy "Delete own reactions" on public.reactions
  for delete to authenticated using (author_id = (select auth.uid()));
revoke update on public.reactions from authenticated;

-- ===========================================================================
-- RPCs callable from the app
-- ===========================================================================

-- Creates a group with a fresh invite code and makes the caller its owner.
create function public.create_group(group_name text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  new_group public.groups;
begin
  if caller is null then
    raise exception 'Sign in to create a group' using errcode = '42501';
  end if;
  insert into public.groups (name, invite_code, created_by)
  values (btrim(group_name), private.new_invite_code(), caller)
  returning * into new_group;
  insert into public.group_members (group_id, user_id, role) values (new_group.id, caller, 'owner');
  return new_group;
end;
$$;

-- Joins the group with this invite code (typed or from a link). Joining twice is harmless.
create function public.join_group(code text)
returns public.groups
language plpgsql security definer set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  target public.groups;
begin
  if caller is null then
    raise exception 'Sign in to join a group' using errcode = '42501';
  end if;
  select * into target from public.groups where invite_code = private.normalize_invite_code(code);
  if not found then
    raise exception 'No group has that invite code' using errcode = 'P0002';
  end if;
  insert into public.group_members (group_id, user_id) values (target.id, caller) on conflict do nothing;
  return target;
end;
$$;

-- What the Join screen shows before someone joins (or signs in): the group name
-- plus each member's display name and photo. Nothing else, and nothing at all
-- for an unknown code. This is the only exception to "non-members see nothing".
create function public.preview_group(code text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'name', g.name,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object('display_name', p.display_name, 'avatar_url', p.avatar_url)
                       order by m.joined_at)
      from public.group_members m join public.profiles p on p.id = m.user_id
      where m.group_id = g.id
    ), '[]'::jsonb)
  )
  from public.groups g
  where g.invite_code = private.normalize_invite_code(code);
$$;

-- This week's group challenge, rotating weekly. The app computes the same
-- rotation in Challenges.group(for:) from ((week_start - 2024-01-01) / 7) % 4.
create function public.group_challenge(week_start date)
returns text
language sql immutable set search_path = ''
as $$
  select (array['steps', 'azm', 'long_nights', 'avg_sleep'])[
    1 + ((((week_start - date '2024-01-01') / 7) % 4) + 4) % 4
  ];
$$;

-- A group's weekly leaderboard for one metric. Runs with the caller's own
-- permissions (security invoker), so RLS applies; on top of that, only data the
-- member shares with THIS group counts. Recovery, HRV, and resting HR can never
-- be ranked: any other metric name returns nothing.
create function public.weekly_leaderboard(p_group_id uuid, week_start date, metric text)
returns table (user_id uuid, display_name text, avatar_url text, value numeric, rank bigint)
language sql stable security invoker set search_path = ''
as $$
  with wanted as (
    -- The only rankable metrics. Anything else (recovery, HRV, resting HR) maps to null.
    select case weekly_leaderboard.metric
      when 'effort' then 'effort_score'
      when 'steps' then 'steps'
      when 'azm' then 'azm'
      when 'avg_sleep' then 'sleep_minutes'
      when 'long_nights' then 'sleep_minutes'
    end as metric_name
  ),
  source as (
    select d.user_id, d.value
    from public.daily_metrics d
    cross join wanted w
    where d.metric = w.metric_name
      and d.date >= weekly_leaderboard.week_start
      and d.date < weekly_leaderboard.week_start + 7
      and private.is_group_member(p_group_id, (select auth.uid()))
      and private.is_group_member(p_group_id, d.user_id)
      and private.shared_in_group(d.user_id, p_group_id, private.metric_category(d.metric), d.date)
  ),
  totals as (
    select s.user_id,
      (case weekly_leaderboard.metric
        when 'avg_sleep' then avg(s.value)
        when 'long_nights' then count(*) filter (where s.value >= 420)
        else sum(s.value)
      end)::numeric as total
    from source s
    group by s.user_id
  )
  select t.user_id, p.display_name, p.avatar_url, round(t.total, 1) as value,
         rank() over (order by t.total desc) as rank
  from totals t
  join public.profiles p on p.id = t.user_id
  order by rank, p.display_name;
$$;

-- Deletes your account and everything in it (App Store requirement).
create function public.delete_my_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  delete from auth.users where id = caller;  -- cascades to profiles and all their rows
  delete from public.groups g where not exists (select 1 from public.group_members m where m.group_id = g.id);
end;
$$;

revoke execute on function public.create_group(text) from public, anon;
revoke execute on function public.join_group(text) from public, anon;
revoke execute on function public.delete_my_account() from public, anon;
revoke execute on function public.weekly_leaderboard(uuid, date, text) from public, anon;
revoke execute on function public.preview_group(text) from public;
grant execute on function public.create_group(text) to authenticated;
grant execute on function public.join_group(text) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
grant execute on function public.weekly_leaderboard(uuid, date, text) to authenticated;
grant execute on function public.preview_group(text) to anon, authenticated;
grant execute on function public.group_challenge(date) to anon, authenticated;

-- ===========================================================================
-- Storage: optional custom profile photos (Google's photo is the default)
-- ===========================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg']);

create policy "Read own avatar files" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Upload own avatar files" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Update own avatar files" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Delete own avatar files" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

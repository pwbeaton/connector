-- Initial schema.
--
-- Principle: private by default. Row-level security (RLS) is on for every
-- table. A user may read another user's data only when private.can_view()
-- says so: they share a group, the owner shares that metric with that group,
-- and the day isn't hidden. supabase/tests/*.test.sql prove these rules.
--
-- Conventions:
--   * Policies are always `to authenticated`; signed-out (anon) users get no
--     table privileges at all.
--   * `(select auth.uid())` is used instead of `auth.uid()` so Postgres
--     evaluates it once per query instead of once per row.
--   * Helper functions live in the `private` schema, which the API doesn't
--     expose, so the app can't call them to probe other people's settings.

-- ===========================================================================
-- Private schema and helper functions
-- ===========================================================================

create schema private;
grant usage on schema private to authenticated;

-- ===========================================================================
-- Tables
-- ===========================================================================

-- What group-mates may see about you. Created automatically at sign-up.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '' check (char_length(display_name) <= 40),
  avatar_url text check (char_length(avatar_url) <= 500),
  timezone text not null default 'UTC' check (char_length(timezone) <= 64),
  devices text[] not null default '{}' check (
    devices <@ array['apple_watch', 'whoop', 'oura', 'fitbit', 'garmin', 'other', 'iphone']
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Only you can see these. Created automatically at sign-up.
create table public.profile_private (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  birth_year int check (birth_year between 1900 and 2100),
  max_hr_override int check (max_hr_override between 100 and 240),
  preferred_sleep_source text check (char_length(preferred_sleep_source) <= 100)
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

-- One row per (user, group, metric). No row means "not shared".
create table public.sharing_settings (
  user_id uuid not null,
  group_id uuid not null,
  metric text not null check (
    metric in ('sleep', 'resting_hr', 'hrv', 'steps', 'active_minutes', 'effort', 'workouts', 'vendor_score')
  ),
  enabled boolean not null default false,
  hidden_dates date[] not null default '{}',
  primary key (user_id, group_id, metric),
  -- You can only have settings for a group you belong to; leaving deletes them.
  foreign key (group_id, user_id) references public.group_members (group_id, user_id) on delete cascade
);

-- One row per metric per day per source, so RLS can hide individual metrics.
create table public.daily_metrics (
  user_id uuid not null references public.profiles (id) on delete cascade,
  date date not null,
  metric text not null check (
    metric in ('sleep', 'resting_hr', 'hrv', 'steps', 'active_minutes', 'effort', 'vendor_score')
  ),
  source text not null check (source in ('apple_health', 'whoop_api', 'oura_api')),
  value numeric check (value >= 0),
  -- Small extras such as sleep stages and naps. The size cap keeps raw samples out.
  detail jsonb not null default '{}' check (pg_column_size(detail) <= 4096),
  synced_at timestamptz not null default now(),
  primary key (user_id, date, metric, source)
);

create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  source text not null check (source in ('apple_health', 'whoop_api', 'oura_api')),
  source_id text not null check (char_length(source_id) <= 100),
  -- The owner's local date for the workout; lets hidden dates apply to workouts.
  local_date date not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  type text not null check (char_length(type) <= 64),
  avg_hr int check (avg_hr between 20 and 250),
  zone_minutes int[] check (cardinality(zone_minutes) = 5 and 0 <= all (zone_minutes)),
  effort int check (effort >= 0),
  synced_at timestamptz not null default now(),
  unique (source, source_id),
  check (end_at >= start_at)
);
create index workouts_user_id_local_date_idx on public.workouts (user_id, local_date);

-- A reaction or comment on someone's day card or workout, made inside one group
-- and visible only to that group.
create table public.reactions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('day', 'workout')),
  day date not null,
  workout_id uuid references public.workouts (id) on delete cascade,
  emoji text check (char_length(emoji) <= 16),
  comment text check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  check ((target_type = 'workout') = (workout_id is not null)),
  check (emoji is not null or comment is not null)
);
create index reactions_owner_id_day_idx on public.reactions (owner_id, day);

-- One row per device token; a person can have several devices.
create table public.push_tokens (
  apns_token text primary key check (char_length(apns_token) <= 200),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  updated_at timestamptz not null default now()
);

-- Phase 6. Written only by Edge Functions (service role). The app may read its
-- own status, never the tokens.
create table public.vendor_connections (
  user_id uuid not null references public.profiles (id) on delete cascade,
  provider text not null check (provider in ('whoop', 'oura')),
  status text not null default 'active' check (status in ('active', 'needs_reconnect', 'capped')),
  encrypted_tokens text,
  provider_user_id text,
  last_synced_at timestamptz,
  primary key (user_id, provider)
);

-- ===========================================================================
-- Helper functions (security definer: they read tables the caller can't)
-- ===========================================================================

create function private.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = p_user_id
  );
$$;

create function private.is_group_owner(p_group_id uuid, p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = p_user_id and role = 'owner'
  );
$$;

create function private.shares_group(p_user_a uuid, p_user_b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members a
    join public.group_members b on b.group_id = a.group_id
    where a.user_id = p_user_a and b.user_id = p_user_b
  );
$$;

-- The one rule for reading someone else's data. True when the viewer is the
-- owner, or when they share a group in which the owner has `metric` switched
-- on and `day` isn't hidden. Pass metric = null to mean "any metric" (used for
-- reactions on a whole day card).
create function private.can_view(viewer uuid, owner uuid, metric text, day date)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(viewer = owner, false) or exists (
    select 1
    from public.group_members viewer_membership
    join public.group_members owner_membership
      on owner_membership.group_id = viewer_membership.group_id
    join public.sharing_settings setting
      on setting.group_id = owner_membership.group_id
     and setting.user_id = owner_membership.user_id
    where viewer_membership.user_id = can_view.viewer
      and owner_membership.user_id = can_view.owner
      and (can_view.metric is null or setting.metric = can_view.metric)
      and setting.enabled
      and not (can_view.day = any (setting.hidden_dates))
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

-- Every new auth user gets a profile and a private profile row.
create function private.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  insert into public.profile_private (user_id) values (new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

create function private.set_updated_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create function private.set_synced_at()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  new.synced_at := now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function private.set_updated_at();
create trigger push_tokens_set_updated_at before update on public.push_tokens
  for each row execute function private.set_updated_at();
create trigger daily_metrics_set_synced_at before update on public.daily_metrics
  for each row execute function private.set_synced_at();
create trigger workouts_set_synced_at before update on public.workouts
  for each row execute function private.set_synced_at();

-- ===========================================================================
-- View: one source per metric per day
-- ===========================================================================

-- security_invoker makes the view run with the caller's permissions, so the
-- daily_metrics RLS policy still decides what each person sees.
create view public.daily_resolved
with (security_invoker = true)
as
select distinct on (user_id, date, metric)
  user_id, date, metric, source, value, detail, synced_at
from public.daily_metrics
order by
  user_id, date, metric,
  -- Vendor API rows (Phase 6) win over Apple Health for the metrics they provide.
  case when source = 'apple_health' then 1 else 0 end,
  source;

-- ===========================================================================
-- Row-level security
-- ===========================================================================

alter table public.profiles enable row level security;
alter table public.profile_private enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.sharing_settings enable row level security;
alter table public.daily_metrics enable row level security;
alter table public.workouts enable row level security;
alter table public.reactions enable row level security;
alter table public.push_tokens enable row level security;
alter table public.vendor_connections enable row level security;

-- Signed-out users get nothing from any table or view. The Join screen uses
-- public.preview_group() instead.
revoke all on all tables in schema public from anon;

-- profiles: you and your group-mates can read; you can edit your own.
create policy "Read own and group-mates' profiles" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or private.shares_group((select auth.uid()), id));
create policy "Update own profile" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));
revoke insert, update, delete on public.profiles from authenticated;
grant update (display_name, avatar_url, timezone, devices) on public.profiles to authenticated;

-- profile_private: only you.
create policy "Read own private profile" on public.profile_private
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Update own private profile" on public.profile_private
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
revoke insert, update, delete on public.profile_private from authenticated;
grant update (birth_year, max_hr_override, preferred_sleep_source) on public.profile_private to authenticated;

-- groups: members can read; created through create_group(); the owner may
-- rename or delete.
create policy "Members read their groups" on public.groups
  for select to authenticated
  using (private.is_group_member(id, (select auth.uid())));
create policy "Owners rename groups" on public.groups
  for update to authenticated
  using (private.is_group_owner(id, (select auth.uid())))
  with check (private.is_group_owner(id, (select auth.uid())));
create policy "Owners delete groups" on public.groups
  for delete to authenticated
  using (private.is_group_owner(id, (select auth.uid())));
revoke insert, update on public.groups from authenticated;
grant update (name) on public.groups to authenticated;

-- group_members: members see each other; joining happens only through RPCs;
-- you may leave, and an owner may remove members.
create policy "Members read their group's members" on public.group_members
  for select to authenticated
  using (private.is_group_member(group_id, (select auth.uid())));
create policy "Leave a group or remove a member as owner" on public.group_members
  for delete to authenticated
  using (user_id = (select auth.uid()) or private.is_group_owner(group_id, (select auth.uid())));
revoke insert, update on public.group_members from authenticated;

-- sharing_settings: only you.
create policy "Read own sharing settings" on public.sharing_settings
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Create own sharing settings" on public.sharing_settings
  for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Update own sharing settings" on public.sharing_settings
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Delete own sharing settings" on public.sharing_settings
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- daily_metrics: read through can_view(); write only your own Apple Health rows
-- (vendor rows come from Edge Functions in Phase 6).
create policy "Read metrics you are allowed to see" on public.daily_metrics
  for select to authenticated
  using (private.can_view((select auth.uid()), user_id, metric, date));
create policy "Insert own Apple Health metrics" on public.daily_metrics
  for insert to authenticated
  with check (user_id = (select auth.uid()) and source = 'apple_health');
create policy "Update own Apple Health metrics" on public.daily_metrics
  for update to authenticated
  using (user_id = (select auth.uid()) and source = 'apple_health')
  with check (user_id = (select auth.uid()) and source = 'apple_health');
create policy "Delete own Apple Health metrics" on public.daily_metrics
  for delete to authenticated
  using (user_id = (select auth.uid()) and source = 'apple_health');

-- workouts: same rules, under the "workouts" sharing key.
create policy "Read workouts you are allowed to see" on public.workouts
  for select to authenticated
  using (private.can_view((select auth.uid()), user_id, 'workouts', local_date));
create policy "Insert own Apple Health workouts" on public.workouts
  for insert to authenticated
  with check (user_id = (select auth.uid()) and source = 'apple_health');
create policy "Update own Apple Health workouts" on public.workouts
  for update to authenticated
  using (user_id = (select auth.uid()) and source = 'apple_health')
  with check (user_id = (select auth.uid()) and source = 'apple_health');
create policy "Delete own Apple Health workouts" on public.workouts
  for delete to authenticated
  using (user_id = (select auth.uid()) and source = 'apple_health');

-- reactions: visible to members of the reaction's group who can see the card.
create policy "Read reactions in your groups on cards you can see" on public.reactions
  for select to authenticated
  using (
    private.is_group_member(group_id, (select auth.uid()))
    and (
      author_id = (select auth.uid())
      or private.can_view(
        (select auth.uid()), owner_id,
        case when target_type = 'workout' then 'workouts' end,
        day
      )
    )
  );
create policy "React to cards you can see" on public.reactions
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and private.is_group_member(group_id, (select auth.uid()))
    and private.is_group_member(group_id, owner_id)
    and private.can_view(
      (select auth.uid()), owner_id,
      case when target_type = 'workout' then 'workouts' end,
      day
    )
    and (
      workout_id is null
      or exists (
        select 1 from public.workouts w
        where w.id = workout_id and w.user_id = owner_id and w.local_date = day
      )
    )
  );
create policy "Delete own reactions" on public.reactions
  for delete to authenticated
  using (author_id = (select auth.uid()));
revoke update on public.reactions from authenticated;

-- push_tokens: only you.
create policy "Read own push tokens" on public.push_tokens
  for select to authenticated
  using (user_id = (select auth.uid()));
create policy "Add own push tokens" on public.push_tokens
  for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "Update own push tokens" on public.push_tokens
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "Delete own push tokens" on public.push_tokens
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- vendor_connections: read your own status; the token column is never readable.
create policy "Read own vendor connections" on public.vendor_connections
  for select to authenticated
  using (user_id = (select auth.uid()));
revoke all on public.vendor_connections from authenticated;
grant select (user_id, provider, status, provider_user_id, last_synced_at)
  on public.vendor_connections to authenticated;

-- ===========================================================================
-- RPCs callable from the app (the only security-definer functions in public)
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

  insert into public.group_members (group_id, user_id, role)
  values (new_group.id, caller, 'owner');

  return new_group;
end;
$$;
revoke execute on function public.create_group(text) from public, anon;
grant execute on function public.create_group(text) to authenticated;

-- What the Join screen shows before someone joins (or even signs in): the
-- group name plus each member's display name and photo. Nothing else, and
-- nothing at all for an unknown code. This is the only exception to
-- "non-members see nothing".
create function public.preview_group(code text)
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'name', g.name,
    'members', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object('display_name', p.display_name, 'avatar_url', p.avatar_url)
          order by m.joined_at
        )
        from public.group_members m
        join public.profiles p on p.id = m.user_id
        where m.group_id = g.id
      ),
      '[]'::jsonb
    )
  )
  from public.groups g
  where g.invite_code = private.normalize_invite_code(code);
$$;
revoke execute on function public.preview_group(text) from public;
grant execute on function public.preview_group(text) to anon, authenticated;

-- ===========================================================================
-- Storage: profile photos
-- ===========================================================================

-- Public bucket: photos load by URL without signing (the Join screen shows them
-- before sign-in). File names are random, and health data is never stored here.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/jpeg']);

-- You may only manage files inside a folder named after your user ID.
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

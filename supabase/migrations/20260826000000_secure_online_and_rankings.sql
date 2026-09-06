-- Secure online-table admission, trusted Realtime envelopes, and leaderboard
-- write validation. Apply after 20260825000000_weekly_rankings.sql.
--
-- This replaces the abandoned 20260714000000_initial_online_foundation.sql
-- prototype. Do not recreate its unauthenticated public tables or policies.

-- `create table if not exists` does not update a pre-existing CHECK. Repair
-- the original int4 multiplication explicitly so 1,000,000 hands is valid.
alter table public.weekly_rankings
  drop constraint if exists weekly_rankings_plausible;

alter table public.weekly_rankings
  add constraint weekly_rankings_plausible check (
    hands_played >= 0
    and hands_played <= 1000000
    and abs(profit::bigint) <= greatest(hands_played, 1)::bigint * 10000
    and char_length(display_name) between 1 and 12
    and week_key ~ '^W[0-9]{1,6}$'
  );

-- Score writes go through one server-side function. Direct REST upserts are
-- revoked, so a caller cannot overwrite a row or skip the monotonicity and
-- current-week checks below.
create or replace function public.submit_weekly_ranking(
  p_week_key text,
  p_display_name text,
  p_profit integer,
  p_hands_played integer
)
returns public.weekly_rankings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_expected_week text := 'W' || ((current_date - date '2024-01-01') / 7)::text;
  v_previous public.weekly_rankings;
  v_result public.weekly_rankings;
  v_name text := btrim(p_display_name);
begin
  if v_user_id is null then
    raise exception 'Sign in is required to submit a weekly score'
      using errcode = '42501';
  end if;
  if p_week_key is distinct from v_expected_week then
    raise exception 'Scores may only be submitted for the current week'
      using errcode = '22023';
  end if;
  if char_length(v_name) not between 1 and 12 then
    raise exception 'Display names must be 1 to 12 characters'
      using errcode = '22023';
  end if;
  if p_hands_played < 0 or p_hands_played > 1000000 then
    raise exception 'Hands played is outside the accepted range'
      using errcode = '22023';
  end if;
  if abs(p_profit::bigint) > greatest(p_hands_played, 1)::bigint * 10000 then
    raise exception 'Profit is not plausible for the submitted hand count'
      using errcode = '22023';
  end if;

  select * into v_previous
  from public.weekly_rankings
  where player_id = v_user_id and week_key = p_week_key
  for update;

  if found then
    if p_hands_played < v_previous.hands_played then
      raise exception 'Hands played cannot move backwards'
        using errcode = '22023';
    end if;
    if abs(p_profit::bigint - v_previous.profit::bigint) >
        greatest(p_hands_played - v_previous.hands_played, 1)::bigint * 10000 then
      raise exception 'Profit change is not plausible for new hands'
        using errcode = '22023';
    end if;

    update public.weekly_rankings
    set display_name = v_name,
        profit = p_profit,
        hands_played = p_hands_played
    where player_id = v_user_id and week_key = p_week_key
    returning * into v_result;
  else
    insert into public.weekly_rankings (
      player_id, week_key, display_name, profit, hands_played
    ) values (
      v_user_id, p_week_key, v_name, p_profit, p_hands_played
    ) returning * into v_result;
  end if;

  -- The week key is an epoch-based integer. Keeping twelve weeks bounds the
  -- free-tier table without requiring pg_cron or a manual cleanup task.
  delete from public.weekly_rankings
  where week_key ~ '^W[0-9]{1,6}$'
    and substring(week_key from 2)::integer <
        ((current_date - date '2024-01-01') / 7)::integer - 12;

  return v_result;
end;
$$;

revoke insert, update, delete on public.weekly_rankings from anon, authenticated;
grant select on public.weekly_rankings to anon, authenticated;
grant execute on function public.submit_weekly_ranking(text, text, integer, integer)
  to authenticated;

-- An account must be admitted to a room before it can open that room's private
-- Realtime channel. The code is 10 characters from a 32-character alphabet:
-- an invite-only room has roughly 1.1 quadrillion possible codes.
create table if not exists public.online_rooms (
  room_code text primary key check (room_code ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  listed boolean not null default false,
  max_players smallint not null default 5 check (max_players between 2 and 5),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.online_room_members (
  room_code text not null references public.online_rooms(room_code) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 12),
  is_host boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_code, user_id)
);

create index if not exists online_room_members_user_idx
  on public.online_room_members(user_id);

alter table public.online_rooms enable row level security;
alter table public.online_room_members enable row level security;

create or replace function public.prune_stale_online_rooms()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- A room is only a live Realtime coordination record. Expire it after a day
  -- so abandoned invite codes and memberships cannot grow the free-tier DB.
  delete from public.online_rooms
  where created_at < now() - interval '1 day';
  return new;
end;
$$;

drop trigger if exists online_rooms_prune_stale on public.online_rooms;
create trigger online_rooms_prune_stale
  before insert on public.online_rooms
  for each statement execute function public.prune_stale_online_rooms();

-- Membership is intentionally not exposed to clients. This narrow policy is
-- enough for Realtime authorization to evaluate a caller's own membership.
drop policy if exists "Online members can read themselves" on public.online_room_members;
create policy "Online members can read themselves"
  on public.online_room_members for select to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.online_room_topic(p_room_code text)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'bj_room_' || p_room_code;
$$;

create or replace function public.create_online_room(
  p_room_code text,
  p_display_name text,
  p_listed boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(btrim(p_room_code));
  v_name text := btrim(p_display_name);
begin
  if v_user_id is null then
    raise exception 'Sign in is required to create a table' using errcode = '42501';
  end if;
  if v_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$' then
    raise exception 'Invalid room code' using errcode = '22023';
  end if;
  if char_length(v_name) not between 1 and 12 then
    raise exception 'Display names must be 1 to 12 characters' using errcode = '22023';
  end if;

  insert into public.online_rooms (room_code, host_id, listed)
  values (v_code, v_user_id, coalesce(p_listed, false));
  insert into public.online_room_members (room_code, user_id, display_name, is_host)
  values (v_code, v_user_id, v_name, true);
end;
$$;

create or replace function public.join_online_room(
  p_room_code text,
  p_display_name text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(btrim(p_room_code));
  v_name text := btrim(p_display_name);
  v_room public.online_rooms;
  v_member_count integer;
begin
  if v_user_id is null then
    raise exception 'Sign in is required to join a table' using errcode = '42501';
  end if;
  if v_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$' then
    raise exception 'Invalid room code' using errcode = '22023';
  end if;
  if char_length(v_name) not between 1 and 12 then
    raise exception 'Display names must be 1 to 12 characters' using errcode = '22023';
  end if;

  select * into v_room
  from public.online_rooms
  where room_code = v_code and closed_at is null
  for update;
  if not found then
    raise exception 'This table is unavailable' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.online_room_members
    where room_code = v_code and user_id = v_user_id
  ) then
    select count(*) into v_member_count
    from public.online_room_members where room_code = v_code;
    if v_member_count >= v_room.max_players then
      raise exception 'This table is full' using errcode = 'P0001';
    end if;
  end if;

  insert into public.online_room_members (room_code, user_id, display_name, is_host)
  values (v_code, v_user_id, v_name, v_user_id = v_room.host_id)
  on conflict (room_code, user_id) do update
    set display_name = excluded.display_name,
        joined_at = now();

  perform realtime.send(
    jsonb_build_object('kind', 'memberJoined', 'from', v_user_id::text,
      'data', jsonb_build_object('name', v_name)),
    'msg', public.online_room_topic(v_code), true
  );
end;
$$;

-- Client Broadcast is never permitted. This RPC validates the caller's room
-- role, stamps their identity itself, then emits a private database broadcast.
create or replace function public.online_send_message(
  p_room_code text,
  p_kind text,
  p_data jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(btrim(p_room_code));
  v_host_id uuid;
  v_action text;
begin
  if v_user_id is null then
    raise exception 'Sign in is required to send a game message' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.online_room_members
    where room_code = v_code and user_id = v_user_id
  ) then
    raise exception 'You are not a member of this table' using errcode = '42501';
  end if;
  if octet_length(coalesce(p_data, '{}'::jsonb)::text) > 65536 then
    raise exception 'Game message is too large' using errcode = '22023';
  end if;

  select host_id into v_host_id from public.online_rooms
  where room_code = v_code and closed_at is null;
  if not found then
    raise exception 'This table is unavailable' using errcode = 'P0002';
  end if;

  if p_kind = 'state' then
    if v_user_id <> v_host_id then
      raise exception 'Only the host may publish table state' using errcode = '42501';
    end if;
  elsif p_kind = 'intent' then
    v_action := p_data ->> 'action';
    if v_action not in (
      'bet', 'clearBet', 'ready', 'unready', 'rebuy', 'hit', 'stand',
      'double', 'split', 'insure', 'declineInsurance'
    ) then
      raise exception 'Invalid game action' using errcode = '22023';
    end if;
  elsif p_kind <> 'requestState' then
    raise exception 'Invalid game message' using errcode = '22023';
  end if;

  perform realtime.send(
    jsonb_build_object('kind', p_kind, 'from', v_user_id::text,
      'data', coalesce(p_data, '{}'::jsonb)),
    'msg', public.online_room_topic(v_code), true
  );
end;
$$;

-- Realtime evaluates these at private-channel subscribe time. The lobby is
-- discoverable to any authenticated player; room traffic requires membership.
create or replace function public.can_access_online_topic(p_topic text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_topic = 'bj_room_LOBBY'
    or exists (
      select 1 from public.online_room_members
      where room_code = replace(p_topic, 'bj_room_', '')
        and user_id = (select auth.uid())
    );
$$;

revoke all on public.online_rooms, public.online_room_members from anon, authenticated;
grant execute on function public.create_online_room(text, text, boolean) to authenticated;
grant execute on function public.join_online_room(text, text) to authenticated;
grant execute on function public.online_send_message(text, text, jsonb) to authenticated;
grant execute on function public.can_access_online_topic(text) to authenticated;

drop policy if exists "Hi-Lo online read private traffic" on realtime.messages;
create policy "Hi-Lo online read private traffic"
  on realtime.messages for select to authenticated
  using (
    realtime.messages.extension in ('broadcast', 'presence')
    and public.can_access_online_topic((select realtime.topic()))
  );

drop policy if exists "Hi-Lo online publish presence" on realtime.messages;
create policy "Hi-Lo online publish presence"
  on realtime.messages for insert to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and public.can_access_online_topic((select realtime.topic()))
  );

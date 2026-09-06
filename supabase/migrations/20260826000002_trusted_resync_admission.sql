-- Make the post-subscription resync handshake a trusted room-admission path.
-- A guest sends requestState only after its private Realtime channel is ready.
-- The database replaces any client payload with the approved member name, so
-- the host can safely seat the server-stamped sender if the earlier
-- memberJoined broadcast occurred during socket setup.

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
  v_display_name text;
begin
  if v_user_id is null then
    raise exception 'Sign in is required to send a game message' using errcode = '42501';
  end if;
  select display_name into v_display_name
  from public.online_room_members
  where room_code = v_code and user_id = v_user_id;
  if not found then
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
  elsif p_kind = 'requestState' then
    p_data := jsonb_build_object('name', v_display_name);
  else
    raise exception 'Invalid game message' using errcode = '22023';
  end if;

  perform realtime.send(
    jsonb_build_object('kind', p_kind, 'from', v_user_id::text,
      'data', coalesce(p_data, '{}'::jsonb)),
    'msg', public.online_room_topic(v_code), true
  );
end;
$$;

-- Weekly accuracy league: rank players by how often their decisions matched
-- the coach, alongside the existing profit board. Apply after
-- 20260826000000_secure_online_and_rankings.sql.
--
-- Safe to apply while older app versions are live: the original
-- submit_weekly_ranking(text, text, integer, integer) is left exactly as it
-- is, new columns default to zero, and only app 1.2.0+ calls the new
-- submit_weekly_ranking_v2. Until this is applied the app keeps using the
-- original function and shows the accuracy board as "being set up".

alter table public.weekly_rankings
  add column if not exists decisions integer not null default 0,
  add column if not exists correct_decisions integer not null default 0;

alter table public.weekly_rankings
  drop constraint if exists weekly_rankings_accuracy_plausible;

alter table public.weekly_rankings
  add constraint weekly_rankings_accuracy_plausible check (
    decisions >= 0
    and decisions <= 1000000
    and correct_decisions >= 0
    and correct_decisions <= decisions
  );

-- Accuracy in basis points (9650 = 96.50%), stored so the board can be
-- ordered and filtered by it through the REST API.
alter table public.weekly_rankings
  add column if not exists accuracy_bp integer
  generated always as (
    case when decisions > 0
      then (correct_decisions::bigint * 10000 / decisions)::integer
      else 0
    end
  ) stored;

create index if not exists weekly_rankings_accuracy_idx
  on public.weekly_rankings (week_key, accuracy_bp desc, decisions desc);

-- The v1 checks (sign-in, current week, name, plausible profit, monotonic
-- hands) run first by calling v1 itself, so the two can never disagree; then
-- the decision counts are validated and stored.
create or replace function public.submit_weekly_ranking_v2(
  p_week_key text,
  p_display_name text,
  p_profit integer,
  p_hands_played integer,
  p_decisions integer,
  p_correct_decisions integer
)
returns public.weekly_rankings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_previous public.weekly_rankings;
  v_result public.weekly_rankings;
begin
  if p_decisions is null or p_correct_decisions is null
      or p_decisions < 0 or p_decisions > 1000000
      or p_correct_decisions < 0 or p_correct_decisions > p_decisions then
    raise exception 'Decision counts are outside the accepted range'
      using errcode = '22023';
  end if;
  if v_user_id is null then
    raise exception 'Sign in is required to submit a weekly score'
      using errcode = '42501';
  end if;
  -- A round is a handful of decisions even when splitting three spots four
  -- ways; forty per counted hand is far past anything real play produces.
  if p_decisions::bigint > greatest(p_hands_played, 1)::bigint * 40 then
    raise exception 'Decision count is not plausible for the hands played'
      using errcode = '22023';
  end if;

  -- A score is normally posted by one device, but a retry and a background
  -- refresh can overlap. Serialize v2 calls for this player/week before
  -- reading the previous decision counts, otherwise two requests could both
  -- see an old row and the later one could move a count backwards.
  perform pg_advisory_xact_lock(hashtextextended(
    v_user_id::text || ':' || coalesce(p_week_key, ''), 0
  ));

  select * into v_previous
  from public.weekly_rankings
  where player_id = v_user_id and week_key = p_week_key
  for update;

  if found and (p_decisions < v_previous.decisions
      or p_correct_decisions < v_previous.correct_decisions) then
    raise exception 'Decision counts cannot move backwards'
      using errcode = '22023';
  end if;

  perform public.submit_weekly_ranking(
    p_week_key, p_display_name, p_profit, p_hands_played
  );

  update public.weekly_rankings
  set decisions = p_decisions,
      correct_decisions = p_correct_decisions
  where player_id = v_user_id and week_key = p_week_key
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.submit_weekly_ranking_v2(
  text, text, integer, integer, integer, integer
) from public, anon;
grant execute on function public.submit_weekly_ranking_v2(
  text, text, integer, integer, integer, integer
) to authenticated;

-- The original RPC is still called by older app versions. The earlier
-- migration granted authenticated access but did not remove Postgres's default
-- PUBLIC execute grant, so close that unnecessary route here as well.
revoke all on function public.submit_weekly_ranking(text, text, integer, integer)
  from public, anon;
grant execute on function public.submit_weekly_ranking(text, text, integer, integer)
  to authenticated;

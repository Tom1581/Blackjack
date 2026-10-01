-- Shared Hi-Lo Training leaderboards.
--
-- Daily Challenge accepts exactly one official attempt per player/day.
-- Survival retains each player's highest scoring run for the week. Both
-- leaderboards are public to read, but writes are available only through the
-- narrowly validated RPCs below.

create table if not exists public.hilo_daily_scores (
  player_id uuid not null references auth.users(id) on delete cascade,
  day integer not null,
  display_name text not null,
  score integer not null,
  correct integer not null,
  answered integer not null,
  best_streak integer not null,
  submitted_at timestamptz not null default now(),
  primary key (player_id, day)
);

alter table public.hilo_daily_scores
  drop constraint if exists hilo_daily_scores_plausible;

alter table public.hilo_daily_scores
  add constraint hilo_daily_scores_plausible check (
    day >= 1
    and display_name = btrim(display_name)
    and char_length(display_name) between 1 and 12
    and answered between 0 and 10
    and correct between 0 and answered
    and best_streak between 0 and correct
    and score::bigint between correct::bigint * 100 and correct::bigint * 800
  );

create index if not exists hilo_daily_scores_board_idx
  on public.hilo_daily_scores (day, score desc, submitted_at asc);

alter table public.hilo_daily_scores enable row level security;

drop policy if exists "Hi-Lo daily scores are readable" on public.hilo_daily_scores;
create policy "Hi-Lo daily scores are readable"
  on public.hilo_daily_scores for select
  using (true);

revoke insert, update, delete on public.hilo_daily_scores from public, anon, authenticated;
grant select on public.hilo_daily_scores to anon, authenticated;

create or replace function public.submit_hilo_daily(
  p_day integer,
  p_display_name text,
  p_score integer,
  p_correct integer,
  p_answered integer,
  p_best_streak integer
)
returns public.hilo_daily_scores
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_name text := btrim(p_display_name);
  v_today integer := current_date - date '2026-09-28';
  v_result public.hilo_daily_scores;
begin
  if v_user_id is null then
    raise exception 'Sign in is required to submit a daily score'
      using errcode = '42501';
  end if;

  -- The app uses a player's local date, while the server uses its own date.
  -- Accept the neighbouring day on either side for the midnight boundary.
  if p_day is null or p_day < 1
      or p_day < v_today - 1 or p_day > v_today + 1 then
    raise exception 'Daily scores may only be submitted for today'
      using errcode = '22023';
  end if;

  if v_name is null or char_length(v_name) < 1 or char_length(v_name) > 12
      or p_score is null or p_correct is null or p_answered is null
      or p_best_streak is null
      or p_answered < 0 or p_answered > 10
      or p_correct < 0 or p_correct > p_answered
      or p_best_streak < 0 or p_best_streak > p_correct
      or p_score::bigint < p_correct::bigint * 100
      or p_score::bigint > p_correct::bigint * 800 then
    raise exception 'Daily score is outside the accepted range'
      using errcode = '22023';
  end if;

  -- A unique key makes the first successful attempt final even if two client
  -- retries race. The following select returns that first stored row.
  insert into public.hilo_daily_scores (
    player_id, day, display_name, score, correct, answered, best_streak
  ) values (
    v_user_id, p_day, v_name, p_score, p_correct, p_answered, p_best_streak
  ) on conflict (player_id, day) do nothing;

  select * into v_result
  from public.hilo_daily_scores
  where player_id = v_user_id and day = p_day;

  if not found then
    raise exception 'Unable to store daily score' using errcode = 'P0001';
  end if;

  delete from public.hilo_daily_scores
  where day < v_today - 60;

  return v_result;
end;
$$;

revoke all on function public.submit_hilo_daily(
  integer, text, integer, integer, integer, integer
) from public, anon;
grant execute on function public.submit_hilo_daily(
  integer, text, integer, integer, integer, integer
) to authenticated;

create or replace function public.hilo_daily_standing(p_day integer)
returns table("rank" integer, players integer, score integer)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with mine as (
    select *
    from public.hilo_daily_scores
    where player_id = auth.uid() and day = p_day
  )
  select
    (
      1 + count(s.player_id) filter (
        where s.score > m.score
          or (
            s.score = m.score
            and (
              s.submitted_at < m.submitted_at
              or (
                s.submitted_at = m.submitted_at
                and s.player_id < m.player_id
              )
            )
          )
      )
    )::integer as "rank",
    count(s.player_id)::integer as players,
    m.score
  from mine m
  join public.hilo_daily_scores s on s.day = m.day
  group by m.player_id, m.score, m.submitted_at;
$$;

revoke all on function public.hilo_daily_standing(integer) from public, anon;
grant execute on function public.hilo_daily_standing(integer) to authenticated;

create table if not exists public.hilo_survival_scores (
  player_id uuid not null references auth.users(id) on delete cascade,
  week_key text not null,
  display_name text not null,
  score integer not null,
  correct integer not null,
  answered integer not null,
  level integer not null,
  submitted_at timestamptz not null default now(),
  primary key (player_id, week_key)
);

alter table public.hilo_survival_scores
  drop constraint if exists hilo_survival_scores_plausible;

alter table public.hilo_survival_scores
  add constraint hilo_survival_scores_plausible check (
    week_key ~ '^W[0-9]{1,6}$'
    and display_name = btrim(display_name)
    and char_length(display_name) between 1 and 12
    and correct between 0 and 1000
    and answered::bigint - correct::bigint between 0 and 3
    and level = 1 + correct / 5
    and score::bigint between correct::bigint * 100 and correct::bigint * 800
  );

create index if not exists hilo_survival_scores_board_idx
  on public.hilo_survival_scores (week_key, score desc, submitted_at asc);

alter table public.hilo_survival_scores enable row level security;

drop policy if exists "Hi-Lo survival scores are readable" on public.hilo_survival_scores;
create policy "Hi-Lo survival scores are readable"
  on public.hilo_survival_scores for select
  using (true);

revoke insert, update, delete on public.hilo_survival_scores from public, anon, authenticated;
grant select on public.hilo_survival_scores to anon, authenticated;

create or replace function public.submit_hilo_survival(
  p_week_key text,
  p_display_name text,
  p_score integer,
  p_correct integer,
  p_answered integer,
  p_level integer
)
returns public.hilo_survival_scores
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_name text := btrim(p_display_name);
  v_current_week integer := (current_date - date '2024-01-01') / 7;
  v_submitted_week integer;
  v_previous public.hilo_survival_scores;
  v_result public.hilo_survival_scores;
begin
  if v_user_id is null then
    raise exception 'Sign in is required to submit a Survival score'
      using errcode = '42501';
  end if;

  if p_week_key is null or p_week_key !~ '^W[0-9]{1,6}$' then
    raise exception 'Survival scores need a valid week key'
      using errcode = '22023';
  end if;

  v_submitted_week := substring(p_week_key from 2)::integer;
  if abs(v_submitted_week - v_current_week) > 1 then
    raise exception 'Survival scores may only be submitted for this week'
      using errcode = '22023';
  end if;

  if v_name is null or char_length(v_name) < 1 or char_length(v_name) > 12
      or p_score is null or p_correct is null or p_answered is null
      or p_level is null
      or p_correct < 0 or p_correct > 1000
      or p_answered::bigint - p_correct::bigint < 0
      or p_answered::bigint - p_correct::bigint > 3
      or p_level <> 1 + p_correct / 5
      or p_score::bigint < p_correct::bigint * 100
      or p_score::bigint > p_correct::bigint * 800 then
    raise exception 'Survival score is outside the accepted range'
      using errcode = '22023';
  end if;

  -- A retry and a completed game can overlap. Serialize them before reading
  -- the prior row so a lower score can never overwrite a higher one.
  perform pg_advisory_xact_lock(hashtextextended(
    v_user_id::text || ':' || p_week_key, 0
  ));

  select * into v_previous
  from public.hilo_survival_scores
  where player_id = v_user_id and week_key = p_week_key
  for update;

  if not found then
    insert into public.hilo_survival_scores (
      player_id, week_key, display_name, score, correct, answered, level
    ) values (
      v_user_id, p_week_key, v_name, p_score, p_correct, p_answered, p_level
    ) returning * into v_result;
  elsif p_score > v_previous.score then
    update public.hilo_survival_scores
    set display_name = v_name,
        score = p_score,
        correct = p_correct,
        answered = p_answered,
        level = p_level,
        submitted_at = now()
    where player_id = v_user_id and week_key = p_week_key
    returning * into v_result;
  else
    v_result := v_previous;
  end if;

  -- The table's own check guarantees valid week keys, but CASE keeps pruning
  -- safe even if a legacy row predates this migration's constraint.
  delete from public.hilo_survival_scores
  where case
    when week_key ~ '^W[0-9]{1,6}$'
      then substring(week_key from 2)::integer
    else null
  end < v_current_week - 12;

  return v_result;
end;
$$;

revoke all on function public.submit_hilo_survival(
  text, text, integer, integer, integer, integer
) from public, anon;
grant execute on function public.submit_hilo_survival(
  text, text, integer, integer, integer, integer
) to authenticated;

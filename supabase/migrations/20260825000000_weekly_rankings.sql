-- Real cross-device weekly rankings.
--
-- Apply this in the Supabase SQL Editor. Until it is applied the app falls
-- back to showing only your own weekly score, so nothing breaks — the board
-- just has nobody else on it.
--
-- Also enable Authentication -> Providers -> Anonymous sign-ins. Each device
-- signs in anonymously and gets a real user id, which is what the policies
-- below key on. Without it a player could overwrite anyone else's score.

create table if not exists public.weekly_rankings (
  player_id uuid not null references auth.users(id) on delete cascade,
  week_key text not null,
  display_name text not null,
  profit integer not null default 0,
  hands_played integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (player_id, week_key),

  -- Scores are written by the client, so the database refuses values that
  -- could not have come from actually playing. This does not stop a
  -- determined cheat inflating their own score within these bounds — only a
  -- server-side dealer can do that — but it does keep the board sane.
  constraint weekly_rankings_plausible check (
    hands_played >= 0
    and hands_played <= 1000000
    and abs(profit) <= greatest(hands_played, 1) * 10000
    and char_length(display_name) between 1 and 12
    and week_key ~ '^W[0-9]{1,6}$'
  )
);

-- The board is read as "this week, highest profit first".
create index if not exists weekly_rankings_board_idx
  on public.weekly_rankings (week_key, profit desc);

create or replace function public.touch_weekly_rankings()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists weekly_rankings_touch on public.weekly_rankings;
create trigger weekly_rankings_touch
  before insert or update on public.weekly_rankings
  for each row execute function public.touch_weekly_rankings();

alter table public.weekly_rankings enable row level security;

-- Anyone may read the board; that is the point of a leaderboard.
drop policy if exists "Weekly rankings are readable" on public.weekly_rankings;
create policy "Weekly rankings are readable"
  on public.weekly_rankings for select
  using (true);

-- You may only ever write your own row.
drop policy if exists "Players insert their own score" on public.weekly_rankings;
create policy "Players insert their own score"
  on public.weekly_rankings for insert
  with check (auth.uid() = player_id);

drop policy if exists "Players update their own score" on public.weekly_rankings;
create policy "Players update their own score"
  on public.weekly_rankings for update
  using (auth.uid() = player_id)
  with check (auth.uid() = player_id);

-- Old weeks are never read. Prune them whenever you like:
--   delete from public.weekly_rankings where week_key < 'W123';

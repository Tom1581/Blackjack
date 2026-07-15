-- Hi-Lo Blackjack Trainer online foundation.
-- Apply this in Supabase SQL Editor when you are ready to make the app online.
-- The app is currently connected with the publishable key; never put a service
-- role key in Flutter/mobile code.

create extension if not exists pgcrypto;

create table if not exists public.player_profiles (
  id uuid primary key default gen_random_uuid(),
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.weekly_scores (
  id uuid primary key default gen_random_uuid(),
  player_id uuid references public.player_profiles(id) on delete cascade,
  week_key text not null,
  profit integer not null default 0,
  hands_played integer not null default 0,
  updated_at timestamptz not null default now(),
  unique (player_id, week_key)
);

create table if not exists public.game_rooms (
  id uuid primary key default gen_random_uuid(),
  room_code text unique not null,
  status text not null default 'waiting'
    check (status in ('waiting', 'playing', 'finished', 'closed')),
  host_player_id uuid references public.player_profiles(id) on delete set null,
  max_players integer not null default 4 check (max_players between 2 and 6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.room_players (
  room_id uuid references public.game_rooms(id) on delete cascade,
  player_id uuid references public.player_profiles(id) on delete cascade,
  seat_index integer not null,
  bankroll integer not null default 1000,
  joined_at timestamptz not null default now(),
  primary key (room_id, player_id),
  unique (room_id, seat_index)
);

create table if not exists public.multiplayer_events (
  id bigint generated always as identity primary key,
  room_id uuid references public.game_rooms(id) on delete cascade,
  player_id uuid references public.player_profiles(id) on delete set null,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.player_profiles enable row level security;
alter table public.weekly_scores enable row level security;
alter table public.game_rooms enable row level security;
alter table public.room_players enable row level security;
alter table public.multiplayer_events enable row level security;

-- Temporary open read policies for early prototyping. Tighten these when
-- adding Supabase Auth and anti-cheat validation.
create policy "Public profiles are readable"
  on public.player_profiles for select
  using (true);

create policy "Weekly scores are readable"
  on public.weekly_scores for select
  using (true);

create policy "Game rooms are readable"
  on public.game_rooms for select
  using (true);

create policy "Room players are readable"
  on public.room_players for select
  using (true);

create policy "Room events are readable"
  on public.multiplayer_events for select
  using (true);

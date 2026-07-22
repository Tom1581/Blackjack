# Supabase Connection

The Flutter app is connected to this Supabase project:

- URL: `https://yktyobprlradqtvmqfki.supabase.co`
- Publishable key: configured in `lib/core/supabase/supabase_config.dart`

The key in Flutter is a public publishable key, not a service role key. Never
put a Supabase service role key into the app.

## Keeping the Free Project Active

Supabase can pause Free projects after a week without enough database activity.
This game uses Realtime for multiplayer, which does not necessarily create
database requests. Apply
`migrations/20260722000000_free_tier_heartbeat.sql` in the Supabase SQL Editor,
then push this repository to GitHub. The scheduled GitHub Actions workflow will
call the small `keep_alive` database RPC three times per day. It stores no user data
and has no paid services; it uses only the same public publishable key already
bundled into the Flutter app.

## Runtime Overrides

For another Supabase project, run Flutter with:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

For release builds:

```bash
flutter build appbundle --release \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

## Online Multiplayer (implemented)

Play-with-friends multiplayer is built and working. It uses **Supabase Realtime
Broadcast + Presence** — no database tables, no auth, and no Edge Functions.
That means:

- **Nothing to deploy or configure.** It works with the publishable key already
  in the app, entirely inside the Supabase free tier. Realtime is enabled by
  default on new projects; if you ever turned it off, re-enable it under
  *Project → Realtime*.
- **You do NOT need to apply the SQL migration below to play online.** That
  migration is only a foundation for *future* persistence (a real cross-device
  leaderboard, saved rooms). Current gameplay is fully in-memory on the channel.

### How it works

- One player taps **Play Online → Create a Table** and gets a 4-letter room
  code; friends tap **Join Table** and enter the code.
- Each room is a Realtime channel (`bj_room_<CODE>`). Presence tracks who is
  seated; broadcast messages carry game state and player actions.

### Many tables, not one

There is no single shared table. **Every "Create a Table" mints a fresh random
room code = a brand-new, independent table**, and any number of tables can run
at the same time — rooms never see each other's players or cards. So when there
are lots of players, they simply split across multiple tables.

Each table seats up to **5 players** (`OnlineTableLogic.maxSeats`). If someone
tries to join a code that is already full, they get a clear "table is full — go
back and create or join another" message instead of hanging.

> Joining is by room code (share it with friends). There is no public "browse
> open tables" list yet — that needs the persistent DB tables below and is a
> straightforward follow-up if you want automatic match-making.
- The **host device is authoritative**: it owns the shoe and dealing and
  broadcasts the table state after every change; guests send action intents and
  render what the host broadcasts. The host validates every action (e.g. you can
  only act on your turn).
- Rules match the single-player game: dealer hits soft 17, blackjack pays 3:2,
  double-on-any-two. (Splitting is single-player only for now.)

### Trade-off to know

Because the host deals, a modified host client could in principle cheat. That is
the standard, free, no-server model and is fine for play-money games with
friends. To make it tamper-proof later, move dealing into a Supabase Edge
Function or dedicated server (that's the "real online" upgrade path) — the app's
`RealtimeTransport` abstraction is designed so only the transport/authority layer
changes.

### How to verify live

Run the app on two devices or emulators (or one device + one emulator):

1. On device A: *Play Online → Create a Table*. Note the room code.
2. On device B: *Play Online → Join Table*, enter that code.
3. Both should see each other seated. Place bets, the host taps **Deal**, and
   play proceeds seat by seat.

## Database Foundation (optional / future)

`migrations/20260714000000_initial_online_foundation.sql` contains starter
tables for:

- player profiles
- weekly leaderboard scores
- multiplayer rooms
- room seats
- realtime multiplayer events

Apply it in the Supabase SQL Editor only when you want to add **persistent**
online features (these are not required for the current multiplayer). Note the
policies there are read-only prototypes — add auth and write policies before
relying on them.

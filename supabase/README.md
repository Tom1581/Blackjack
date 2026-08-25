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

- One player taps **Play Online → Create a Table** and gets a 5-character room
  code; friends tap **Join Table** and enter the code.
- Each room is a Realtime channel (`bj_room_<CODE>`). Presence tracks who is
  seated; broadcast messages carry game state and player actions.
- The **host device is authoritative**: it owns the shoe, the dealing, and the
  settlement, and broadcasts the table after every change. Guests send action
  intents and render what the host broadcasts.

### Many tables, and a lobby that lists them

There is no single shared table. **Every "Create a Table" mints a fresh random
room code = a brand-new, independent table**, and any number of tables can run
at the same time — rooms never see each other's players or cards.

Each table seats up to **5 players** (`OnlineTableLogic.maxSeats`). A joiner who
picks a full table is told so instead of hanging. Before claiming a code, a new
host listens on the channel for ~1.2s; if somebody is already hosting it, the
app quietly hands the player a different code rather than running two
conflicting tables on one channel.

**Players do not need a room code to find a game.** The Play Online screen shows
an **Open Tables** list: every public table currently being hosted, with its host,
seat count, and whether it is taking bets or mid-round. Tap JOIN to sit down.
Full tables are listed but marked FULL, and joinable ones sort first.

That list is built on **Presence on one well-known channel** (`bj_room_LOBBY`,
see `lib/features/online/lobby/table_directory.dart`) — still no database:

- A host's advert *is* its presence entry, so a table appears the instant the
  host connects and **disappears on its own the moment they leave**. There is no
  room table to keep tidy and nothing to garbage-collect.
- The advert is refreshed only when something actually changes (seats, phase,
  round), so a table sitting idle costs no traffic.
- `LOBBY` can never collide with a real room code: codes are generated from an
  alphabet with no `O`, `I`, `0` or `1`.
- Hosts can switch a table to **Invite only** when creating it; it then works
  exactly as before, reachable by code and never listed.

> A public lobby means playing with strangers, which is where the host-deals
> trust model below is weakest. For anything beyond friendly play money, do the
> server-dealer upgrade first.

### Rules

Full parity with the single-player engine: dealer hits soft 17, blackjack pays
3:2, double on any two cards, **split up to four hands**, split aces draw one
card each, a two-card 21 from a split pays even money (not 3:2), and
**insurance** pays 2:1 when the dealer shows an ace. The table also shares one
Hi-Lo running count, true count, and shoe penetration across every seat.

### Nothing stalls, nothing is lost

Every phase runs on a clock the whole table can see, so one unresponsive player
can never freeze the round:

| Phase | Clock | What happens on expiry |
| --- | --- | --- |
| Betting | 25s from the first chip | The round deals itself |
| Insurance | 12s | Unanswered seats decline |
| A player's turn | 25s | That hand stands |
| Results | 12s | The next round starts |

- A player who drops **keeps their seat and their chips** for 60 seconds and
  reclaims both on reconnect. Dropping mid-round stands the hand so the wager
  settles normally rather than vanishing.
- A player who runs out of chips can **buy back in** instead of becoming a
  permanent spectator.
- The host re-broadcasts every 2.5s. Guests use that as a liveness signal and as
  the repair path for a dropped message; every broadcast carries a sequence
  number, so a late or duplicated one can never rewind the table.
- Guests get a clear, actionable screen — not a spinner — for a wrong room code,
  a host who left, a full table, or a friend on an older build.

### The trust model, stated honestly

The host deals, so a **modified host client could cheat**. That is the standard
free, no-server model and is fine for play-money games with friends.

Two things narrow the blast radius, and one thing does not:

- Guests **pin the host**: only the client that sent the first table state can
  drive their screen, so no peer can forge a table or take one over.
- The host attributes every action to the message's **sender**, never to an id
  the message body claims, and applies it only if that sender holds a seat.
- **But** Supabase Broadcast relays payloads verbatim without stamping a sender,
  so on the real transport that sender id is still self-declared. A deliberately
  modified client can forge it. Closing that for good needs a server-side dealer
  with real auth (Supabase anonymous auth + an Edge Function) — the
  `RealtimeTransport` seam exists so only the transport and authority layers
  have to change.

Treat online play as "friends with play money", not as a trustless casino.

### One wire-format trap, already paid for

Supabase Realtime **overwrites `payload['event']`** on a delivered broadcast with
the broadcast event name, and adds its own `payload['type']`. The transport
originally labelled its messages with `payload['event']`, so every message
arrived relabelled `msg` and was silently dropped by the receiver — multiplayer
did not work over the real network at all, while the in-memory tests passed
happily.

The message kind now travels as `payload['kind']`
(`SupabaseTransport.encodeEnvelope`), and
`SupabaseTransport.reservedPayloadKeys` plus `test/online_transport_test.dart`
guard it. **Never put your own data under `event` or `type` in a broadcast
payload.**

### How to verify live

Automated, no network — `flutter test` drives full multi-player sessions,
including disconnects, forged messages, host departure, the lobby, and every
clock, through an in-memory transport.

Automated, against the real service:

```bash
# Three real clients on one live table + the live lobby.
flutter test test/live/live_table_check.dart

# Lower-level presence/broadcast smoke check.
dart run tool/realtime_live_check.dart
```

`test/live/live_table_check.dart` is deliberately **not** named `*_test.dart`,
so `flutter test` never picks it up and the normal suite stays hermetic. It
opens three independent Supabase clients — three "phones" — seats them at one
table, plays a complete round through the real `OnlineController` and
`SupabaseTransport`, and asserts all three converge on the same result. This is
the check that caught the wire-format trap above; run it after touching the
transport.

Manually, on two devices or emulators:

1. On device A: *Play Online → Create a Table*. Note the room code.
2. On device B: *Play Online → Join Table*, enter that code.
3. Both should see each other seated. Place bets, tap READY, the host taps
   **Deal**, and play proceeds seat by seat.

## Weekly Rankings (needs two setup steps)

Players compete on a shared weekly leaderboard that resets every Monday. Unlike
multiplayer, this one **does** need the database, because a ranking has to
outlive the session.

### Setting it up

1. **Apply the migration.** Paste
   `migrations/20260825000000_weekly_rankings.sql` into the Supabase SQL
   Editor and run it. It creates `public.weekly_rankings` with row-level
   security and sanity constraints.
2. **Enable anonymous sign-ins.** Supabase dashboard →
   *Authentication → Providers → Anonymous sign-ins* → enable.

Both are free. Until they are done the app does **not** break: the board falls
back to showing only that player's own week, with a "rankings are being set
up" note, and their score keeps accumulating locally so it appears the moment
you switch it on.

### Why anonymous auth

Each device signs in anonymously once and gets a real `auth.users` id. The
policies key on it:

- anyone may `select` — that is what a leaderboard is for
- you may only `insert`/`update` a row where `auth.uid() = player_id`

Without it, any player could overwrite or delete anyone else's score using the
publishable key that ships in the APK.

### What this does and does not protect

Scores are still submitted by the client, so **a modified client can inflate
its own score** — it just cannot touch anybody else's. The table constraints
blunt the absurd cases (a name longer than the column, a profit with no hands
behind it, `abs(profit) > hands_played * 10000`), but real validation needs the
server-side dealer described above. For a play-money practice app that is the
right trade; revisit it if the board ever matters to anyone.

### How it behaves

- The app pushes your weekly total at most every 30 seconds while you play,
  and only when it has actually changed — a finished round is not a REST call.
- Opening the board pushes first, so you always see yourself on the board you
  are looking at.
- The board shows the top 100 for the current week, your own row pinned if you
  fall outside it, and the exact gap to the player above you.
- Old weeks are never read. Prune them whenever you like:
  `delete from public.weekly_rankings where week_key < 'W123';`

### Verifying it

```bash
flutter test test/weekly_board_test.dart
```

covers ranking, the chase gap, throttled writes, week rollover, and each
failure mode (missing table, anonymous sign-ins disabled, offline). To check
the live table, play a hand and then look for a row:

```bash
curl -s "$SUPABASE_URL/rest/v1/weekly_rankings?select=*" \
  -H "apikey: $SUPABASE_PUBLISHABLE_KEY"
```

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

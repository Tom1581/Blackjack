# Supabase handoff: Hi-Lo Training leaderboards

**For:** the agent doing the database work.
**Written:** 2026-10-01.
**Repo:** this Flutter app (`blackjack_app`). Supabase project `yktyobprlradqtvmqfki`.

Hi-Lo Training (`lib/features/hilo_training/`) is a lobby game mode where a
dealer deals real rounds and asks for the Hi-Lo running count at random
moments. Its Daily Challenge (the same shoe for every player each day) and
Survival mode currently keep scores **on the device only**. The database work
below gives them shared leaderboards.

The app is finished and tested without these tables. The database work must
not break it, and the app must keep working until the migration is applied.

---

## What is live today (checked 2026-10-01)

| Check | Result |
|---|---|
| `weekly_rankings` table + `submit_weekly_ranking` | live |
| Anonymous sign-ins | enabled |
| `keep_alive` RPC | 200 |
| `20260929000000_weekly_accuracy.sql` | **not applied** — `weekly_rankings.decisions` answers `42703` |
| `hilo_daily_scores` | does not exist — answers `PGRST205` |

---

## Task 0 — apply the pending accuracy-league migration

`supabase/migrations/20260929000000_weekly_accuracy.sql` is already written,
reviewed, and validated (`tool/sql_checks/weekly_accuracy_check.sql`). Do not
edit it. Apply it as is, in the SQL Editor or with `supabase db push`.

It is safe with older app versions live: the original
`submit_weekly_ranking(text, text, integer, integer)` is untouched.

Verify:

```bash
curl -s "https://yktyobprlradqtvmqfki.supabase.co/rest/v1/weekly_rankings?select=decisions&limit=1" \
  -H "apikey: sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm"
# want: [] or rows      (before: {"code":"42703", ...})
```

---

## Task 1 — write `supabase/migrations/20261001000000_hilo_training_boards.sql`

Follow the conventions the existing migrations already use. Read
`20260825000000_weekly_rankings.sql`, `20260826000000_secure_online_and_rankings.sql`
and `20260929000000_weekly_accuracy.sql` first:

- **Writes:** only through `security definer` functions that use `auth.uid()`
  and `set search_path = public, pg_temp`.
- **Direct writes revoked:** `revoke insert, update, delete … from anon, authenticated`.
- **Reads:** public. Enable RLS, then add a `select using (true)` policy and
  `grant select … to anon, authenticated`.
- **Function grants:** `revoke all on function … from public, anon`, then
  `grant execute … to authenticated`.
- **Validation errors:** `errcode '22023'` for bad input, `'42501'` for not
  signed in.
- **Plausibility:** check it twice, as `CHECK` constraints on the table and
  again in the function. Cast to `bigint` before multiplying.
- **Bounded history:** prune old rows inside the submit function. No pg_cron.
- **Idempotent:** use `create … if not exists`, `drop policy if exists`, and
  `create or replace`.

### Facts the plausibility checks rest on

These come from `lib/features/hilo_training/hilo_scoring.dart` and `hilo_game.dart`.

- **Per right answer:** a right running count scores (100 + speed bonus 0–100)
  × combo 1–4. That is **at least 100 and at most 800**. A wrong or
  timed-out answer scores 0. Daily and Survival never ask for the true count,
  so the separate +50 true-count bonus never applies to them.
- **Daily Challenge:** exactly 10 questions. A player can end early, so
  0–10 are answered.
  - *Day number:* local calendar date − 2026-09-28. Daily #1 is 2026-09-29;
    the app never sends less than 1.
  - *Timezones:* the app uses the player's **local** date, so near midnight it
    can differ from the server's UTC date by one day either way.
- **Survival:** the game ends on the third miss, or earlier if the player stops.
  - *Misses:* answered − correct is 0–3.
  - *Level:* always exactly `1 + correct / 5`, using integer division.
  - *Week key:* the same `W<n>` format and epoch as `weekly_rankings`, i.e.
    `'W' || ((date - date '2024-01-01') / 7)`. The app computes it from the
    local date.

### 1a. `public.hilo_daily_scores`: one row per player per day, first try only

| column | type | notes |
|---|---|---|
| `player_id` | `uuid not null references auth.users(id) on delete cascade` | |
| `day` | `integer not null` | Daily number, ≥ 1 |
| `display_name` | `text not null` | 1–12 chars after trim |
| `score` | `integer not null` | |
| `correct` | `integer not null` | |
| `answered` | `integer not null` | |
| `best_streak` | `integer not null` | |
| `submitted_at` | `timestamptz not null default now()` | |

- Primary key `(player_id, day)`.
- Check: `answered between 0 and 10`, `correct between 0 and answered`,
  `best_streak between 0 and correct`, and
  `score between correct * 100 and correct * 800`.
- Index `(day, score desc, submitted_at asc)`.

**`submit_hilo_daily(p_day integer, p_display_name text, p_score integer, p_correct integer, p_answered integer, p_best_streak integer) returns public.hilo_daily_scores`**

- Raise `42501` when `auth.uid()` is null.
- Accept `p_day` only within ±1 of `(current_date - date '2026-09-28')`, the
  timezone allowance. Otherwise raise `22023`.
- Validate the name and every number against the rules above. Raise `22023`
  on failure.
- **The first submission for a day is final.** Use
  `insert … on conflict (player_id, day) do nothing`, then return the stored
  row, which is the earlier one when a row already existed. A player may
  replay the day's shoe in the app, but replays are practice. They must never
  replace the official score, even if a buggy client resends.
- Prune rows where `day` is more than 60 days old.

**`hilo_daily_standing(p_day integer) returns table (rank integer, players integer, score integer)`**

- Returns the caller's position for the day: `rank = 1 + rows above`, where a
  row is above if its score is higher, or equal and submitted earlier.
- `players` is the count of all rows that day. Return no row if the caller
  has none.
- `stable`. It may be `security invoker`, since the table is publicly
  readable. Grant execute to `authenticated` only.

**The board read** is a plain REST select. No function is needed:
`hilo_daily_scores?select=player_id,display_name,score,correct,answered,best_streak&day=eq.<n>&order=score.desc,submitted_at.asc&limit=100`

### 1b. `public.hilo_survival_scores`: best run per player per week

| column | type | notes |
|---|---|---|
| `player_id` | `uuid not null references auth.users(id) on delete cascade` | |
| `week_key` | `text not null` | `^W[0-9]{1,6}$` |
| `display_name` | `text not null` | 1–12 chars |
| `score` | `integer not null` | |
| `correct` | `integer not null` | 0–1,000 |
| `answered` | `integer not null` | `answered - correct between 0 and 3` |
| `level` | `integer not null` | `= 1 + correct / 5` |
| `submitted_at` | `timestamptz not null default now()` | |

- Primary key `(player_id, week_key)`.
- Check: `score between correct * 100 and correct * 800`, together with the
  constraints in the table.
- Index `(week_key, score desc, submitted_at asc)`.

**`submit_hilo_survival(p_week_key text, p_display_name text, p_score integer, p_correct integer, p_answered integer, p_level integer) returns public.hilo_survival_scores`**

- Raise `42501` when not signed in.
- Accept the server's current week key, or one either side of it (the
  timezone allowance, as for the Daily). Otherwise raise `22023`.
- Validate every rule above, including the exact level formula.
- **Keep the best run of the week.** Insert if no row exists. Update only when
  `p_score` beats the stored score; the display name may also be updated
  then. Return the stored row.
- Serialize concurrent calls per player and week, the way
  `submit_weekly_ranking_v2` does with `pg_advisory_xact_lock`.
- Prune weeks more than 12 old.

**The board read:**
`hilo_survival_scores?select=player_id,display_name,score,level,correct&week_key=eq.<W..>&order=score.desc,submitted_at.asc&limit=100`

### Must not change

- Nothing else may change: no existing table, function, policy or grant, and
  no `realtime.*`.
- **Never** put a service-role key in the app or in the repo.

---

## Task 2 — validate on a throwaway database first

Add `tool/sql_checks/hilo_boards_check.sql`, following the header and style of
`tool/sql_checks/weekly_accuracy_check.sql`. Run it against
`public.ecr.aws/supabase/postgres:15.8.1.085` in Docker. **Never run it
against production.** Write the actual results into the file header.

Cases, at minimum:

1. **Daily valid submit:** the row is stored and returned.
2. **Daily second submit:** a higher score on the same day is ignored, and the
   first row is returned.
3. **Daily day window:** today ±1 is accepted; today ±2 is refused with `22023`.
4. **Daily score range:** a score below `correct*100` or above `correct*800` is
   refused. So are `correct > answered`, `best_streak > correct`, and
   `answered > 10`.
5. **Names:** an empty name and a 13-character name are refused; a name with
   leading or trailing spaces is trimmed.
6. **`hilo_daily_standing`:** check the rank, including that the earlier
   submission wins a tie, and the players count.
7. **Survival:**
   - *Level mismatch:* correct 12 with level 2 is refused; level 3 is accepted.
   - *Misses:* `answered - correct = 4` is refused.
8. **Survival best of week:** a lower second score keeps the first; a higher
   one replaces it.
9. **Survival week window:** the current week ±1 is accepted; ±2 is refused.
10. **Anonymous role:** permission denied on both submit functions.
11. **Direct writes:** an insert or update on either table as `authenticated`
    gets permission denied.
12. **Pruning:** a 61-day-old daily row and a 13-week-old survival row are gone
    after a submit.

---

## Task 3 — apply to live and verify

Apply Task 0 and Task 1, then:

```bash
KEY="sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm"
BASE="https://yktyobprlradqtvmqfki.supabase.co/rest/v1"
curl -s "$BASE/hilo_daily_scores?select=day&limit=1"       -H "apikey: $KEY"   # want []
curl -s "$BASE/hilo_survival_scores?select=week_key&limit=1" -H "apikey: $KEY" # want []
curl -s -X POST "$BASE/rpc/submit_hilo_daily" -H "apikey: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_day":1,"p_display_name":"x","p_score":0,"p_correct":0,"p_answered":0,"p_best_streak":0}'
# want: permission denied / 401 — the anon key alone must not be able to write
```

---

## Task 4 (optional, only if asked) — the Flutter side

Hi-Lo Training was built by a different agent, under the rule that changes
stay inside `lib/features/hilo_training/` plus the one lobby button. Keep to
that.

- **New file:** `lib/features/hilo_training/hilo_boards_service.dart`. Model it
  on `lib/features/leaderboard/weekly_board_service.dart`: a narrow backend
  interface plus a Supabase implementation, so the logic is testable without a
  network.
- **Backend:**
  - Gate everything on `AppSupabase.isReady` (`lib/core/supabase/supabase_service.dart`).
  - *Identity:* sign in anonymously the same way `SupabaseBoardBackend.identify()` does.
  - *Name:* use `loadPlayerName()` from `lib/features/online/online_providers.dart`,
    falling back to `'Player'` and cutting it to 12 characters.
- **When to submit:** from `_HiLoGameScreenState._finish()` in
  `hilo_game_screen.dart`, after `recordGame`, fire-and-forget. A failure must
  never block or delay the results screen.
  - *Daily:* when `spec.mode == HiLoMode.daily && spec.ranked`. Send
    `dailyNumber`, the score, `correct`, `answered` and `bestStreak` of
    `players.first`.
  - *Survival:* when `spec.isSurvival && spec.ranked && !spec.isChallenge`.
    Leave challenge seeds out: a friend could hand-pick an easy shoe.
- **Not set up yet:** treat `PGRST202`, `PGRST205`, `42883`, `42P01` and
  `42703` as "leaderboard being set up" and show that. Note `PGRST205`:
  `SupabaseBoardBackend.isMissingSchema` does not include it, and a missing
  table answers with it.
- **UI:** the hub Daily card gets "#7 of 213 today" and a "Today's top 100"
  sheet; the Survival tile gets "This week" plus a board.
- **Tests:** follow `test/weekly_board_test.dart` (fake backend). Widget tests
  need real fonts (`test/support/real_fonts.dart`); see `PICK_UP_HERE.md` →
  "Traps".
- **Formatting:** run `dart format` on named files only, never a whole folder.
  It rewrites untouched files.

---

## Done means

- [ ] Task 0 applied; the `decisions` curl answers `[]` or rows
- [ ] Migration file added; check script added with real results in its header
- [ ] Applied live; the three Task 3 curls give the expected answers
- [ ] `flutter test` and `flutter analyze` still clean (95 info notes are pre-existing)
- [ ] Report back: what was applied, the check results, and anything that differed from this spec, and why

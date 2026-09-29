# Handover — what is left, and who can actually do it

> **Latest pass: 2026-09-29 (1.3.0+11)** — the whole roadmap is built: two-deck
> chart, late surrender, index plays, bet-spread coach, accuracy league. See
> "What is built, and what is next" below. One new console step: **A8**.
>
> **Resuming? Start with `PICK_UP_HERE.md`.** Status as of 2026-09-29: A1
> (rewarded unit), A3 (rankings migration) and A4 (anonymous sign-ins) are
> **done**; the sections below were written before that and are kept for
> reference.

Checked live on 2026-08-26. Most of what remains is **console work in your
Google and Supabase accounts**, which no coding agent can do for you. The
genuine code tasks are in part B and there are not many.

## Where things stand

Verified 2026-08-26, immediately before deployment.

| Check | Result |
| --- | --- |
| `flutter test` | **310 passing**, 8 consecutive clean runs |
| `flutter analyze` | **0 errors, 0 warnings** |
| Release bundle | **Builds** — `app-release.aab`, 46.9 MB |
| Sound assets in the bundle | 7 of 7 |
| Live Realtime (multiplayer) | Presence + broadcast roundtrip OK |
| Supabase project | Awake (`keep_alive` → 200) |
| Version | `1.1.0+4` |

### Safe to ship, with two features inert until you act

Neither breaks anything; both degrade on purpose.

- **Rewarded ads earn $0** until a live unit id exists (A1). Both placements
  grant their chips with no ad and the button says so.
- **Weekly rankings show a board of one** until the migration is applied and
  anonymous sign-ins are enabled (A3, A4). Scores accumulate locally and appear
  the moment you switch them on.

Re-verified today: `weekly_rankings` → **404**, auth → **`anonymous_provider_disabled`**,
rewarded unit → **empty**.

### One thing to expect after the update

Existing players will see the three-page intro once, because the "seen" flag is
new in this release. It is skippable from the first tap, and given how much has
changed since 1.0.2 it is arguably the right thing to show them.

---

## Part A — only you can do these (console, no code)

Verification commands are included so you can prove each one landed.

### A1. Create the Rewarded ad unit  ← blocks all ad revenue

AdMob → **Apps** → *Hi-Lo Blackjack Trainer* → **Ad units** → **Add ad unit** →
**Rewarded**. Name it `hilo-rewarded-chips`, reward `500` `chips`.

Copy the unit id (`ca-app-pub-1653382608147355/XXXXXXXXXX`) and give it to
whoever does B1.

**Until this exists, both rewarded placements grant their chips with no ad and
earn $0.** That is deliberate — nothing breaks, it just does not pay.

### A2. Finish AdMob payment setup  ← blocks any payout

AdMob → **Payments → Settings**:

- [ ] Address verified — Google posts a PIN, this can take weeks, start now
- [ ] Tax information submitted
- [ ] Payment method added

Earnings roll over and are not lost, but nothing is paid until these are done.

### A3. Apply the weekly rankings migration  ← blocks the leaderboard

Supabase → **SQL Editor** → paste and run
`supabase/migrations/20260825000000_weekly_rankings.sql`.

Verified 2026-08-25: currently returns **HTTP 404** (table does not exist).

```bash
curl -s -o /dev/null -w "%{http_code}\n" \
  "https://yktyobprlradqtvmqfki.supabase.co/rest/v1/weekly_rankings?select=*&limit=1" \
  -H "apikey: sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm"
# want: 200   (404 = not applied yet)
```

### A4. Enable anonymous sign-ins  ← also blocks the leaderboard

Supabase → **Authentication → Providers → Anonymous sign-ins** → enable.

Verified 2026-08-25: currently returns `anonymous_provider_disabled`.

```bash
curl -s -X POST "https://yktyobprlradqtvmqfki.supabase.co/auth/v1/signup" \
  -H "apikey: sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm" \
  -H "Content-Type: application/json" -d '{}'
# want: a user object   (currently: "Anonymous sign-ins are disabled")
```

Without this, players could overwrite each other's scores — the row-level
policies key on the anonymous user id.

### A5. Refresh the store listing

Play Console → **Store presence → Main store listing**. Paste the title, short
description, full description and release notes from
`store-assets/google-play/listing-text.md` (all verified within Play's limits).

**Screenshots are stale** — they predate online play and the coach. The three
worth shooting: the open-tables lobby, a five-seat table mid-round, and the
coach correcting a misplay.

### A6. Update the Data Safety form and privacy policy  ← compliance

The app declares `com.google.android.gms.permission.AD_ID` and serves AdMob
ads, so Play requires the Data safety form to disclose the advertising ID and
advertising use, and the privacy policy to match.

Play Console → **Policy → App content → Data safety**. Confirm:

- [ ] Device or other IDs → **collected**, purpose **Advertising or marketing**
- [ ] Third-party sharing declared for AdMob
- [ ] The privacy policy at `privacy-policy-google-sites.html` says the same

An inaccurate form is grounds for removal, so this is worth getting right
before the next release rather than after.

### A7. Optional — `app-ads.txt`

Needs a website on your Play listing. Host the line AdMob gives you at
`https://yourdomain.com/app-ads.txt`. Some ad demand will not bid without it.

---

## Part B — real code tasks (hand these to Codex)

### B0. Analytics and crash reporting — not built, deliberately

There is none. Play Console already reports crashes and ANRs for free with no
SDK, and that is the right place to start given there are 12 monthly users —
an analytics SDK would report on almost nobody while adding a dependency, a
Data Safety disclosure, and a consent flow.

Worth adding once there is traffic to measure. It needs a Firebase project,
which only you can create.

### B1. Paste the rewarded unit id  *(needs A1 first)*

`lib/core/ads/ad_service.dart`:

```dart
static const androidRewardedUnitId = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: 'ca-app-pub-1653382608147355/XXXXXXXXXX',   // <- from A1
);
```

Or leave the code alone and pass `--dart-define=ADMOB_REWARDED_ANDROID=...` at
build time. The ad tests accept either an empty or live rewarded unit id, so
no test change is needed when the real id is supplied.

### B2. Bump the version

`pubspec.yaml` is still `1.0.2+3`. Play rejects a duplicate version code, so
this must go up — suggest `1.1.0+4`, since this is a large feature release.

### B3. Commit and release

63 files are uncommitted. I have not committed anything; that is your call.

```bash
flutter test && flutter analyze          # expect 270 passing, 0 errors
flutter build appbundle --release \
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-.../...
```

Then upload the `.aab` in Play Console → **Test and release → Production**.

**Nothing in this repo reaches a single user until this is done.**

### B4. iOS is not wired up  *(only if you want an iOS build)*

- `ios/Runner/Info.plist` carries **Google's sample app id**
  (`ca-app-pub-3940256099942544~1458002511`), not yours
- `AdMobIds._supported` is Android-only, so iOS serves no ads at all
- No iOS interstitial or rewarded unit ids exist

Needs: register the iOS app in AdMob, real `GADApplicationIdentifier`, iOS unit
ids, and widening `_supported`.

---

## Part C — needs a person, a device, or ears

### C1. Listen to the sound effects

`assets/sfx/*.wav` were **generated procedurally** by
`tool/generate_sfx.py`. They were written without anyone hearing them. Play the
game with sound on and judge chip, card, win, lose, push and blackjack. To
change one, edit the generator and re-run `python3 tool/generate_sfx.py`, or
drop in your own recording with the same filename — nothing else changes.

### C2. Verify rewarded ads on a real device  *(after A1 + B1)*

Emulators will not tell you whether live ads fill. Install a release build,
play until you are out of chips, and confirm a real ad plays and the chips
arrive afterwards. Watch `logcat` for `Rewarded failed to load`.

### C3. Verify the leaderboard  *(after A3 + A4)*

Play one hand, then:

```bash
curl -s "https://yktyobprlradqtvmqfki.supabase.co/rest/v1/weekly_rankings?select=*" \
  -H "apikey: sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm"
```

You should see your row. In the app the board should stop saying "rankings are
being set up".

---

## What is built, and what is next

### 2026-09-28 audit — version 1.2.0+10

Every defect below was reproduced before it was fixed, and each has a
regression test in `test/table_regressions_test.dart` or `test/training_test.dart`
(372 tests passing, up from 321; `flutter analyze` 0 errors / 0 warnings).

**Game-rule and system bugs fixed**

| # | Bug | Effect on players |
|---|-----|-------------------|
| 1 | Dealer badge read `hand.value`, which includes the face-down hole card | Showed "17" over a lone ten on every hand — the hole card was given away (solo, and on the online host's screen) |
| 2 | Dealer ace + player natural left `activeHandIndex` past the end | RangeError building the action bar (~0.4% of hands) |
| 3 | Changing rules/shoe from the lobby mid-round replaced the round | The stake, already deducted, vanished |
| 4 | Rule change read a derived provider before Riverpod invalidated it | First rules change after launch: dealer kept the old rules while the coach graded the new ones |
| 5 | Felt text hard-coded "3 to 2" and "hit soft 17" | Wrong rules printed on the 6:5 and S17 tables |
| 6 | Stats screen read `hands_played`, `wins`, … that nothing wrote; provider cached forever | Stats always 0 hands / 0% |
| 7 | Reshuffle message computed after the reset and never shown; state kept the old count until the next deal | Count silently reset — fatal for anyone counting with the HUD off |
| 8 | Solo dealer drew on all-bust / all-natural rounds (online already fixed for busts) | Burned shoe cards a real dealer never deals |
| 9 | True count divided by decks rounded **up** | TC understated late in the shoe (RC +6 with 1.5 decks read +3, not +4) — now nearest half deck |
| 10 | Count HUD, shoe and hands-per-round not persisted | Reset every launch |
| 11 | "Atlantic City" blurb claimed 8 decks; no 8-deck shoe existed | Now an 8 D shoe option, and honest wording |
| 12 | Bankroll pill rounded ("1.0k" for $1,049); bet tabs overflowed on 360dp phones | Exact bankroll; layout fixed |
| 13 | An empty shoe mid-round would throw | Now reshuffles (and resets the count) instead |

**Features added** (the Hi-Lo training was extended, nothing removed — the
Daily Count Drill, count HUD and coach all work exactly as before)

- **Training Center** (`lib/features/training/`): Strategy Drill (hard / soft /
  pairs / *my mistakes*), Speed Count (incl. deck countdown), True Count drill,
  and the existing Daily Count Drill.
- **Strategy chart screen** — computed by `BasicStrategy.best`, so it can never
  disagree with the coach. Also reachable from the table's top rail.
- **Count check quiz** — with the HUD hidden the table asks for the running
  count every 5 hands; accuracy shows on the stats screen.
- **Per-category mastery + most-missed cells** (roadmap item 1 below).
- **Discard tray** on the felt (no number — estimating decks is the skill).
- **Insurance tip**: insure at TC ≥ +3; shows the live TC only if the HUD is on.
- **REBET**, card deal slide-in animation, radial felt, curved felt text.

**Still not done, on purpose:** double-deck chart (the 2 D shoe now says the
coach uses the multi-deck chart), surrender, Illustrious 18 deviations — all
three change what "correct" means and need their own tested grids first.

### 2026-09-29 — roadmap finished, version 1.3.0+11

Every roadmap item from the audit is now built, each with its own tests
(489 tests passing; `flutter analyze` 0 errors / 0 warnings; release AAB
builds).

| Feature | Where | How it was verified |
|---|---|---|
| **Two-deck strategy chart** | `basic_strategy.dart` (`decks:`) | Every cell of 48 published charts (2/6/8 decks × H17/S17 × DAS × 3 doubling rules × surrender) in `test/strategy_reference_test.dart`; the 168 cells that differ re-derived with our own EV calculator (`tool/strategy_check/`) — 168/168 agree |
| **Late surrender** | engine, action bar, coach, chart, stats; presets *H17 + Surrender*, *S17 + Surrender* | `test/surrender_test.dart`; chart cells in the reference test |
| **Index plays** (Illustrious 18 + Fab 4, H17/S17) | `deviations.dart`, `table_coach.dart`, lobby toggle, Index Drill | `test/deviations_test.dart` — every index flips exactly at its number (floored true count) |
| **Bet-spread coach** (true count − 1 units, 1–8) | `bet_ramp.dart`, betting panel, deal check, stats | `test/bet_ramp_test.dart` |
| **Accuracy league** | `weekly_board_service.dart`, leaderboard PROFIT / ACCURACY toggle | `test/weekly_board_test.dart`, `test/leaderboard_widget_test.dart`; the SQL validated on a real Supabase Postgres (`tool/sql_checks/`) |

Also fixed on the way: a round's dealer sequence could keep writing to a
disposed table (now stops), and the felt overflowed on short phones (360×600,
320×568) with three hands and a coaching note — cards now size to the space
(`test/table_fit_test.dart`, measured with the real Roboto font, not the test
font, which is twice as wide and reports overflows no phone shows).

**Design rules worth keeping**

- Index plays only apply on 4+ deck shoes and never on a continuous shuffler.
  A two-deck game has different indices; the app does not teach those.
- An index entry only applies when basic strategy is already making one of
  its two plays — so 8,8 v 10 still splits and a surrender cell stays a
  surrender. A departure from the chart is recorded as an index decision
  only, never as a chart miss.
- With the count HUD hidden, a hand an index play governs gets no hint (it
  would give the count away); the bet coach shows only its rule, not the
  number.

**Needs the owner (A8):** apply
`supabase/migrations/20260929000000_weekly_accuracy.sql` in the SQL Editor.
It is safe with older app versions live: the original
`submit_weekly_ranking` API remains available. Until it is applied the app
falls back to the original function (checked against the live server: it answers
`PGRST202` / `42703`, which the app treats as "not set up yet") and the
Accuracy tab says the rankings are being set up.

```bash
curl -s "https://yktyobprlradqtvmqfki.supabase.co/rest/v1/weekly_rankings?select=decisions&limit=1" \
  -H "apikey: sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm"
# want: [] or rows    (now: 42703 "column ... decisions does not exist")
```

### Still not built, on purpose

- **Single deck.** A different chart again and different indices; not
  offered, not verified.
- **Resplitting aces.** `RuleSet.resplitAces` exists but no preset enables it
  and the engine does not deal the resplit; the reference charts assume no
  resplit, so this matches what is taught.
- **Two-deck index plays.** See above.

## The thing none of this fixes

$100/month at your eCPM needs roughly **13,700 impressions**, which is about
**1,000–3,000 monthly active users**. You have **12**. Everything above is
worth doing and correct, but revenue is gated on distribution, not on features
or ad configuration. See the notes at the bottom of
`store-assets/google-play/listing-text.md`.

# Pick up here

Short notes for resuming work on Hi-Lo Blackjack Trainer. Last updated
**2026-10-02**. The long version, with every bug and design decision, is
`HANDOVER.md`.

## Where things stand

- **Version `1.5.0+14`** (UX and presentation pass on top of 1.4). The signed
  release bundle builds: `build/app/outputs/bundle/release/app-release.aab`.
  Not uploaded.
- **Git:** `main` = GitHub holds 1.4 (`0bbec28`, `807cfca`). The 1.5 work is
  committed on branch **`ux-polish-1.5`, not pushed**.
- `flutter test` → **654 passing**. `flutter analyze` → 0 errors, 0 warnings.
- **Supabase is fully set up** (checked by Codex 2026-10-01): the accuracy
  league, the Hi-Lo Daily board and the weekly Survival board are live, and
  anonymous writes are refused. No SQL is waiting.

## What 1.5 changes (UX and presentation only)

The brief: no change to blackjack rules, strategy math, the Supabase schema,
the online protocol, ads or rewarded flows, or routes.

- **Home:** one "Hi-Lo Blackjack Trainer" lockup whose BLACKJACK wordmark
  never wraps (it scales down instead); the player's name and avatar; and a
  **Today's next step** card above the fold, picked by
  `lib/features/lobby/next_step.dart` (first hand → today's Daily → the hand
  they keep missing → their weakest chart category → the running count →
  Survival).
- **One identity:** the name is set once (`lib/features/profile/`) and stored
  where online tables already read it, so tables, leaderboards and shared
  challenges all use it. The avatar colour is a fixed hash of the name — the
  same on every device with nothing new on the wire.
- **Practice Setup** (`lib/features/lobby/practice_setup.dart`) replaces the
  old settings list: table rules, shoe ("Continuous shuffle", not "C.S."),
  hands, counting and coaching in one sheet; the home card shows the active
  rules at a glance.
- **After a table session** a report shows accuracy, the one mistake to fix
  and the drill for it (`session_report.dart`); Hi-Lo results end with a
  next-drill button too.
- **Achievements and records** show the next unlock with a progress bar and
  one button (`hilo_goals.dart`) instead of a grid of locks.
- **Accents** (`AppColors`): blue = drills, violet = friends/social,
  mint = right, red = mistakes. The table coach's correction is now red.
- **Online:** five players fit on one screen (three seats to a row); the turn
  badge says PLAYING on someone else's seat instead of YOUR TURN; a ten-letter
  room code shrinks instead of overflowing on a 320 dp phone.
- **Fixed on a real device:** tall bottom sheets ran under the status bar
  (`useSafeArea`); the Hi-Lo question dim now covers the status bar too.
- **Fixed in the release build:** the Daily reminder could be switched on
  once but never off or rescheduled ("Missing type parameter" — R8 stripped
  what Gson needs), and would have crashed in the background when it fired
  or after a reboot. `android/app/proguard-rules.pro` fixes it.
- **Home keeps up:** the next-step card refreshes whenever the home screen is
  back on top or the app is reopened, not only after screens it opened
  itself (it said "Play your first hand" after the intro's first hand).

**Tests:** `test/home_ux_test.dart` (next step, report, identity, goals, and
every new screen at 320/360/390/412 dp — no clipped text, no mid-word breaks,
no overlapping controls; the checks live in `test/support/layout_checks.dart`
and test themselves) and `test/online_full_table_test.dart`.

**Store screenshots:** seven real captures at 1080 x 1920 are in
`store-assets/google-play/screenshots/hilo-1080x1920/` with captions in its
README. To reshoot: boot a 1080 x 1920 emulator and run
`python3 tool/capture_store_screenshots.py <out_dir>`
(`integration_test/store_screenshots_test.dart` seeds a believable player and
plays to each moment).

## What 1.4 adds

**Hi-Lo Training** (lobby button, and a tile in the Training Center). A
dealer deals real rounds; at a random card it stops and asks for the running
count.

- **Modes:**
  - *Daily Challenge:* the same shoe for everyone, one ranked try, and a
    shared leaderboard.
  - *Survival:* lives and levels, with a weekly leaderboard.
  - *Duel:* pass-and-play on one phone.
  - *Practice:* optionally asks for the true count too.
- **Friend challenge codes:** a share message carries a code that deals the
  same shoe. The friend can paste the whole message into the app.
- **Optional Daily reminder:** off by default, and asks for notification
  permission when switched on. Only one reminder is ever pending, so a player
  who stops playing gets one nudge, not a daily one.
- **Screen stays on** during a game; it is allowed to sleep when paused,
  finished or in the background.
- **Code and tests:** everything lives in `lib/features/hilo_training/`. Tests
  are in `test/hilo_training_test.dart`, `hilo_training_widget_test.dart`,
  `hilo_training_extras_test.dart` and `hilo_boards_test.dart`.

## Do next (in order)

1. **Merge and push.**
   ```bash
   git checkout main && git merge ux-polish-1.5 && git push
   ```
2. **Turn on the challenge link page.** Optional, but it makes shared
   challenges one tap.
   - **Publish:** GitHub → repo *Blackjack* → Settings → Pages → *Deploy from
     a branch* → `main`, folder `/docs`. After a minute this works:
     `https://tom1581.github.io/Blackjack/challenge/?c=7Q2M-KD9X-A4F`
   - **Build with the link:**
     ```bash
     flutter build appbundle --release \
       --dart-define=HILO_CHALLENGE_PAGE=https://tom1581.github.io/Blackjack/challenge/
     ```
   - *Until then:* shared messages leave the link out, and friends paste the
     message into the app instead. That always works.
3. **Upload the AAB** in Play Console → Production.
   - *Store listing:* paste the text from
     `store-assets/google-play/listing-text.md`. It is within Play's limits.
   - *Screenshots:* replace the phone screenshots with the seven in
     `store-assets/google-play/screenshots/hilo-1080x1920/`, in file order.
     Keep the feature graphic.
   - *Data safety:* nothing new to declare. The reminder is a local
     notification and sends no data anywhere.
4. **Play on a real phone.** The release build has been run on an Android 15
   emulator (2026-10-02): the table, Hi-Lo Training, live leaderboards, and
   the Daily reminder — switched on, off and on, fired at its hour, tapped
   (it opens Hi-Lo Training) and kept through a reboot. Still worth doing on
   a real phone:
   - **Screen-on:** pick *Rarely* at *Relaxed* pace and don't touch the phone
     for a minute. The screen must stay on.
   - **Challenge link:** with the page live, send yourself a challenge, open
     the link in Chrome and tap *Open in the app*.
   - **Back gesture:** back out of a ranked Daily — it must ask first.

## Still open

**Only you can do these (console work):**

- AdMob payment setup: address PIN, tax and payment method (HANDOVER A2).
- The Play Data Safety form and privacy policy for the advertising ID
  (HANDOVER A6).
- Optional: `app-ads.txt` (HANDOVER A7).
- About two weeks after release, check AdMob → Reports by ad unit. Decide
  whether showing an interstitial every 5 hands (rather than every 3) paid
  off. Background is in `MONETIZATION.md`.

**Not built, on purpose:**

- **Single-deck tables.** They need their own chart and index numbers,
  verified the same way as the others (see "How to check things" below).
- **Resplitting aces.** `RuleSet.resplitAces` exists, but no table enables
  it and the engine skips the resplit.
- **Index plays for 2-deck games.** The numbers are different; only 4+ deck
  shoes use index plays.
- **iOS.** There's no AdMob setup for iOS (HANDOVER B4). The Daily reminder
  also has no iOS wiring: AppDelegate would need the notification-center
  delegate. Challenge links have their URL scheme in `Info.plist`, but that
  has never been tested.
- **Verified https app links.** The challenge page hands off with an
  `intent://` link instead. That needs no `assetlinks.json` and no signing-key
  fingerprint.
- **Analytics and crash reporting.** Deliberately not added yet (HANDOVER B0).

**Ideas for more players (the real bottleneck is reach, not features):**

- Translations of the store listing. This is the cheapest reach lever and is
  still unused.
- A score that can't be faked. Every leaderboard, the Hi-Lo boards included,
  trusts what the app sends within plausibility checks. Only a server-side
  dealer can fix that.

## How to check things

| What | Command |
| --- | --- |
| All tests | `flutter test` |
| Code checker | `flutter analyze` |
| Release build | `flutter build appbundle --release` |
| Every strategy chart cell | `flutter test test/strategy_reference_test.dart` |
| Re-derive chart cells independently | `cd tool/strategy_check && python3 crosscheck_cells.py` (slow, about 30 minutes) |
| Accuracy-league SQL cases | see the header of `tool/sql_checks/weekly_accuracy_check.sql` (needs Docker) |
| Hi-Lo leaderboard SQL cases | see the header of `tool/sql_checks/hilo_boards_check.sql` (needs Docker) |
| Online multiplayer against the real server | `flutter test test/live/live_table_check.dart` |

## Traps we already hit (don't repeat them)

- **Hidden cards:** `HandModel.value` counts the face-down hole card.
  Anything shown to a player must use `visibleValue`.
- **Stale Riverpod values:** don't read a derived provider inside a
  `ref.listen` callback; it can still hold the old value.
- **Layout tests need real fonts.** They must load Roboto
  (`test/support/real_fonts.dart`). The default test font is about twice as
  wide and reports overflows no phone would show.
- **Flushing Riverpod in widget tests:** use
  `tester.pump(const Duration(milliseconds: 1))`. A bare `pump()` doesn't
  fire Riverpod's zero-duration timer.
- **Page transitions take 800 ms** in this Flutter version. Widget tests
  must pump at least 900 ms after a push. A pushed route also spends its
  first frame offstage.
- **`Stopwatch` runs on real time,** even under the widget tester's fake
  clock.
- **Roboto has no "→" glyph.** It renders as a box in the app (fine in
  shared text and on the web page).
- **Never put the challenge code in a `code` query parameter.**
  supabase_flutter treats any incoming link with `?code=` as a sign-in
  callback. Challenge links carry it in the path.
- **Formatting:** never run `dart format` on whole folders. It rewrites
  untouched files. (This happened twice; both times it had to be undone with
  `git checkout`.)
- **Widget tests have no status bar and short room codes.** Two bugs only
  showed on the emulator: bottom sheets running under the status bar, and a
  real ten-letter room code overflowing the header at 320 dp (tests used
  five letters). Check new screens with the screenshot run, not only tests.
- **Release builds shrink code with R8.** Anything that serialises with
  reflection (Gson in the notifications plugin) can work in debug and fail in
  release. Try new native features in `flutter build apk --release` on a
  device, not only in debug.
- **Strategy data:** change the reference charts or index numbers only from
  a verified source, then re-run the reference test. Never from memory.

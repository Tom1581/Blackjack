# Pick up here

Short notes for resuming work on Hi-Lo Blackjack Trainer. Last updated
**2026-10-02**. The long version, with every bug and design decision, is
`HANDOVER.md`.

## Where things stand

- **Version `1.4.0+13`.** The signed release bundle builds:
  `build/app/outputs/bundle/release/app-release.aab` (50.4 MB). Not uploaded.
- **Git:** 1.4 is committed on branch `hilo-training-1.4` and **not pushed**.
  `main` (= GitHub) holds `055e9b3 1.3.1`, which Codex pushed with the Hi-Lo
  leaderboards.
- `flutter test` → **601 passing**. `flutter analyze` → 0 errors, 0 warnings
  (95 style notes, all older than this work).
- **Supabase is fully set up** (checked by Codex 2026-10-01): the accuracy
  league, the Hi-Lo Daily board and the weekly Survival board are live, and
  anonymous writes are refused. No SQL is waiting.

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
   git checkout main && git merge hilo-training-1.4 && git push
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
     `store-assets/google-play/listing-text.md`. It is within Play's limits,
     and the shot list for new screenshots is at the bottom of that file.
   - *Data safety:* nothing new to declare. The reminder is a local
     notification and sends no data anywhere.
4. **Play on a real phone.** The new pieces have only run in tests:
   - **Reminder:** switch it on, allow notifications, set the hour a few
     minutes ahead (or change the phone's clock), close the app and wait.
     Tapping the reminder should open Hi-Lo Training. Then reboot and check it
     is still scheduled.
   - **Screen-on:** pick *Rarely* at *Relaxed* pace and don't touch the phone
     for a minute. The screen must stay on.
   - **Challenge link:** with the page live, send yourself a challenge, open
     the link in Chrome and tap *Open in the app*.
   - **Android 12L or later:** the notifications plugin's docs mention old
     reports of a crash with desugaring on 12L+. Launch the app once on such
     a phone.
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
- **Strategy data:** change the reference charts or index numbers only from
  a verified source, then re-run the reference test. Never from memory.

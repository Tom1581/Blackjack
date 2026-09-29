# Pick up here

Short notes for resuming work on Hi-Lo Blackjack Trainer. Last updated
**2026-09-29**. The long version, with every bug and design decision, is
`HANDOVER.md` → "What is built, and what is next".

## Where things stand

- **Version `1.3.0+11`**, built but **not uploaded**. The release bundle is at
  `build/app/outputs/bundle/release/app-release.aab` (49.6 MB).
- **Nothing from the last two work sessions is committed.** Every change is
  still in the working tree (`git status`), on `main`. Last commit is
  `e56b27f Prepare 1.1.5 online trainer release`.
- `flutter test` → **489 passing**, five clean full runs in a row.
  `flutter analyze` → 0 errors, 0 warnings (95 style "info" notes, all older
  than this work).
- Live checks on 2026-09-29: the weekly rankings table is live, anonymous
  sign-in is on, and real players are on the board.

## What was done

**Session 1 (2026-09-28): audit, 13 bugs fixed.** The worst ones:

- The dealer's badge showed the hole card's total.
- A dealer ace plus a player blackjack threw an error.
- Changing rules mid-hand deleted the bet.
- The first rules change after launch never reached the dealer.
- The Stats screen always showed zero.
- Reshuffles were silent.

Also added in that session: the Training Center, count-check quiz, discard
tray, rebet button and strategy chart.

**Session 2 (2026-09-29): the roadmap, finished.**

- A 2-deck strategy chart.
- Late surrender, with two new tables.
- Index plays (Illustrious 18 / Fab 4), at the table and as a drill.
- A bet spread coach.
- An accuracy league on the leaderboard.
- The table now fits short phones.

## Do next (in this order)

1. **Commit.** Suggested message: "1.3.0: audit fixes, Training Center,
   2-deck chart, surrender, index plays, bet coach, accuracy league".
2. **Apply the accuracy-league database change.** In Supabase → SQL Editor,
   run `supabase/migrations/20260929000000_weekly_accuracy.sql`. It is safe
   with the current live app. Check it worked:
   ```bash
   curl -s "https://yktyobprlradqtvmqfki.supabase.co/rest/v1/weekly_rankings?select=decisions&limit=1" \
     -H "apikey: sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm"
   ```
   The answer should be `[]` or rows. Before the change it answers
   `42703 ... does not exist`. Until then the Accuracy tab says "being set
   up" and everything else works.
3. **Upload the AAB** in Play Console → Production. If `1.2.0+10` was never
   uploaded, skip it and upload `1.3.0+11`.
4. **Refresh the store listing.** The title, description and release notes
   in `store-assets/google-play/listing-text.md` are ready and within Play's
   limits. The screenshots are stale. Shoot these:
   - the Training Center
   - a surrender table (five buttons)
   - the strategy chart
   - the Accuracy tab
5. **Play on a real phone** for a few rounds. So far the new screens have
   only been checked with rendered screenshots, never on a device. Try:
   - surrender
   - index plays on, with the count display hidden
   - the bet coach
   - a reshuffle

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
- **iOS.** No AdMob setup for iOS (HANDOVER B4).
- **Analytics and crash reporting.** Deliberately not added yet (HANDOVER B0).

**Ideas for more players (the real bottleneck is reach, not features):**

- Translations of the store listing. This is the cheapest reach lever and is
  still unused.
- A score that can't be faked. The leaderboard trusts whatever the app sends;
  only a server-side dealer can fix that (see the memory notes on Supabase
  open items).

## How to check things

| What | Command |
| --- | --- |
| All tests | `flutter test` |
| Code checker | `flutter analyze` |
| Release build | `flutter build appbundle --release` |
| Every strategy chart cell | `flutter test test/strategy_reference_test.dart` |
| Re-derive chart cells independently | `cd tool/strategy_check && python3 crosscheck_cells.py` (slow, about 30 minutes) |
| Accuracy-league SQL cases | see the header of `tool/sql_checks/weekly_accuracy_check.sql` (needs Docker) |
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
- **Formatting:** never run `dart format` on whole folders. It rewrites
  untouched files.
- **Strategy data:** change the reference charts or index numbers only from
  a verified source, then re-run the reference test. Never from memory.

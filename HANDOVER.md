# Handover — what is left, and who can actually do it

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

**Done since the review:** selectable table rules (`RuleSet`) with the strategy
chart recalculated per table, the action buttons gated on the table's actual
doubling and splitting rules, and online tables defaulting to invite-only.

**Next, in order:**

1. **Per-category mastery** — record every decision by hand type (hard / soft /
   pair), dealer up-card and rule set, rather than one global accuracy number.
   This had to wait for `RuleSet`, since "correct" depends on the table.
2. **Weak-hand drills** generated from the player's own mistakes, plus separate
   Hard Totals, Soft Totals, Pairs and Speed Round drills.
3. **Single and double deck charts.** Not offered today on purpose — they are
   genuinely different from the multi-deck chart, and shipping them against the
   multi-deck one would teach the wrong play.
4. **Late surrender.** Modelled in `RuleSet` but no preset enables it, because
   the table has no surrender action yet. It needs an engine action, a button
   in both UIs, and a new result type — half-adding it would be worse than not
   having it.
5. **Counting curriculum** — count-down drills, true-count maths, and a clearly
   labelled index-deviation set after basic strategy is solid.
6. **Accuracy league** alongside the profit league. Accuracy is harder to fake
   and matches what the app claims to teach.

## The thing none of this fixes

$100/month at your eCPM needs roughly **13,700 impressions**, which is about
**1,000–3,000 monthly active users**. You have **12**. Everything above is
worth doing and correct, but revenue is gated on distribution, not on features
or ad configuration. See the notes at the bottom of
`store-assets/google-play/listing-text.md`.

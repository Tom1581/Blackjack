# Monetization — what is built, and what only you can do

Last updated 2026-08-25. Read part 2 first if you just want the to-do list.

---

## 1. What is already built

### Rewarded ads (the money)

Two opt-in placements. Both check `AdService.rewardedReady` **before** offering
an ad, and both do something sensible when no ad is loaded — no button ever
promises an ad it cannot show.

| Placement | Where | No ad available? |
| --- | --- | --- |
| Out of chips → +$500 | `BrokeModal` | Grants the chips and relabels to "GET $500 CHIPS" |
| Double the daily bonus | `_DailyStreakCard` in the lobby | Button is hidden entirely |

Closing an ad early earns nothing — that is what "rewarded" means — but the
broke modal keeps the offer open and explains, so an empty bankroll is never a
dead end.

### The wasted-fill fix (the leak)

AdMob was reporting **146 requests for 13 impressions — about a 9% show rate**.
Cause: an interstitial was fetched on *every app open*, while one was only
shown every third finished hand, so most sessions fetched an ad that expired
unseen.

Now (`AdCadence`):

- nothing is fetched at launch;
- an interstitial is fetched **one hand before** it is needed;
- interstitials show every **5** finished hands, not 3 — rewarded ads carry the
  revenue now, and interstitials cost retention every time they interrupt.
- if that warm-up request has no fill, the placement is skipped and the next
  five-hand cycle begins; the app never retries on every subsequent hand.

`test/ads_test.dart` replays a 200-hand session and asserts the fetch:show
ratio stays at or below 1.1.

### The old fake ad is gone

`BrokeModal._watchAd` used to be a 2.2-second `Timer` that granted chips and
showed **no ad at all**. That is why "asking users to watch ads" earned nothing.

---

## 2. What only you can do

### 2.1 Create the Rewarded ad unit — REQUIRED, nothing earns without it

I cannot create ad units; they live in your AdMob console.

1. AdMob → **Apps** → *Hi-Lo Blackjack Trainer* → **Ad units** → **Add ad unit**
2. Choose **Rewarded**. Name it something like `hilo-rewarded-chips`.
3. Reward: amount `500`, item `chips` (cosmetic — the app grants its own).
4. Copy the unit id (looks like `ca-app-pub-1653382608147355/1234567890`).

Then either paste it into `lib/core/ads/ad_service.dart`:

```dart
static const androidRewardedUnitId = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: 'ca-app-pub-1653382608147355/YOUR_UNIT_ID',   // <- here
);
```

…or pass it at build time and leave the code alone:

```bash
flutter build appbundle --release \
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-1653382608147355/YOUR_UNIT_ID
```

**Until this is set, both rewarded placements still work — they just grant the
reward without an ad and earn $0.** Nothing breaks; it simply does not pay.
Debug builds always use Google's test unit, so you can try the flow right now.

### 2.2 Finish AdMob payment setup — REQUIRED before any payout

AdMob will not pay at $100 unless all of this is done. Check
**Payments → Settings**:

- [ ] Address verified (Google mails a PIN; it can take weeks — start now)
- [ ] Tax information submitted
- [ ] Payment method added
- [ ] Payment threshold confirmed ($100 by default)

Unpaid earnings **roll over and are not lost** — your $1.60 keeps accumulating.

### 2.3 Publish `app-ads.txt`

Needs a website listed on your Play Store entry. Put a file at
`https://yourdomain.com/app-ads.txt` containing the line AdMob gives you under
**Apps → app-ads.txt**. It tells advertisers your inventory is genuine; some
demand will not bid without it.

### 2.4 Verify on a real device

The emulator will not tell you whether live ads fill.

```bash
flutter build apk --release \
  --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-.../...
```

Install it, play until you are out of chips, and confirm a real ad plays and
the chips arrive afterwards. Watch for `Rewarded failed to load` in `logcat`.

### 2.5 iOS is not wired up

`ios/Runner/Info.plist` currently carries **Google's sample app id**
(`ca-app-pub-3940256099942544~1458002511`), not yours, and `AdMobIds` only
serves ads on Android:

```dart
static bool get _supported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
```

If you ship iOS, someone needs to: register the iOS app in AdMob, put the real
`GADApplicationIdentifier` in `Info.plist`, add iOS interstitial and rewarded
unit ids, and widen `_supported`.

### 2.6 Still outstanding from the leaderboard work

- [ ] Run `supabase/migrations/20260825000000_weekly_rankings.sql` in the SQL Editor
- [ ] Enable **Authentication → Providers → Anonymous sign-ins**

Verified 2026-08-25: the table still returns HTTP 404, so weekly rankings are
falling back to a board of one.

---

## 3. What this is realistically worth

Better placement and a working rewarded ad should meaningfully raise revenue
**per user**. It does not change the arithmetic:

| | |
| --- | --- |
| Your eCPM | ~$7.28 — this is fine, it was never the problem |
| Impressions needed for $100/month | ~13,700 |
| Monthly actives that implies | **roughly 1,000–3,000** |
| Monthly actives today | **12** |

There is no ad configuration that turns 12 users into $100 a month. Do the
steps above because they are correct and cheap, then put the effort into
distribution — see the notes in `store-assets/google-play/listing-text.md`.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/ads/ad_service.dart';
import 'package:blackjack_app/core/progress/daily_streak.dart';

void main() {
  group('Interstitial cadence', () {
    test('an ad is shown only once every few hands', () {
      for (var hand = 1; hand < AdCadence.handsBetweenInterstitials; hand++) {
        expect(AdCadence.shouldShow(hand), isFalse, reason: 'hand $hand');
      }
      expect(
        AdCadence.shouldShow(AdCadence.handsBetweenInterstitials),
        isTrue,
      );
    });

    test('the ad is fetched shortly before it is needed, not at launch', () {
      // The old build loaded on every app open, so most fetches expired
      // unseen. Nothing should be fetched during the early hands.
      for (var hand = 1;
          hand < AdCadence.handsBetweenInterstitials - AdCadence.preloadLead;
          hand++) {
        expect(AdCadence.shouldPreload(hand), isFalse, reason: 'hand $hand');
      }
      expect(
        AdCadence.shouldPreload(
            AdCadence.handsBetweenInterstitials - AdCadence.preloadLead),
        isTrue,
      );
    });

    test('a long session fetches roughly one ad per ad shown', () {
      // This is the regression that matters: AdMob reported 146 requests for
      // 13 impressions — about a 9% show rate — because ads were fetched and
      // never displayed. Replay the real control flow and hold the ratio near
      // one.
      var loads = 0;
      var shows = 0;
      var handsSinceAd = 0;
      var cached = false;

      for (var hand = 0; hand < 200; hand++) {
        handsSinceAd++;
        if (!AdCadence.shouldShow(handsSinceAd)) {
          if (AdCadence.shouldPreload(handsSinceAd) && !cached) {
            loads++;
            cached = true;
          }
          continue;
        }
        if (!cached) {
          loads++;
          cached = true;
          continue; // counter is deliberately not reset
        }
        shows++;
        cached = false;
        handsSinceAd = 0;
      }

      expect(shows, greaterThan(30));
      expect(loads / shows, lessThanOrEqualTo(1.1),
          reason: 'fetching far more ads than are shown is what wasted fill');
    });

    test('a session too short to earn an ad fetches nothing at all', () {
      var loads = 0;
      for (var hand = 1;
          hand < AdCadence.handsBetweenInterstitials - AdCadence.preloadLead;
          hand++) {
        if (AdCadence.shouldPreload(hand)) loads++;
      }
      expect(loads, 0,
          reason: 'most sessions are short — they should cost no fill');
    });

    test('a failed load does not cause a request on every hand', () {
      // No inventory must be treated as one missed placement, not retried on
      // every hand after the show threshold. This protects request quality
      // during a low-fill period.
      var loads = 0;
      var handsSinceAd = 0;
      var attemptedThisCycle = false;

      for (var hand = 0; hand < 200; hand++) {
        handsSinceAd++;
        if (AdCadence.shouldPreload(handsSinceAd) && !attemptedThisCycle) {
          loads++;
          attemptedThisCycle = true;
        }
        if (AdCadence.shouldShow(handsSinceAd)) {
          handsSinceAd = 0;
          attemptedThisCycle = false;
        }
      }

      expect(loads, 40);
    });
  });

  group('Ad units', () {
    test('the rewarded unit is separate from the interstitial one', () {
      expect(
        AdMobIds.androidRewardedUnitId,
        isNot(AdMobIds.androidInterstitialUnitId),
      );
    });

    test('the rewarded unit is configured', () {
      // An empty unit is not a crash, which is exactly why it needs a test:
      // both rewarded placements quietly fall back to granting their reward
      // with no ad, and all rewarded revenue silently becomes zero.
      expect(
        AdMobIds.androidRewardedUnitId,
        isNotEmpty,
        reason: 'blanking this disables every rewarded placement',
      );
      expect(AdMobIds.androidRewardedUnitId, startsWith('ca-app-pub-'));
    });
  });

  group('Doubling the daily bonus', () {
    var clock = DateTime(2026, 9, 1, 10);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      clock = DateTime(2026, 9, 1, 10);
      DailyStreak.now = () => clock;
    });

    tearDown(DailyStreak.resetForTest);

    test('there is nothing to double before the bonus is claimed', () async {
      expect((await DailyStreak.read()).canDouble, isFalse);
      expect(await DailyStreak.claimDouble(), 0);
    });

    test('doubling pays the same again', () async {
      final claimed = await DailyStreak.claim();
      final state = await DailyStreak.read();
      expect(state.canDouble, isTrue);

      expect(await DailyStreak.claimDouble(), claimed);
      final after = await DailyStreak.read();
      expect(after.doubledToday, isTrue);
      expect(after.canDouble, isFalse);
    });

    test('it cannot be doubled twice', () async {
      await DailyStreak.claim();
      await DailyStreak.claimDouble();
      expect(await DailyStreak.claimDouble(), 0);
    });

    test('tomorrow the offer comes back', () async {
      await DailyStreak.claim();
      await DailyStreak.claimDouble();

      final next = clock.add(const Duration(days: 1));
      clock = DateTime(next.year, next.month, next.day, 10);

      final tomorrow = await DailyStreak.read();
      expect(tomorrow.doubledToday, isFalse);
      expect(tomorrow.canDouble, isFalse, reason: 'claim it first');

      final claimed = await DailyStreak.claim();
      expect((await DailyStreak.read()).canDouble, isTrue);
      expect(await DailyStreak.claimDouble(), claimed);
    });

    test('the double scales with the streak, like the claim does', () async {
      for (var day = 0; day < 4; day++) {
        final claimed = await DailyStreak.claim();
        expect(await DailyStreak.claimDouble(), claimed,
            reason: 'day ${day + 1} doubles day ${day + 1}');
        final next = clock.add(const Duration(days: 1));
        clock = DateTime(next.year, next.month, next.day, 10);
      }
    });
  });
}

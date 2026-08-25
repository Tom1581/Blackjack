import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/reviews/review_prompter.dart';
import 'package:blackjack_app/core/supabase/supabase_service.dart';

void main() {
  group('Start-up survives a backend that will not come up', () {
    setUp(AppSupabase.resetForTest);
    tearDown(AppSupabase.resetForTest);

    test('a failing connect disables online play instead of the app', () async {
      AppSupabase.initializer = () async => throw StateError('no key');

      // The whole point: this must not throw. It used to run unguarded in
      // main() ahead of runApp(), so a failure here meant an install that
      // could never register a first open.
      final ok = await AppSupabase.tryInitialize();

      expect(ok, isFalse);
      expect(AppSupabase.isReady, isFalse);
      expect(AppSupabase.lastError, isA<StateError>());
    });

    test('a hanging connect times out rather than stalling the launch',
        () async {
      AppSupabase.initializer = () => Completer<void>().future;

      final ok = await AppSupabase.tryInitialize(
        timeout: const Duration(milliseconds: 50),
      );

      expect(ok, isFalse);
      expect(AppSupabase.isReady, isFalse);
    });

    test('a successful connect enables online play', () async {
      AppSupabase.initializer = () async {};
      expect(await AppSupabase.tryInitialize(), isTrue);
      expect(AppSupabase.isReady, isTrue);
      expect(AppSupabase.lastError, isNull);
    });

    test('a second call is a no-op once connected', () async {
      var calls = 0;
      AppSupabase.initializer = () async => calls++;
      await AppSupabase.tryInitialize();
      await AppSupabase.tryInitialize();
      expect(calls, 1);
    });

    test('retrying after a failure can succeed', () async {
      AppSupabase.initializer = () async => throw StateError('offline');
      expect(await AppSupabase.tryInitialize(), isFalse);

      AppSupabase.initializer = () async {};
      expect(await AppSupabase.tryInitialize(), isTrue);
      expect(AppSupabase.lastError, isNull);
    });
  });

  group('The rating prompt only asks when it has earned it', () {
    var asks = 0;
    late DateTime clock;

    setUp(() {
      asks = 0;
      clock = DateTime(2026, 9, 1);
      SharedPreferences.setMockInitialValues({});
      ReviewPrompter.requester = () async => asks++;
      ReviewPrompter.now = () => clock;
    });

    tearDown(ReviewPrompter.resetForTest);

    /// Play [count] winning rounds.
    Future<void> win(int count) async {
      for (var i = 0; i < count; i++) {
        await ReviewPrompter.onRoundFinished(100);
      }
    }

    test('it stays quiet through the early rounds', () async {
      await win(ReviewPrompter.milestones.first - 1);
      expect(asks, 0);
      expect(await ReviewPrompter.roundsPlayed(), 19);
    });

    test('it asks once the player has really played', () async {
      await win(ReviewPrompter.milestones.first);
      expect(asks, 1);
    });

    test('it never asks after a losing round', () async {
      for (var i = 0; i < 40; i++) {
        await ReviewPrompter.onRoundFinished(-100);
      }
      expect(asks, 0, reason: 'nobody rates an app right after busting out');
      expect(await ReviewPrompter.roundsPlayed(), 40,
          reason: 'the round still counts toward the milestone');
    });

    test('a push is not a good moment either', () async {
      for (var i = 0; i < 40; i++) {
        await ReviewPrompter.onRoundFinished(0);
      }
      expect(asks, 0);
    });

    test('it does not ask again the very next round', () async {
      await win(ReviewPrompter.milestones.first + 20);
      expect(asks, 1);
    });

    test('a later milestone only counts once the gap has passed', () async {
      await win(ReviewPrompter.milestones[1]);
      expect(asks, 1, reason: 'too soon after the first ask');

      clock = clock.add(ReviewPrompter.minGap + const Duration(days: 1));
      await win(1);
      expect(asks, 2);
    });

    test('it gives up after the last milestone', () async {
      for (final _ in ReviewPrompter.milestones) {
        clock = clock.add(ReviewPrompter.minGap + const Duration(days: 1));
        await win(ReviewPrompter.milestones.last);
      }
      expect(asks, ReviewPrompter.milestones.length);

      clock = clock.add(const Duration(days: 400));
      await win(50);
      expect(asks, ReviewPrompter.milestones.length,
          reason: 'three asks over a lifetime is the whole budget');
    });

    test('a review sheet that fails to open is not the player\'s problem',
        () async {
      ReviewPrompter.requester = () async => throw StateError('no store');
      await win(ReviewPrompter.milestones.first); // must not throw
      expect(await ReviewPrompter.roundsPlayed(),
          ReviewPrompter.milestones.first);
    });
  });
}

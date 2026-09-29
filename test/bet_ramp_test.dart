// The bet-spread coach: the ramp itself, the check at the deal, the betting
// panel line, and the settings that drive it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/progress/player_stats.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/bet_ramp.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';

class _Seeded extends TableNotifier {
  _Seeded(this.seed);
  final GameState seed;

  @override
  GameState build() {
    super.build();
    return seed;
  }
}

GameState _betting({required double tc, int bet = 0}) => GameState(
      bankroll: 5000,
      spotBets: [bet],
      currentBet: bet,
      trueCount: tc,
      runningCount: (tc * 5).round(),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablePrefs.resetForTest();
    StrategyCoach.resetForTest();
  });

  group('The ramp', () {
    test('one unit up to +2, then true count minus one, capped at eight', () {
      expect(BetRamp.units(-4), 1);
      expect(BetRamp.units(0), 1);
      expect(BetRamp.units(2.9), 1);
      expect(BetRamp.units(3), 2);
      expect(BetRamp.units(3.9), 2, reason: 'floored: +3.9 is +3');
      expect(BetRamp.units(4.5), 3);
      expect(BetRamp.units(8.99), 7);
      expect(BetRamp.units(9), 8);
      expect(BetRamp.units(20), BetRamp.maxUnits);
    });

    test('a bet matches only as an exact number of units', () {
      expect(BetRamp.matches(50, 3.2, 25), isTrue);
      expect(BetRamp.matches(25, 3.2, 25), isFalse);
      expect(BetRamp.matches(55, 3.2, 25), isFalse);
      expect(BetRamp.matches(0, 0, 25), isFalse);
      expect(BetRamp.matches(10, -1, 10), isTrue);
    });
  });

  group('The check at the deal', () {
    ProviderContainer container(GameState s, {bool coach = true}) {
      final c = ProviderContainer(overrides: [
        tableProvider.overrideWith(() => _Seeded(s)),
        betCoachProvider.overrideWith((ref) => coach),
        betUnitProvider.overrideWith((ref) => 25),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('a bet off the ramp is named, and recorded', (tester) async {
      final c = container(_betting(tc: 4.1, bet: 25));
      c.read(tableProvider.notifier).deal();
      final message = c.read(strategyFeedbackProvider)?.message ?? '';
      // A dealt natural can replace the note with nothing else; the bet check
      // runs first either way.
      expect(message, contains('calls for 3 units (\$75)'));
      expect(message, contains('you bet \$25'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final stats = await PlayerStatsStore.read();
        expect(stats.betChecks, 1);
        expect(stats.betChecksCorrect, 0);
      });
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a bet on the ramp passes quietly', (tester) async {
      final c = container(_betting(tc: 0.5, bet: 25));
      c.read(tableProvider.notifier).deal();
      expect(c.read(strategyFeedbackProvider)?.message ?? '',
          isNot(contains('Bet check')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((await PlayerStatsStore.read()).betChecksCorrect, 1);
      });
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('with the coach off nothing is checked', (tester) async {
      final c = container(_betting(tc: 6, bet: 25), coach: false);
      c.read(tableProvider.notifier).deal();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect((await PlayerStatsStore.read()).betChecks, 0);
      });
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('The betting panel', () {
    Future<void> pump(WidgetTester tester, {required bool showCount}) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tableProvider.overrideWith(() => _Seeded(_betting(tc: 3.2))),
          betCoachProvider.overrideWith((ref) => true),
          betUnitProvider.overrideWith((ref) => 25),
          showCountProvider.overrideWith((ref) => showCount),
        ],
        child: const MaterialApp(home: TableScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('shows the ramp bet when the count is on screen',
        (tester) async {
      await pump(tester, showCount: true);
      expect(find.text('TC +3.2 → BET 2 UNITS · \$50'), findsOneWidget);
      expect(find.byKey(const ValueKey('bet-ramp-ok')), findsNothing,
          reason: 'nothing bet yet');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ticks the bet once it matches the ramp', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tableProvider
              .overrideWith(() => _Seeded(_betting(tc: 3.2, bet: 50))),
          betCoachProvider.overrideWith((ref) => true),
          betUnitProvider.overrideWith((ref) => 25),
        ],
        child: const MaterialApp(home: TableScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('bet-ramp-ok')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows only the rule when the count is hidden',
        (tester) async {
      await pump(tester, showCount: false);
      final line = tester.widget<Text>(find.byKey(const ValueKey('bet-ramp')));
      expect(line.data, isNot(contains('+3.2')));
      expect(line.data, contains('TRUE COUNT − 1 UNITS'));
      expect(tester.takeException(), isNull);
    });
  });

  test('coach settings survive a restart', () async {
    await TablePrefs.setBetCoach(true);
    await TablePrefs.setBetUnit(10);
    await TablePrefs.setIndexPlays(true);
    TablePrefs.resetForTest();
    await TablePrefs.load();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(betCoachProvider), isTrue);
    expect(c.read(betUnitProvider), 10);
    expect(c.read(indexPlaysProvider), isTrue);
  });

  test('an unknown saved unit falls back to 25', () async {
    SharedPreferences.setMockInitialValues({'table_bet_unit': 7});
    await TablePrefs.load();
    expect(TablePrefs.betUnit, 25);
  });
}

// Widget tests for the coaching surface: the misplay correction and the
// highlighted recommendation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StrategyCoach.resetForTest();
  });

  Future<void> pumpTable(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: TableScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('nothing is said while the player is playing correctly',
      (tester) async {
    await pumpTable(tester);
    expect(find.textContaining('basic strategy says'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a misplay is named, with the hand and the better move',
      (tester) async {
    await pumpTable(tester, overrides: [
      strategyFeedbackProvider.overrideWith(
        (ref) => const StrategyFeedback(
          played: StrategyMove.hit,
          best: StrategyMove.stand,
          handValue: 16,
          handWasSoft: false,
          dealerUp: '5',
        ),
      ),
    ]);

    expect(
      find.text('16 vs 5 — basic strategy says Stand'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a soft hand is called soft, because the play differs',
      (tester) async {
    await pumpTable(tester, overrides: [
      strategyFeedbackProvider.overrideWith(
        (ref) => const StrategyFeedback(
          played: StrategyMove.stand,
          best: StrategyMove.double,
          handValue: 18,
          handWasSoft: true,
          dealerUp: '4',
        ),
      ),
    ]);

    expect(
      find.text('Soft 18 vs 4 — basic strategy says Double'),
      findsOneWidget,
    );
  });

  testWidgets('the correction takes no space when there is nothing to say',
      (tester) async {
    await pumpTable(tester);
    // The bar is always in the tree so the layout does not jump; it should
    // simply be empty.
    expect(find.byIcon(Icons.school_outlined), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('The hint respects the setting', () {
    testWidgets('hints off means no recommendation is computed',
        (tester) async {
      await StrategyCoach.setHintsEnabled(false);
      await pumpTable(tester);
      expect(StrategyCoach.hintsEnabled, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hints on is the default for a trainer', (tester) async {
      await StrategyCoach.load();
      expect(StrategyCoach.hintsEnabled, isTrue);
      await pumpTable(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no recommendation exists before the cards are out',
      (tester) async {
    late WidgetRef captured;
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const TableScreen();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Betting phase: there is no hand to advise on.
    expect(captured.read(strategyHintProvider), isNull);
  });
}

// The table on short and narrow screens, measured with the real fonts: three
// hands, a multi-card hand, and a coaching note must all fit without the
// felt overflowing. The cards shrink to the space rather than spilling.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';
import 'package:blackjack_app/theme/app_theme.dart';

import 'support/real_fonts.dart';

class _Seeded extends TableNotifier {
  _Seeded(this.seed);
  final GameState seed;

  @override
  GameState build() {
    super.build();
    return seed;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await loadRealFonts(), isTrue);
  });

  const nine = CardModel(suit: Suit.spades, rank: Rank.nine);
  const seven = CardModel(suit: Suit.hearts, rank: Rank.seven);
  const two = CardModel(suit: Suit.clubs, rank: Rank.two);

  GameState midRound(int spots) => GameState(
        phase: GamePhase.playerTurn,
        playerHands: [
          for (var i = 0; i < spots; i++)
            const HandModel(cards: [two, seven, two, two], bet: 10),
        ],
        dealerHand: const HandModel(cards: [
          nine,
          CardModel(suit: Suit.clubs, rank: Rank.two, faceUp: false),
        ]),
        bankroll: 123456,
        currentBet: 10 * spots,
        spotBets: [for (var i = 0; i < spots; i++) 10],
        handResults: List<GameResult?>.filled(spots, null),
      );

  const note = StrategyFeedback.note(
    '16 vs 10 at true count +1.2 — the count says Stand '
    '(Illustrious 18 index 0)',
  );

  for (final size in const [
    Size(360, 640),
    Size(360, 600),
    Size(320, 568),
    Size(800, 620),
  ]) {
    for (final spots in [1, 3]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}, '
          '$spots hand(s), surrender table, coaching note', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ProviderScope(
          overrides: [
            tableProvider.overrideWith(() => _Seeded(midRound(spots))),
            rulesProvider.overrideWith((ref) => RuleSet.sixDeckH17Surrender),
            strategyFeedbackProvider.overrideWith((ref) => note),
          ],
          child: MaterialApp(theme: buildAppTheme(), home: const TableScreen()),
        ));
        await tester.pump(const Duration(milliseconds: 800));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in const [Size(360, 600), Size(320, 568)]) {
    testWidgets('${size.width.toInt()}x${size.height.toInt()}, betting with '
        'the bet coach and a new shoe', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tableProvider.overrideWith(() => _Seeded(const GameState(
                bankroll: 5000,
                spotBets: [0, 0, 0],
                lastSpotBets: [25, 25, 25],
                freshShoe: true,
                trueCount: 3.4,
              ))),
          betCoachProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: const TableScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('REBET'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

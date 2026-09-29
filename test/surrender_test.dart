// Late surrender: the engine action, what it pays, when it is allowed, the
// coach's advice, and the table UI.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/engine/game_engine.dart';
import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/progress/player_stats.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/online/online_table_logic.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';

CardModel _c(Rank r, [Suit s = Suit.spades]) => CardModel(suit: s, rank: r);
const _holeSeven =
    CardModel(suit: Suit.hearts, rank: Rank.seven, faceUp: false);

GameState _turn(
  List<HandModel> hands, {
  HandModel dealer = const HandModel(cards: [
    CardModel(suit: Suit.clubs, rank: Rank.king),
    _holeSeven,
  ]),
  InsuranceState insurance = InsuranceState.notOffered,
  int activeHandIndex = 0,
}) =>
    GameState(
      phase: GamePhase.playerTurn,
      playerHands: hands,
      activeHandIndex: activeHandIndex,
      dealerHand: dealer,
      bankroll: 900,
      currentBet: hands.fold<int>(0, (a, h) => a + h.bet),
      spotBets: [for (final h in hands) h.bet],
      handResults: List<GameResult?>.filled(hands.length, null),
      insuranceState: insurance,
    );

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablePrefs.resetForTest();
    StrategyCoach.resetForTest();
  });

  final ls = GameEngine(rules: RuleSet.sixDeckH17Surrender);
  final noLs = GameEngine(rules: RuleSet.sixDeckH17);
  final sixteen = HandModel(cards: [_c(Rank.ten), _c(Rank.six)], bet: 100);

  group('When surrender is allowed', () {
    test('only at a late-surrender table', () {
      expect(ls.canSurrenderActiveHand(_turn([sixteen])), isTrue);
      expect(noLs.canSurrenderActiveHand(_turn([sixteen])), isFalse);
    });

    test('only as the first decision on a dealt two-card hand', () {
      final three = HandModel(
          cards: [_c(Rank.ten), _c(Rank.two), _c(Rank.four)], bet: 100);
      expect(ls.canSurrenderActiveHand(_turn([three])), isFalse);
      final split = sixteen.copyWith(fromSplit: true);
      expect(ls.canSurrenderActiveHand(_turn([split])), isFalse,
          reason: 'no surrender after splitting');
    });

    test('not while the insurance question is open', () {
      expect(
        ls.canSurrenderActiveHand(
            _turn([sixteen], insurance: InsuranceState.offered)),
        isFalse,
      );
      expect(
        ls.canSurrenderActiveHand(
            _turn([sixteen], insurance: InsuranceState.declined)),
        isTrue,
        reason: 'late surrender: after the peek, insurance answered',
      );
    });

    test('never against a dealer blackjack — the peek ends the round first',
        () {
      final engine = GameEngine(rules: RuleSet.sixDeckH17Surrender);
      var peeked = 0;
      for (var i = 0; i < 3000 && peeked < 5; i++) {
        final s = engine.dealInitial(const GameState(
          spotBets: [10],
          currentBet: 10,
          bankroll: 1000,
        ));
        if (s.dealerHand.cards.first.rank.value == 10 &&
            s.dealerHand.isBlackjack) {
          peeked++;
          expect(s.phase, GamePhase.dealerTurn);
          expect(engine.canSurrenderActiveHand(s), isFalse);
        }
        engine.newHand(s);
      }
      expect(peeked, greaterThan(0), reason: 'sanity: sampled a peek');
    });
  });

  group('What surrender pays', () {
    test('half the bet back, and the dealer need not draw for it', () {
      final s = ls.surrender(_turn([sixteen]));
      expect(s.phase, GamePhase.dealerTurn);
      expect(s.playerHands.single.surrendered, isTrue);
      expect(ls.dealerMustPlay(s), isFalse);

      final settled = ls.resolveAll(s.copyWith(
        dealerHand: s.dealerHand.revealAll(),
      ));
      expect(settled.handResults.single, GameResult.surrender);
      expect(settled.roundNet, -50);
      expect(settled.bankroll, 950);
    });

    test('an odd chip is rounded in the player\'s favour', () {
      expect(GameEngine.surrenderRefund(25), 13);
      expect(GameEngine.surrenderRefund(100), 50);
      expect(GameEngine.surrenderRefund(5), 3);
    });

    test('with two hands, surrendering one moves play to the next', () {
      final other = HandModel(cards: [_c(Rank.nine), _c(Rank.two)], bet: 50);
      final s = ls.surrender(_turn([sixteen, other]));
      expect(s.phase, GamePhase.playerTurn);
      expect(s.activeHandIndex, 1);
      expect(ls.dealerMustPlay(s), isTrue, reason: 'hand two is still live');
    });

    test('the flag survives the online wire format, and online pays alike',
        () {
      final back = HandModel.fromJson(sixteen.markSurrendered().toJson());
      expect(back.surrendered, isTrue);
      expect(HandModel.fromJson(sixteen.toJson()).surrendered, isFalse);
      expect(OnlineTableLogic.payout(GameResult.surrender, 25),
          GameEngine.surrenderRefund(25));
    });

    test('stats count a surrender as a loss, and on its own', () async {
      await PlayerStatsStore.recordRound(
        results: const [GameResult.surrender],
        roundNet: -50,
        trueCountAtDeal: 0,
      );
      final stats = await PlayerStatsStore.read();
      expect(stats.surrenders, 1);
      expect(stats.losses, 1);
      expect(stats.hands, 1);
    });
  });

  group('The coach on surrender', () {
    CardModel up(Rank r) => _c(r, Suit.clubs);

    test('surrenders only where the chart does, and only if allowed', () {
      StrategyMove best(HandModel h, Rank u,
              {bool canSurrender = true,
              RuleSet rules = RuleSet.sixDeckH17Surrender}) =>
          BasicStrategy.best(
            hand: h,
            dealerUp: up(u),
            canSurrender: canSurrender,
            rules: rules,
          );
      final h17 = HandModel(cards: [_c(Rank.ten), _c(Rank.seven)]);
      final eights = HandModel(cards: [_c(Rank.eight), _c(Rank.eight)]);

      expect(best(sixteen, Rank.ten), StrategyMove.surrender);
      expect(best(sixteen, Rank.ten, canSurrender: false), StrategyMove.hit);
      expect(best(h17, Rank.ace), StrategyMove.surrender);
      expect(best(h17, Rank.ace, canSurrender: false), StrategyMove.stand);
      expect(best(eights, Rank.ace), StrategyMove.surrender);
      expect(best(eights, Rank.ace, canSurrender: false), StrategyMove.split);
      expect(best(eights, Rank.ten), StrategyMove.split,
          reason: 'eights split against a ten even with surrender');
      expect(
        best(sixteen, Rank.ten, rules: RuleSet.sixDeckH17),
        StrategyMove.hit,
        reason: 'no surrender on a table that does not offer it',
      );
    });
  });

  group('At the table', () {
    Future<ProviderContainer> pump(WidgetTester tester, GameState seed,
        {RuleSet rules = RuleSet.sixDeckH17Surrender}) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(overrides: [
        rulesProvider.overrideWith((ref) => rules),
        tableProvider.overrideWith(() => _Seeded(seed)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TableScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 700));
      return container;
    }

    testWidgets('a surrender table shows the button, and it works',
        (tester) async {
      final c = await pump(tester, _turn([sixteen]));
      expect(find.text('Surrender'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Surrender'));
      await tester.pump();
      expect(c.read(tableProvider).playerHands.single.surrendered, isTrue);
      expect(find.text('SURRENDERED'), findsOneWidget);

      // Pump until the round settles — the result banner deals the next hand
      // on its own a moment later, so do not overshoot.
      for (var i = 0;
          i < 40 && c.read(tableProvider).phase != GamePhase.result;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final s = c.read(tableProvider);
      expect(s.phase, GamePhase.result);
      expect(s.roundNet, -50);
      expect(s.dealerHand.cards, hasLength(2),
          reason: 'nothing left to draw for');
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('surrendering where the chart says to earns no correction',
        (tester) async {
      final c = await pump(tester, _turn([sixteen]));
      await tester.tap(find.text('Surrender'));
      await tester.pump();
      expect(c.read(strategyFeedbackProvider), isNull);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a table without surrender has no button', (tester) async {
      await pump(tester, _turn([sixteen]), rules: RuleSet.sixDeckH17);
      expect(find.text('Surrender'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

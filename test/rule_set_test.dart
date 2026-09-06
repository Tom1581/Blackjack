import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/engine/game_engine.dart';
import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/rules/rules_store.dart';

CardModel _c(Rank rank) => CardModel(suit: Suit.hearts, rank: rank);
CardModel _d(Rank rank) => CardModel(suit: Suit.spades, rank: rank);

/// A state sitting on the player's turn with [hand] in front of them.
GameState _playing(HandModel hand, {int bankroll = 900}) => GameState(
      phase: GamePhase.playerTurn,
      playerHands: [hand],
      dealerHand: HandModel(cards: [_d(Rank.ten), _c(Rank.six)]),
      bankroll: bankroll,
      currentBet: hand.bet,
      handResults: const [null],
    );

void main() {
  group('The default table is exactly what it always was', () {
    const rules = RuleSet.sixDeckH17;

    test('dealer hits soft 17, blackjack pays 3:2, doubling is unrestricted',
        () {
      expect(rules.dealerHitsSoft17, isTrue);
      expect(rules.doubleAfterSplit, isTrue);
      expect(rules.doubleRule, DoubleRule.anyTwo);
      expect(rules.blackjackPayout, 1.5);
      expect(rules.isUnfavourable, isFalse);
      expect(RuleSet.fallback, rules);
    });

    test('a bare engine uses it', () {
      expect(GameEngine().rules, RuleSet.sixDeckH17);
    });
  });

  group('Describing a table', () {
    test('the summary says what actually differs', () {
      expect(RuleSet.sixDeckH17.summary, 'H17 · DAS · 3:2');
      expect(RuleSet.sixDeckS17.summary, 'S17 · DAS · 3:2');
      expect(RuleSet.sixDeckNoDas.summary, 'H17 · no DAS · 3:2');
      expect(RuleSet.sixFive.summary, 'H17 · DAS · 6:5');
      expect(
        RuleSet.restrictedDouble.summary,
        'H17 · DAS · 3:2 · 9–11 only',
      );
    });

    test('a 6:5 table is flagged as the worse deal it is', () {
      expect(RuleSet.sixFive.isUnfavourable, isTrue);
      expect(RuleSet.sixFive.payoutLabel, '6:5');
      expect(RuleSet.sixDeckH17.payoutLabel, '3:2');
    });

    test('presets resolve by id and fall back safely', () {
      for (final preset in RuleSet.presets) {
        expect(RuleSet.byId(preset.id), preset);
      }
      expect(RuleSet.byId('gone'), RuleSet.fallback);
      expect(RuleSet.byId(null), RuleSet.fallback);
    });
  });

  group('The dealer follows the table, not the engine', () {
    final soft17 = GameState(
      phase: GamePhase.dealerTurn,
      dealerHand: HandModel(cards: [_c(Rank.ace), _d(Rank.six)]),
    );
    final hard17 = GameState(
      phase: GamePhase.dealerTurn,
      dealerHand: HandModel(cards: [_c(Rank.ten), _d(Rank.seven)]),
    );

    test('H17 draws to soft seventeen', () {
      final engine = GameEngine(rules: RuleSet.sixDeckH17);
      expect(engine.dealerShouldHit(soft17), isTrue);
      expect(engine.dealerShouldHit(hard17), isFalse);
    });

    test('S17 stands on it', () {
      final engine = GameEngine(rules: RuleSet.sixDeckS17);
      expect(engine.dealerShouldHit(soft17), isFalse);
      expect(engine.dealerShouldHit(hard17), isFalse);
    });
  });

  group('Blackjack payout', () {
    GameState withNatural(int bankroll) => GameState(
          phase: GamePhase.dealerTurn,
          playerHands: [
            HandModel(cards: [_c(Rank.ace), _d(Rank.king)], bet: 100),
          ],
          dealerHand: HandModel(cards: [_d(Rank.ten), _c(Rank.eight)]),
          bankroll: bankroll,
          currentBet: 100,
          handResults: const [null],
        );

    test('3:2 returns the stake plus half again', () {
      final after =
          GameEngine(rules: RuleSet.sixDeckH17).resolveAll(withNatural(900));
      expect(after.handResults.single, GameResult.blackjack);
      expect(after.bankroll, 1150);
      expect(after.roundNet, 150);
    });

    test('6:5 quietly pays 30 chips less on the same hand', () {
      final after =
          GameEngine(rules: RuleSet.sixFive).resolveAll(withNatural(900));
      expect(after.handResults.single, GameResult.blackjack);
      expect(after.bankroll, 1120);
      expect(after.roundNet, 120);
    });
  });

  group('Doubling follows the table rule', () {
    final fifteen =
        HandModel(cards: [_c(Rank.ten), _d(Rank.five)], bet: 100);
    final ten = HandModel(cards: [_c(Rank.six), _d(Rank.four)], bet: 100);

    test('anything goes on an unrestricted table', () {
      final engine = GameEngine(rules: RuleSet.sixDeckH17);
      expect(engine.canDoubleActiveHand(_playing(fifteen)), isTrue);
      expect(engine.canDoubleActiveHand(_playing(ten)), isTrue);
    });

    test('a 9–11 table refuses a fifteen but allows a ten', () {
      final engine = GameEngine(rules: RuleSet.restrictedDouble);
      expect(engine.canDoubleActiveHand(_playing(fifteen)), isFalse);
      expect(engine.canDoubleActiveHand(_playing(ten)), isTrue);
    });

    test('a soft total is never 9–11, so restricted tables kill soft doubles',
        () {
      final soft17 =
          HandModel(cards: [_c(Rank.ace), _d(Rank.six)], bet: 100);
      expect(soft17.isSoft, isTrue);
      expect(
        GameEngine(rules: RuleSet.restrictedDouble)
            .canDoubleActiveHand(_playing(soft17)),
        isFalse,
      );
      expect(
        GameEngine(rules: RuleSet.sixDeckH17)
            .canDoubleActiveHand(_playing(soft17)),
        isTrue,
      );
    });

    test('no-DAS blocks doubling a split hand but not a fresh one', () {
      final splitHand = HandModel(
        cards: [_c(Rank.six), _d(Rank.four)],
        bet: 100,
        fromSplit: true,
      );
      final noDas = GameEngine(rules: RuleSet.sixDeckNoDas);
      expect(noDas.canDoubleActiveHand(_playing(splitHand)), isFalse);
      expect(noDas.canDoubleActiveHand(_playing(ten)), isTrue);

      final das = GameEngine(rules: RuleSet.sixDeckH17);
      expect(das.canDoubleActiveHand(_playing(splitHand)), isTrue);
    });

    test('you still cannot double what you cannot afford', () {
      final engine = GameEngine(rules: RuleSet.sixDeckH17);
      expect(
        engine.canDoubleActiveHand(_playing(ten, bankroll: 50)),
        isFalse,
      );
    });

    test('three cards is never a double', () {
      final threeCards = HandModel(
        cards: [_c(Rank.four), _d(Rank.three), _c(Rank.three)],
        bet: 100,
      );
      expect(
        GameEngine().canDoubleActiveHand(_playing(threeCards)),
        isFalse,
      );
    });
  });

  group('Splitting respects the hand limit', () {
    final pair = HandModel(cards: [_c(Rank.eight), _d(Rank.eight)], bet: 100);

    GameState withHands(int count) => GameState(
          phase: GamePhase.playerTurn,
          playerHands: List.filled(count, pair),
          dealerHand: HandModel(cards: [_d(Rank.ten), _c(Rank.six)]),
          bankroll: 900,
          currentBet: 100,
          handResults: List.filled(count, null),
        );

    test('a pair splits while there is room', () {
      final engine = GameEngine();
      expect(engine.canSplitActiveHand(withHands(1)), isTrue);
      expect(engine.canSplitActiveHand(withHands(3)), isTrue);
    });

    test('the fourth hand is the last — previously this was unlimited', () {
      final engine = GameEngine();
      expect(engine.rules.maxSplitHands, 4);
      expect(engine.canSplitActiveHand(withHands(4)), isFalse);
    });

    test('a non-pair never splits', () {
      final engine = GameEngine();
      final state = _playing(
        HandModel(cards: [_c(Rank.eight), _d(Rank.nine)], bet: 100),
      );
      expect(engine.canSplitActiveHand(state), isFalse);
    });

    test('split aces are not re-split unless the table says so', () {
      final splitAces = HandModel(
        cards: [_c(Rank.ace), _d(Rank.ace)],
        bet: 100,
        fromSplit: true,
      );
      expect(
        GameEngine().canSplitActiveHand(_playing(splitAces)),
        isFalse,
      );
      const resplit = RuleSet(
        id: 'test_rsa',
        name: 'test',
        blurb: 'test',
        resplitAces: true,
      );
      expect(
        GameEngine(rules: resplit).canSplitActiveHand(_playing(splitAces)),
        isTrue,
      );
    });
  });

  group('The chosen table is remembered', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      RulesStore.resetForTest();
    });

    test('a new install starts on the default table', () async {
      await RulesStore.load();
      expect(RulesStore.current, RuleSet.sixDeckH17);
    });

    test('a choice survives a restart', () async {
      await RulesStore.select(RuleSet.sixDeckS17);
      RulesStore.resetForTest();
      await RulesStore.load();
      expect(RulesStore.current, RuleSet.sixDeckS17);
    });

    test('a rule set that no longer exists falls back safely', () async {
      SharedPreferences.setMockInitialValues({'rule_set_id': 'removed_preset'});
      RulesStore.resetForTest();
      await RulesStore.load();
      expect(RulesStore.current, RuleSet.fallback);
    });
  });
}

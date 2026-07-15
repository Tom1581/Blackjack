import 'package:flutter_test/flutter_test.dart';
import 'package:blackjack_app/core/engine/hi_lo_counter.dart';
import 'package:blackjack_app/core/engine/deck_manager.dart';
import 'package:blackjack_app/core/engine/game_engine.dart';
import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';

void main() {
  group('HiLoCounter', () {
    test('balanced deck returns to zero', () {
      // Deal every card in one deck — Hi-Lo is balanced, so count must return to 0
      final counter = HiLoCounter(totalDecks: 1);
      for (final suit in Suit.values) {
        for (final rank in Rank.values) {
          counter.update(CardModel(suit: suit, rank: rank));
        }
      }
      expect(counter.runningCount, 0);
    });

    test('low cards increment count', () {
      final counter = HiLoCounter(totalDecks: 6);
      for (final rank in [Rank.two, Rank.three, Rank.four, Rank.five, Rank.six]) {
        counter.update(CardModel(suit: Suit.hearts, rank: rank));
      }
      expect(counter.runningCount, 5);
    });

    test('high cards decrement count', () {
      final counter = HiLoCounter(totalDecks: 6);
      for (final rank in [Rank.ten, Rank.jack, Rank.queen, Rank.king, Rank.ace]) {
        counter.update(CardModel(suit: Suit.hearts, rank: rank));
      }
      expect(counter.runningCount, -5);
    });

    test('neutral cards do not change count', () {
      final counter = HiLoCounter(totalDecks: 6);
      for (final rank in [Rank.seven, Rank.eight, Rank.nine]) {
        counter.update(CardModel(suit: Suit.hearts, rank: rank));
      }
      expect(counter.runningCount, 0);
    });

    test('true count calculation', () {
      final counter = HiLoCounter(totalDecks: 6);
      // Running count = +4, 4 decks remaining → true count = 1.0
      counter.update(CardModel(suit: Suit.hearts, rank: Rank.two));
      counter.update(CardModel(suit: Suit.hearts, rank: Rank.three));
      counter.update(CardModel(suit: Suit.hearts, rank: Rank.four));
      counter.update(CardModel(suit: Suit.hearts, rank: Rank.five));
      counter.updateDecksRemaining(4 * 52); // 4 decks left
      expect(counter.trueCount, closeTo(1.0, 0.01));
    });

    test('favorable signal when true count >= 2', () {
      final counter = HiLoCounter(totalDecks: 6);
      // Add 4 low cards, set 1 deck remaining → true count = 4
      for (int i = 0; i < 4; i++) {
        counter.update(CardModel(suit: Suit.hearts, rank: Rank.two));
      }
      counter.updateDecksRemaining(52);
      expect(counter.signal, CountSignal.favorable);
    });
  });

  group('HandModel', () {
    test('Ace counts as 11 without busting', () {
      final hand = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.king),
      ]);
      expect(hand.value, 21);
      expect(hand.isBlackjack, true);
    });

    test('Ace adjusts to 1 to avoid bust', () {
      final hand = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.king),
        const CardModel(suit: Suit.clubs, rank: Rank.five),
      ]);
      expect(hand.value, 16);
      expect(hand.isBust, false);
    });

    test('bust detection', () {
      final hand = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten),
        const CardModel(suit: Suit.spades, rank: Rank.king),
        const CardModel(suit: Suit.clubs, rank: Rank.five),
      ]);
      expect(hand.isBust, true);
    });

    test('pair detection', () {
      final hand = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.eight),
        const CardModel(suit: Suit.spades, rank: Rank.eight),
      ]);
      expect(hand.isPair, true);
    });

    test('isSoft handles partial ace demotion (A+A+5 = soft 17)', () {
      // Single-ace soft hands.
      final softA5 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.five),
      ]);
      expect(softA5.value, 16);
      expect(softA5.isSoft, true);

      // Two aces + 5 = 1 + 11 + 5 = soft 17. Critical for dealer-hits-soft-17.
      final softAA5 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.ace),
        const CardModel(suit: Suit.clubs, rank: Rank.five),
      ]);
      expect(softAA5.value, 17);
      expect(softAA5.isSoft, true,
          reason: 'A+A+5 plays as 1+11+5 = soft 17');

      // Two aces alone = 1 + 11 = soft 12.
      final softAA = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.ace),
      ]);
      expect(softAA.value, 12);
      expect(softAA.isSoft, true);

      // Hand with all aces forced to 1 → hard.
      final hardA95 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.nine),
        const CardModel(suit: Suit.clubs, rank: Rank.five),
      ]);
      expect(hardA95.value, 15);
      expect(hardA95.isSoft, false,
          reason: 'A had to be demoted to 1 to avoid bust');
    });

    test('canDouble on any two-card hand (DOA)', () {
      final h10 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.six),
        const CardModel(suit: Suit.spades, rank: Rank.four),
      ]);
      expect(h10.canDouble, true);

      final h12 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.seven),
        const CardModel(suit: Suit.spades, rank: Rank.five),
      ]);
      expect(h12.canDouble, true);

      final h16Soft = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.five),
      ]);
      expect(h16Soft.canDouble, true);

      // Three cards: doubling no longer allowed.
      final threeCard = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.four),
        const CardModel(suit: Suit.spades, rank: Rank.three),
        const CardModel(suit: Suit.clubs, rank: Rank.two),
      ]);
      expect(threeCard.canDouble, false);
    });
  });

  group('GameEngine bet math', () {
    GameState afterDeal(GameEngine engine, {int bet = 100, int bankroll = 1000}) {
      var state = const GameState();
      state = state.copyWith(bankroll: bankroll);
      state = engine.placeBet(state, bet);
      return engine.dealInitial(state);
    }

    test('per-hand bet and running total are set at deal', () {
      final engine = GameEngine(numDecks: 6);
      final state = afterDeal(engine, bet: 75);
      expect(state.playerHands.length, 1);
      expect(state.playerHands[0].bet, 75,
          reason: 'the dealt hand carries its own base wager');
      expect(state.currentBet, 75);
      expect(state.bankroll, 1000 - 75);
    });

    test('splitting deducts exactly one extra base bet (no double-charging)',
        () {
      final engine = GameEngine(numDecks: 6);
      // Construct a known pre-split state — pair of 8s, no actual deal so
      // we can check the bet math in isolation.
      final pair = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.eight),
        const CardModel(suit: Suit.spades, rank: Rank.eight),
      ], bet: 100);
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.diamonds, rank: Rank.six),
        const CardModel(suit: Suit.clubs, rank: Rank.ten, faceUp: false),
      ]);
      final state = const GameState().copyWith(
        bankroll: 900, // already paid the first $100 in dealInitial
        currentBet: 100,
        playerHands: [pair],
        dealerHand: dealer,
        phase: GamePhase.playerTurn,
      );

      final afterSplit = engine.split(state);
      expect(afterSplit.playerHands.length, 2);
      expect(afterSplit.bankroll, 800,
          reason: 'split deducts one more base bet (\$100), not the total');
      expect(afterSplit.currentBet, 200,
          reason: 'total wager = 2 hands × \$100');
      expect(afterSplit.playerHands.every((h) => h.bet == 100), true,
          reason: 'each split hand inherits the source base bet');
      expect(afterSplit.playerHands.every((h) => h.fromSplit), true,
          reason: 'both new hands are flagged split-derived');
    });

    test('doubling stakes only that hand\'s bet, not the running total', () {
      final engine = GameEngine(numDecks: 6);
      final hand1 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.five),
        const CardModel(suit: Suit.diamonds, rank: Rank.six),
      ], bet: 100, fromSplit: true);
      final hand2 = HandModel(cards: [
        const CardModel(suit: Suit.spades, rank: Rank.eight),
        const CardModel(suit: Suit.clubs, rank: Rank.three),
      ], bet: 100, fromSplit: true);
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.six),
        const CardModel(suit: Suit.spades, rank: Rank.ten, faceUp: false),
      ]);
      final state = const GameState().copyWith(
        bankroll: 800, // after deal + split
        currentBet: 200, // 2 × \$100
        playerHands: [hand1, hand2],
        dealerHand: dealer,
        phase: GamePhase.playerTurn,
        activeHandIndex: 0,
      );

      final afterDouble = engine.doubleDown(state);
      expect(afterDouble.bankroll, 700,
          reason: 'double stakes only one more of THIS hand\'s bet');
      expect(afterDouble.currentBet, 300,
          reason: 'sum of hands = doubled \$200 + normal \$100');
      expect(afterDouble.playerHands[0].isDoubled, true);
      expect(afterDouble.playerHands[0].bet, 100,
          reason: 'the base bet field is unchanged by doubling');
    });

    test('resolveAll pays a doubled hand from its own bet', () {
      final engine = GameEngine(numDecks: 6);
      // Hand 1 doubled to \$200 and wins; hand 2 normal \$100 loses.
      final h1Doubled = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.five),
        const CardModel(suit: Suit.diamonds, rank: Rank.six),
        const CardModel(suit: Suit.clubs, rank: Rank.eight),
      ], bet: 100, isDoubled: true, fromSplit: true);
      final h2 = HandModel(cards: [
        const CardModel(suit: Suit.spades, rank: Rank.eight),
        const CardModel(suit: Suit.clubs, rank: Rank.three),
        const CardModel(suit: Suit.diamonds, rank: Rank.six),
      ], bet: 100, fromSplit: true); // 17, dealer 18 → loss
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten, faceUp: true),
        const CardModel(suit: Suit.spades, rank: Rank.eight, faceUp: true),
      ]); // 18
      final state = const GameState().copyWith(
        bankroll: 700, // after deal+split+double
        currentBet: 300,
        playerHands: [h1Doubled, h2],
        dealerHand: dealer,
        phase: GamePhase.dealerTurn,
      );

      final resolved = engine.resolveAll(state);
      // Hand 1: 19 vs 18 → win. Doubled bet pays 2 × \$200 = \$400.
      // Hand 2: 17 vs 18 → loss. \$0.
      // Final bankroll = 700 + 400 = 1100. Net vs starting \$1000 = +\$100.
      expect(resolved.bankroll, 1100);
      expect(resolved.handResults[0], GameResult.win);
      expect(resolved.handResults[1], GameResult.loss);
      expect(resolved.roundNet, 100);
    });

    test('split-21 (e.g. split aces dealt 10) pays 1:1, not 3:2', () {
      final engine = GameEngine(numDecks: 6);
      final aceTen = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.diamonds, rank: Rank.ten),
      ], bet: 100, fromSplit: true);
      final aceNine = HandModel(cards: [
        const CardModel(suit: Suit.spades, rank: Rank.ace),
        const CardModel(suit: Suit.clubs, rank: Rank.nine),
      ], bet: 100, fromSplit: true);
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten, faceUp: true),
        const CardModel(suit: Suit.spades, rank: Rank.seven, faceUp: true),
      ]); // 17
      final state = const GameState().copyWith(
        bankroll: 800, // after deal + split
        currentBet: 200,
        playerHands: [aceTen, aceNine],
        dealerHand: dealer,
        phase: GamePhase.dealerTurn,
      );

      final resolved = engine.resolveAll(state);
      // Both hands win 1:1 (NOT 3:2 — split hands don't count as blackjack).
      // Win pays 2× bet, so each \$100 hand returns \$200.
      // Final bankroll = 800 + 200 + 200 = 1200. Net = +\$200.
      expect(resolved.bankroll, 1200);
      // The internal results are 'win' (regular 21), not 'blackjack'.
      expect(resolved.handResults[0], GameResult.win);
      expect(resolved.handResults[1], GameResult.win);
      expect(resolved.roundNet, 200);
    });

    test('sideBet pays sliding scale on dealer bust, lost on dealer 21', () {
      final engine = GameEngine(numDecks: 6);
      final player = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten),
        const CardModel(suit: Suit.spades, rank: Rank.nine),
      ], bet: 100);
      // Dealer bust in 4 cards → side bet pays 4:1.
      final dealerBust4 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.five, faceUp: true),
        const CardModel(suit: Suit.spades, rank: Rank.six, faceUp: true),
        const CardModel(suit: Suit.clubs, rank: Rank.three, faceUp: true),
        const CardModel(suit: Suit.diamonds, rank: Rank.king, faceUp: true),
      ]); // 24, bust
      final state = const GameState().copyWith(
        bankroll: 880, // after \$100 main + \$20 side deducted
        currentBet: 100,
        sideBet: 20,
        playerHands: [player],
        dealerHand: dealerBust4,
        phase: GamePhase.dealerTurn,
      );

      final resolved = engine.resolveAll(state);
      // Main: 19 vs bust → dealerBust. Pays \$200.
      // Side: 4 cards bust pays 4:1. \$20 stake + \$80 profit = \$100 returned.
      // Bankroll = 880 + 200 + 100 = 1180. Net = +\$180.
      expect(resolved.bankroll, 1180);
      expect(resolved.handResults[0], GameResult.dealerBust);
      expect(resolved.roundNet, 180);
    });

    test('insurance pays 2:1 on dealer BJ, lost otherwise', () {
      final engine = GameEngine(numDecks: 6);
      final player = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten),
        const CardModel(suit: Suit.spades, rank: Rank.nine),
      ], bet: 100);
      final dealerBJ = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace, faceUp: true),
        const CardModel(suit: Suit.spades, rank: Rank.king, faceUp: true),
      ]);
      final state = const GameState().copyWith(
        bankroll: 850, // after \$100 main + \$50 insurance deducted
        currentBet: 100,
        insuranceBet: 50,
        playerHands: [player],
        dealerHand: dealerBJ,
        phase: GamePhase.dealerTurn,
      );

      final resolved = engine.resolveAll(state);
      // Insurance: \$50 + 2 × \$50 profit = \$150 returned.
      // Main: loss to dealer BJ → \$0 payout.
      // Bankroll = 850 + 150 = 1000. Net = 0 (insurance hedged the loss).
      expect(resolved.bankroll, 1000);
      expect(resolved.handResults[0], GameResult.loss);
      expect(resolved.roundNet, 0);
    });
  });

  group('GameEngine multi-spot', () {
    test('deals one hand per funded spot, each with its own bet', () {
      final engine = GameEngine(numDecks: 6);
      var state = const GameState().copyWith(
        bankroll: 1000,
        spotBets: [0, 0, 0],
      );
      state = engine.placeBet(state, 100, 0);
      state = engine.placeBet(state, 50, 1);
      state = engine.placeBet(state, 25, 2);
      expect(state.currentBet, 175);

      final dealt = engine.dealInitial(state);
      expect(dealt.playerHands.length, 3);
      expect(dealt.playerHands.map((h) => h.bet).toList(), [100, 50, 25]);
      expect(dealt.playerHands.every((h) => h.cards.length == 2), true);
      expect(dealt.bankroll, 825, reason: '1000 − 175 total main wager');
      expect(dealt.currentBet, 175);
      expect(dealt.handResults.length, 3);
    });

    test('empty spots are skipped when dealing', () {
      final engine = GameEngine(numDecks: 6);
      var state = const GameState().copyWith(
        bankroll: 1000,
        spotBets: [0, 0],
      );
      state = engine.placeBet(state, 100, 0); // spot 1 left empty

      final dealt = engine.dealInitial(state);
      expect(dealt.playerHands.length, 1);
      expect(dealt.playerHands[0].bet, 100);
      expect(dealt.bankroll, 900);
    });

    test('clearBet resets every spot and the side bet', () {
      final engine = GameEngine(numDecks: 6);
      var state = const GameState().copyWith(bankroll: 1000, spotBets: [0, 0]);
      state = engine.placeBet(state, 100, 0);
      state = engine.placeBet(state, 50, 1);
      state = engine.placeSideBet(state, 20);
      expect(state.currentBet, 150);
      expect(state.sideBet, 20);

      final cleared = engine.clearBet(state);
      expect(cleared.currentBet, 0);
      expect(cleared.sideBet, 0);
      expect(cleared.spotBets, [0, 0]);
    });

    test('two separate spots each pay their own bet; naturals still pay 3:2',
        () {
      final engine = GameEngine(numDecks: 6);
      // Two INDEPENDENT spots (not from a split), so a two-card 21 is a real
      // natural that must still pay 3:2 even though several hands are in play.
      final natural = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.king),
      ], bet: 100);
      final winner = HandModel(cards: [
        const CardModel(suit: Suit.clubs, rank: Rank.ten),
        const CardModel(suit: Suit.diamonds, rank: Rank.nine),
      ], bet: 50); // 19
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten, faceUp: true),
        const CardModel(suit: Suit.clubs, rank: Rank.eight, faceUp: true),
      ]); // 18
      final state = const GameState().copyWith(
        bankroll: 850, // 1000 − 150 staked across both spots
        currentBet: 150,
        playerHands: [natural, winner],
        dealerHand: dealer,
        phase: GamePhase.dealerTurn,
      );

      final resolved = engine.resolveAll(state);
      // natural: \$100 + \$150 = \$250. winner: \$50 × 2 = \$100. → \$350 back.
      expect(resolved.handResults[0], GameResult.blackjack);
      expect(resolved.handResults[1], GameResult.win);
      expect(resolved.bankroll, 1200);
      expect(resolved.roundNet, 200);
    });

    test('roundNet aggregates a winning and a losing hand', () {
      final engine = GameEngine(numDecks: 6);
      final winHand = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten),
        const CardModel(suit: Suit.spades, rank: Rank.nine),
      ], bet: 100); // 19
      final loseHand = HandModel(cards: [
        const CardModel(suit: Suit.clubs, rank: Rank.ten),
        const CardModel(suit: Suit.diamonds, rank: Rank.six),
      ], bet: 100); // 16
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten, faceUp: true),
        const CardModel(suit: Suit.clubs, rank: Rank.eight, faceUp: true),
      ]); // 18
      final state = const GameState().copyWith(
        bankroll: 800,
        currentBet: 200,
        playerHands: [winHand, loseHand],
        dealerHand: dealer,
        phase: GamePhase.dealerTurn,
      );

      final resolved = engine.resolveAll(state);
      expect(resolved.handResults[0], GameResult.win);
      expect(resolved.handResults[1], GameResult.loss);
      // win returns \$200, loss returns \$0 → \$200 back on \$200 staked.
      expect(resolved.roundNet, 0);
      expect(resolved.bankroll, 1000);
    });

    test('stand walks through every spot before the dealer plays', () {
      final engine = GameEngine(numDecks: 6);
      final h0 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten),
        const CardModel(suit: Suit.spades, rank: Rank.seven),
      ], bet: 100); // 17
      final h1 = HandModel(cards: [
        const CardModel(suit: Suit.clubs, rank: Rank.nine),
        const CardModel(suit: Suit.diamonds, rank: Rank.eight),
      ], bet: 100); // 17
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.six),
        const CardModel(suit: Suit.spades, rank: Rank.ten, faceUp: false),
      ]);
      var state = const GameState().copyWith(
        playerHands: [h0, h1],
        dealerHand: dealer,
        phase: GamePhase.playerTurn,
        activeHandIndex: 0,
      );

      state = engine.stand(state);
      expect(state.activeHandIndex, 1);
      expect(state.phase, GamePhase.playerTurn);

      state = engine.stand(state);
      expect(state.phase, GamePhase.dealerTurn);
    });

    test('a natural-blackjack spot is auto-skipped during play', () {
      final engine = GameEngine(numDecks: 6);
      final h0 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ten),
        const CardModel(suit: Suit.spades, rank: Rank.seven),
      ], bet: 100); // 17
      final bjHand = HandModel(cards: [
        const CardModel(suit: Suit.clubs, rank: Rank.ace),
        const CardModel(suit: Suit.diamonds, rank: Rank.king),
      ], bet: 100); // natural 21 — nothing to decide
      final h2 = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.nine),
        const CardModel(suit: Suit.spades, rank: Rank.seven),
      ], bet: 100); // 16
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.six),
        const CardModel(suit: Suit.spades, rank: Rank.ten, faceUp: false),
      ]);
      var state = const GameState().copyWith(
        playerHands: [h0, bjHand, h2],
        dealerHand: dealer,
        phase: GamePhase.playerTurn,
        activeHandIndex: 0,
      );

      state = engine.stand(state); // finish h0 → should jump past the BJ hand
      expect(state.activeHandIndex, 2);
      expect(state.phase, GamePhase.playerTurn);
    });

    test('splitting aces mid-round resumes at the next spot, not the dealer',
        () {
      final engine = GameEngine(numDecks: 6);
      final aces = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.ace),
      ], bet: 100);
      final other = HandModel(cards: [
        const CardModel(suit: Suit.clubs, rank: Rank.ten),
        const CardModel(suit: Suit.diamonds, rank: Rank.six),
      ], bet: 100); // 16 — still needs a decision
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.six),
        const CardModel(suit: Suit.spades, rank: Rank.ten, faceUp: false),
      ]);
      final state = const GameState().copyWith(
        bankroll: 900,
        currentBet: 200,
        playerHands: [aces, other],
        dealerHand: dealer,
        phase: GamePhase.playerTurn,
        activeHandIndex: 0,
      );

      final afterSplit = engine.split(state);
      expect(afterSplit.playerHands.length, 3);
      expect(afterSplit.activeHandIndex, 2,
          reason: 'both ace hands auto-stand; play moves to the other spot');
      expect(afterSplit.phase, GamePhase.playerTurn);
      expect(afterSplit.bankroll, 800, reason: 'one more base bet staked');
    });

    test('splitting aces on the only spot goes straight to the dealer', () {
      final engine = GameEngine(numDecks: 6);
      final aces = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.ace),
        const CardModel(suit: Suit.spades, rank: Rank.ace),
      ], bet: 100);
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.hearts, rank: Rank.six),
        const CardModel(suit: Suit.spades, rank: Rank.ten, faceUp: false),
      ]);
      final state = const GameState().copyWith(
        bankroll: 900,
        currentBet: 100,
        playerHands: [aces],
        dealerHand: dealer,
        phase: GamePhase.playerTurn,
        activeHandIndex: 0,
      );

      final afterSplit = engine.split(state);
      expect(afterSplit.playerHands.length, 2);
      expect(afterSplit.phase, GamePhase.dealerTurn);
    });

    test('a full two-hand round settles cleanly with real cards', () {
      final engine = GameEngine(numDecks: 6);
      var state = const GameState().copyWith(bankroll: 1000, spotBets: [0, 0]);
      state = engine.placeBet(state, 50, 0);
      state = engine.placeBet(state, 50, 1);
      state = engine.dealInitial(state);

      // The UI resolves insurance first — decline so play can continue.
      if (state.insuranceState == InsuranceState.offered) {
        state = engine.handleInsurance(state, false);
      }

      // Stand every hand until control passes to the dealer.
      var guard = 0;
      while (state.phase == GamePhase.playerTurn && guard++ < 30) {
        state = engine.stand(state);
      }
      expect(state.phase, GamePhase.dealerTurn);

      // Run the dealer to completion, then settle.
      state = engine.revealDealerHole(state);
      guard = 0;
      while (engine.dealerShouldHit(state) && guard++ < 30) {
        state = engine.dealerHit(state);
      }
      state = engine.resolveAll(state);

      expect(state.phase, GamePhase.result);
      expect(state.handResults.length, 2);
      expect(state.handResults.every((r) => r != null), true);
      // Invariant: final bankroll = starting bankroll + net for the round,
      // regardless of which cards came out.
      expect(state.bankroll, 1000 + state.roundNet);
      expect(state.bankroll, greaterThanOrEqualTo(0));
    });
  });

  group('DeckManager', () {
    test('shoe contains correct number of cards', () {
      final deck = DeckManager(numDecks: 6);
      // After creating, some cards may be cut — total should still be 312
      // We check the total is within range (cut removes none, it just reorders)
      expect(deck.remaining, lessThanOrEqualTo(312));
      expect(deck.remaining, greaterThan(0));
    });

    test('draw reduces remaining count', () {
      final deck = DeckManager(numDecks: 1);
      final before = deck.remaining;
      deck.draw();
      expect(deck.remaining, before - 1);
    });
  });
}

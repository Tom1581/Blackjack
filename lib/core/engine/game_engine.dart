import '../models/card_model.dart';
import '../models/game_state.dart';
import '../models/hand_model.dart';
import 'deck_manager.dart';
import 'hi_lo_counter.dart';

/// Core game logic — direct port of BlackjackGame from blackjack.py, extended
/// to support multiple simultaneous betting spots (hands) in one round.
/// Stateless: each method takes a GameState and returns a new GameState.
class GameEngine {
  final DeckManager _deck;
  final HiLoCounter _counter;

  /// When true, the deck is reshuffled after every hand (continuous shuffle
  /// machine). Card counting provides no edge in this mode.
  final bool continuous;

  GameEngine({int numDecks = 6, this.continuous = false})
      : _deck = DeckManager(numDecks: numDecks),
        _counter = HiLoCounter(totalDecks: numDecks);

  int get numDecks => _deck.numDecks;

  /// Maximum number of main betting spots a player may play at once.
  static const maxSpots = 3;

  // ─── Betting ──────────────────────────────────────────────────────────────

  /// Maximum allowed dealer-bust side bet.
  static const sideBetMax = 50;

  /// Add [amount] chips to the main bet on [spotIndex].
  GameState placeBet(GameState state, int amount, [int spotIndex = 0]) {
    assert(amount > 0);
    if (spotIndex < 0 || spotIndex >= state.spotBets.length) return state;
    final spots = [...state.spotBets];
    spots[spotIndex] += amount;
    return state.copyWith(
      spotBets: spots,
      currentBet: state.currentBet + amount,
    );
  }

  /// Add chips to the dealer-bust side bet. Capped at [sideBetMax].
  GameState placeSideBet(GameState state, int amount) {
    assert(amount > 0);
    final next = state.sideBet + amount;
    if (next > sideBetMax) return state;
    if (state.currentBet + next > state.bankroll) return state;
    return state.copyWith(sideBet: next);
  }

  GameState clearBet(GameState state) => state.copyWith(
        currentBet: 0,
        sideBet: 0,
        spotBets: List<int>.filled(state.spotBets.length, 0),
      );

  // ─── Deal ────────────────────────────────────────────────────────────────

  GameState dealInitial(GameState state) {
    // One hand per funded spot. Empty spots (bet 0) are skipped.
    final funded = <int>[];
    for (var i = 0; i < state.spotBets.length; i++) {
      if (state.spotBets[i] > 0) funded.add(i);
    }
    // Defensive: nothing wagered — leave the state untouched.
    if (funded.isEmpty) return state;

    // Deal like a real table: one card to each spot, dealer up-card, a second
    // card to each spot, then the dealer's face-down hole card (not counted).
    final firstCards = [for (var _ in funded) _drawAndCount()];
    final d1 = _drawAndCount();
    final secondCards = [for (var _ in funded) _drawAndCount()];
    final d2 = _deck.draw(faceUp: false); // hole card — not counted yet

    final playerHands = <HandModel>[
      for (var k = 0; k < funded.length; k++)
        HandModel(
          cards: [firstCards[k], secondCards[k]],
          bet: state.spotBets[funded[k]],
        ),
    ];
    final dealerHand = HandModel(cards: [d1, d2]);

    final insuranceState = d1.rank == Rank.ace
        ? InsuranceState.offered
        : InsuranceState.notOffered;

    // Where does play start? Skip any hand that is already a natural blackjack
    // (nothing to decide). If the dealer has blackjack, or every player hand is
    // a natural, hand straight off to the dealer sequence.
    final firstIdx = _firstActionable(playerHands, 0);
    final GamePhase phase;
    if (insuranceState == InsuranceState.offered) {
      // Insurance is resolved first via the UI prompt; play continues after.
      phase = GamePhase.playerTurn;
    } else if (dealerHand.isBlackjack || firstIdx >= playerHands.length) {
      phase = GamePhase.dealerTurn;
    } else {
      phase = GamePhase.playerTurn;
    }

    return _applyCounters(state.copyWith(
      phase: phase,
      playerHands: playerHands,
      activeHandIndex: firstIdx,
      dealerHand: dealerHand,
      bankroll: state.bankroll - state.currentBet - state.sideBet,
      handResults: List<GameResult?>.filled(playerHands.length, null),
      insuranceState: insuranceState,
      roundNet: 0,
      message: null,
    ));
  }

  // ─── Insurance ───────────────────────────────────────────────────────────

  GameState handleInsurance(GameState state, bool take) {
    // Insurance: side bet up to half the total main bet that the dealer has a
    // natural blackjack. Pays 2:1 if the dealer does; lost otherwise.
    var cost = take ? state.currentBet ~/ 2 : 0;
    // Defensive: if somehow asked to take insurance the player can't afford,
    // silently decline. UI normally prevents this.
    if (cost > state.bankroll) cost = 0;
    final actuallyTook = cost > 0;
    final next = state.copyWith(
      insuranceState:
          actuallyTook ? InsuranceState.taken : InsuranceState.declined,
      insuranceBet: cost,
      bankroll: state.bankroll - cost,
    );

    // Dealer blackjack ends the round immediately; otherwise resume play at the
    // first hand that still needs a decision.
    final firstIdx = _firstActionable(next.playerHands, 0);
    if (next.dealerHand.isBlackjack || firstIdx >= next.playerHands.length) {
      return next.copyWith(
        phase: GamePhase.dealerTurn,
        activeHandIndex: firstIdx,
      );
    }
    return next.copyWith(
      phase: GamePhase.playerTurn,
      activeHandIndex: firstIdx,
    );
  }

  // ─── Player actions ──────────────────────────────────────────────────────

  GameState hit(GameState state) {
    final card = _drawAndCount();
    final hand = state.activeHand.addCard(card);
    final hands = _replaceActive(state.playerHands, state.activeHandIndex, hand);

    if (hand.isBust || hand.value == 21) {
      return _advanceOrDealer(state.copyWith(playerHands: hands));
    }
    return _applyCounters(state.copyWith(playerHands: hands));
  }

  GameState stand(GameState state) => _advanceOrDealer(state);

  GameState doubleDown(GameState state) {
    assert(state.activeHand.canDouble);
    final card = _drawAndCount();
    final hand = state.activeHand.addCard(card).markDoubled();
    final hands = _replaceActive(state.playerHands, state.activeHandIndex, hand);
    // Doubling stakes one extra base bet for *this* hand only — its own [bet],
    // independent of how many other hands exist.
    final extra = state.activeHand.bet;
    return _advanceOrDealer(_applyCounters(state.copyWith(
      playerHands: hands,
      bankroll: state.bankroll - extra,
      currentBet: state.currentBet + extra,
    )));
  }

  GameState split(GameState state) {
    assert(state.activeHand.isPair);
    final src = state.activeHand;
    final c1 = src.cards[0];
    final c2 = src.cards[1];
    final newCard1 = _drawAndCount();
    final newCard2 = _drawAndCount();
    // Each split hand carries the same base bet as the source and is flagged as
    // split-derived so it can never pay the 3:2 blackjack bonus.
    final hand1 =
        HandModel(cards: [c1, newCard1], bet: src.bet, fromSplit: true);
    final hand2 =
        HandModel(cards: [c2, newCard2], bet: src.bet, fromSplit: true);
    final allHands = [
      ...state.playerHands.sublist(0, state.activeHandIndex),
      hand1,
      hand2,
      ...state.playerHands.sublist(state.activeHandIndex + 1),
    ];

    // Splitting always wagers exactly one more base bet.
    final extra = src.bet;
    final next = _applyCounters(state.copyWith(
      playerHands: allHands,
      handResults: List<GameResult?>.filled(allHands.length, null),
      bankroll: state.bankroll - extra,
      currentBet: state.currentBet + extra,
    ));

    // Split aces receive exactly one card each and stand automatically — resume
    // at the next spot (past both new hands). Other splits keep playing the
    // first of the two new hands (unless it is an auto-stand 21).
    final searchFrom = c1.rank == Rank.ace
        ? state.activeHandIndex + 2
        : state.activeHandIndex;
    final nextIdx = _firstActionable(allHands, searchFrom);
    return next.copyWith(
      activeHandIndex: nextIdx,
      phase: nextIdx >= allHands.length
          ? GamePhase.dealerTurn
          : GamePhase.playerTurn,
    );
  }

  // ─── Dealer turn (staged so the UI can pace the animation) ──────────────

  /// Flip the dealer's hole card face-up and update the running count for it.
  /// Should be the first step of the animated dealer sequence.
  GameState revealDealerHole(GameState state) {
    final hole = state.dealerHand.cards[1];
    _counter.update(hole);
    return _applyCounters(state.copyWith(
      dealerHand: state.dealerHand.revealAll(),
    ));
  }

  /// Whether the dealer is required to take another card. Dealer hits soft 17.
  bool dealerShouldHit(GameState state) {
    final d = state.dealerHand;
    return d.value < 17 || (d.isSoft && d.value == 17);
  }

  /// Draw one additional card for the dealer.
  GameState dealerHit(GameState state) {
    final card = _drawAndCount();
    return _applyCounters(state.copyWith(
      dealerHand: state.dealerHand.addCard(card),
    ));
  }

  // ─── New hand / reshuffle ────────────────────────────────────────────────

  GameState newHand(GameState state) {
    if (continuous || _deck.needsReshuffle) {
      _deck.reset();
      _counter.reset();
    }
    return state.copyWith(
      phase: GamePhase.betting,
      playerHands: [const HandModel()],
      activeHandIndex: 0,
      dealerHand: const HandModel(),
      currentBet: 0,
      spotBets: List<int>.filled(state.spotBets.length, 0),
      insuranceBet: 0,
      sideBet: 0,
      handResults: [null],
      insuranceState: InsuranceState.notOffered,
      roundNet: 0,
      message: _deck.needsReshuffle ? 'Shoe reshuffled' : null,
    );
  }

  /// Sliding payout multiplier for the dealer-bust side bet.
  /// The returned value is the *profit* multiplier — the stake is added
  /// separately by the caller. Standard "Buster Blackjack" schedule.
  static int busterPayoutMultiplier(int dealerCardCount) {
    switch (dealerCardCount) {
      case 3:
        return 2;
      case 4:
        return 4;
      case 5:
        return 15;
      case 6:
        return 50;
      default:
        return 100; // 7 or more cards
    }
  }

  // ─── Internals ───────────────────────────────────────────────────────────

  CardModel _drawAndCount() {
    final card = _deck.draw();
    _counter.update(card);
    _counter.updateDecksRemaining(_deck.remaining);
    return card;
  }

  GameState _applyCounters(GameState state) => state.copyWith(
        runningCount: _counter.runningCount,
        trueCount: _counter.trueCount,
        deckPenetration: _deck.penetration,
        cardsRemaining: _deck.remaining,
      );

  /// Index of the first hand at or after [from] that still needs a player
  /// decision. Natural blackjacks (and split two-card 21s) auto-stand and are
  /// skipped. Returns `hands.length` when no hand needs action.
  int _firstActionable(List<HandModel> hands, int from) {
    var i = from < 0 ? 0 : from;
    while (i < hands.length && hands[i].isBlackjack) {
      i++;
    }
    return i;
  }

  GameState _advanceOrDealer(GameState state) {
    final nextIdx = _firstActionable(state.playerHands, state.activeHandIndex + 1);
    if (nextIdx < state.playerHands.length) {
      return _applyCounters(state.copyWith(activeHandIndex: nextIdx));
    }
    // All player hands done — hand off to the animated dealer sequence.
    return state.copyWith(phase: GamePhase.dealerTurn);
  }

  /// Final settlement. Assumes the dealer hand is already revealed and any
  /// dealer hits have been drawn (the table provider does this step-by-step
  /// via [revealDealerHole] + [dealerHit] for animation).
  GameState resolveAll(GameState state) {
    final dealer = state.dealerHand;
    final results = <GameResult?>[];
    var bankroll = state.bankroll;
    var returned = 0; // everything paid back into the bankroll this settlement

    // Insurance settles before the main hands. Pays 2:1 (returns 3× the stake)
    // if the dealer has a natural blackjack; otherwise forfeit.
    if (state.insuranceBet > 0 && dealer.isBlackjack) {
      returned += state.insuranceBet * 3;
    }

    // Dealer-bust side bet ("Buster Blackjack"). Pays a sliding multiplier
    // based on how many cards the dealer needed to bust. Lost otherwise.
    if (state.sideBet > 0 && dealer.isBust) {
      final mult = busterPayoutMultiplier(dealer.cards.length);
      returned += state.sideBet + state.sideBet * mult; // stake back + profit
    }

    for (final hand in state.playerHands) {
      // Per-hand bet = that hand's own base wager, doubled if it was doubled.
      final handBet = hand.isDoubled ? hand.bet * 2 : hand.bet;
      final result = _resolveHand(hand, dealer, fromSplit: hand.fromSplit);
      results.add(result);
      returned += _payout(result, handBet);
    }

    bankroll += returned;

    // Net for the round = everything returned minus everything staked. The
    // stakes (main + side + insurance) were already deducted from the bankroll
    // at deal / insurance time.
    final staked = state.currentBet + state.sideBet + state.insuranceBet;
    final roundNet = returned - staked;

    return _applyCounters(state.copyWith(
      phase: GamePhase.result,
      bankroll: bankroll,
      handResults: results,
      roundNet: roundNet,
    ));
  }

  GameResult _resolveHand(
    HandModel player,
    HandModel dealer, {
    required bool fromSplit,
  }) {
    final playerBJ = !fromSplit && player.isBlackjack;
    final dealerBJ = dealer.isBlackjack;

    if (playerBJ && !dealerBJ) return GameResult.blackjack;
    if (dealerBJ && !playerBJ) return GameResult.loss;
    if (player.isBust) return GameResult.bust;
    if (dealer.isBust) return GameResult.dealerBust;
    if (player.value > dealer.value) return GameResult.win;
    if (player.value < dealer.value) return GameResult.loss;
    return GameResult.push;
  }

  int _payout(GameResult result, int bet) {
    switch (result) {
      case GameResult.blackjack:
        return bet + (bet * 1.5).toInt();
      case GameResult.win:
      case GameResult.dealerBust:
        return bet * 2;
      case GameResult.push:
        return bet;
      case GameResult.loss:
      case GameResult.bust:
        return 0;
    }
  }

  List<HandModel> _replaceActive(
      List<HandModel> hands, int idx, HandModel hand) {
    return [
      ...hands.sublist(0, idx),
      hand,
      ...hands.sublist(idx + 1),
    ];
  }
}

import '../models/card_model.dart';
import '../models/game_state.dart';
import '../models/hand_model.dart';
import 'deck_manager.dart';
import 'hi_lo_counter.dart';

/// Core game logic — direct port of BlackjackGame from blackjack.py.
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

  // ─── Betting ──────────────────────────────────────────────────────────────

  /// Maximum allowed dealer-bust side bet.
  static const sideBetMax = 50;

  GameState placeBet(GameState state, int amount) {
    assert(amount > 0 && amount <= state.bankroll);
    return state.copyWith(
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

  GameState clearBet(GameState state) =>
      state.copyWith(currentBet: 0, sideBet: 0);

  // ─── Deal ────────────────────────────────────────────────────────────────

  GameState dealInitial(GameState state) {
    // Deal: player, dealer, player, dealer (second dealer card face-down)
    final p1 = _drawAndCount();
    final d1 = _drawAndCount();
    final p2 = _drawAndCount();
    final d2 = _deck.draw(faceUp: false); // hole card — not counted yet

    final playerHand = HandModel(cards: [p1, p2]);
    final dealerHand = HandModel(cards: [d1, d2]);

    final insuranceState = d1.rank == Rank.ace
        ? InsuranceState.offered
        : InsuranceState.notOffered;

    return _applyCounters(state.copyWith(
      phase: insuranceState == InsuranceState.offered
          ? GamePhase.playerTurn // insurance prompt handled in UI
          : _checkBlackjack(playerHand, dealerHand)
              ? GamePhase.dealerTurn // hand off to animated dealer sequence
              : GamePhase.playerTurn,
      playerHands: [playerHand],
      activeHandIndex: 0,
      dealerHand: dealerHand,
      bankroll: state.bankroll - state.currentBet - state.sideBet,
      // Lock in the per-hand stake — splits and doubles will reference this
      // instead of dividing currentBet by hand count, which only works when
      // every hand carries the same wager.
      originalBet: state.currentBet,
      handResults: [null],
      insuranceState: insuranceState,
      message: null,
    ));
  }

  // ─── Insurance ───────────────────────────────────────────────────────────

  GameState handleInsurance(GameState state, bool take) {
    // Insurance: side bet up to half the original bet that the dealer has
    // a natural blackjack. Pays 2:1 if dealer does; lost otherwise.
    var cost = take ? state.currentBet ~/ 2 : 0;
    // Defensive: if somehow asked to take insurance the player can't
    // afford, silently decline. UI normally prevents this.
    if (cost > state.bankroll) cost = 0;
    final actuallyTook = cost > 0;
    var next = state.copyWith(
      insuranceState:
          actuallyTook ? InsuranceState.taken : InsuranceState.declined,
      insuranceBet: cost,
      bankroll: state.bankroll - cost,
    );
    if (_checkBlackjack(state.activeHand, state.dealerHand)) {
      // Hand off to animated dealer sequence — caller will reveal the
      // hole card and call resolveAll().
      return next.copyWith(phase: GamePhase.dealerTurn);
    }
    return next.copyWith(phase: GamePhase.playerTurn);
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

  GameState stand(GameState state) =>
      _advanceOrDealer(state);

  GameState doubleDown(GameState state) {
    assert(state.activeHand.canDouble);
    final card = _drawAndCount();
    final hand = state.activeHand.addCard(card).markDoubled();
    final hands = _replaceActive(state.playerHands, state.activeHandIndex, hand);
    // Doubling stakes one extra base bet for *this* hand only — independent
    // of how many other hands exist. Using state.currentBet (the running
    // total across all hands) would over-charge after a split.
    final extra = state.originalBet;
    return _advanceOrDealer(_applyCounters(state.copyWith(
      playerHands: hands,
      bankroll: state.bankroll - extra,
      currentBet: state.currentBet + extra,
    )));
  }

  GameState split(GameState state) {
    assert(state.activeHand.isPair);
    final c1 = state.activeHand.cards[0];
    final c2 = state.activeHand.cards[1];
    final newCard1 = _drawAndCount();
    final newCard2 = _drawAndCount();
    final hand1 = HandModel(cards: [c1, newCard1]);
    final hand2 = HandModel(cards: [c2, newCard2]);
    final allHands = [
      ...state.playerHands.sublist(0, state.activeHandIndex),
      hand1,
      hand2,
      ...state.playerHands.sublist(state.activeHandIndex + 1),
    ];
    final results = List<GameResult?>.filled(allHands.length, null);

    // Splitting always wagers exactly one more base bet. The previous
    // implementation doubled state.currentBet, which works for the first
    // split but compounds wrongly on a re-split (3 hands wants 3× the base,
    // not 4×).
    final extra = state.originalBet;
    final next = _applyCounters(state.copyWith(
      playerHands: allHands,
      handResults: results,
      bankroll: state.bankroll - extra,
      currentBet: state.currentBet + extra,
    ));

    // Split aces: each receives exactly one card and the player cannot hit,
    // double, or re-split. Both hands stand and the dealer plays.
    if (c1.rank == Rank.ace) {
      return next.copyWith(
        activeHandIndex: allHands.length,
        phase: GamePhase.dealerTurn,
      );
    }

    return next;
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
      originalBet: 0,
      insuranceBet: 0,
      sideBet: 0,
      handResults: [null],
      insuranceState: InsuranceState.notOffered,
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

  GameState _advanceOrDealer(GameState state) {
    final next = state.activeHandIndex + 1;
    if (next < state.playerHands.length) {
      return _applyCounters(state.copyWith(activeHandIndex: next));
    }
    // All player hands done — hand off to the animated dealer sequence.
    return state.copyWith(phase: GamePhase.dealerTurn);
  }

  bool _checkBlackjack(HandModel player, HandModel dealer) =>
      player.isBlackjack || dealer.isBlackjack;

  /// Final settlement. Assumes the dealer hand is already revealed and any
  /// dealer hits have been drawn (the table provider does this step-by-step
  /// via [revealDealerHole] + [dealerHit] for animation).
  GameState resolveAll(GameState state) {
    final dealer = state.dealerHand;
    final results = <GameResult?>[];
    var bankroll = state.bankroll;

    // Insurance settles before the main hand. Pays 2:1 (returns 3× the
    // insurance stake total) if the dealer has a natural blackjack;
    // otherwise the stake is forfeit (already deducted at takeInsurance).
    if (state.insuranceBet > 0 && dealer.isBlackjack) {
      bankroll += state.insuranceBet * 3;
    }

    // Dealer-bust side bet ("Buster Blackjack"). Pays a sliding multiplier
    // based on how many cards the dealer needed to bust. Lost otherwise.
    if (state.sideBet > 0 && dealer.isBust) {
      final mult = busterPayoutMultiplier(dealer.cards.length);
      bankroll += state.sideBet + state.sideBet * mult; // stake back + profit
    }

    // Once the player has split, no hand can count as a "natural" blackjack
    // — only the original 2-card initial deal pays 3:2. Split-21 (e.g. split
    // aces dealt a ten) is just a regular 21 and pays 1:1.
    final fromSplit = state.playerHands.length > 1;

    for (final hand in state.playerHands) {
      // Per-hand bet = base wager, doubled if the player doubled this hand.
      // Computing it from `currentBet / N` would average the bets across
      // hands, which is wrong as soon as one split hand is doubled.
      final handBet = hand.isDoubled ? state.originalBet * 2 : state.originalBet;
      final result = _resolveHand(hand, dealer, fromSplit: fromSplit);
      results.add(result);
      bankroll += _payout(result, handBet, state);
    }

    return _applyCounters(state.copyWith(
      phase: GamePhase.result,
      bankroll: bankroll,
      handResults: results,
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

  int _payout(GameResult result, int bet, GameState state) {
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

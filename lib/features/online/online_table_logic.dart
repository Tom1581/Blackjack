import '../../core/engine/deck_manager.dart';
import '../../core/models/card_model.dart';
import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';
import 'online_state.dart';

/// Authoritative multiplayer table logic, run only on the host device. Holds
/// the shared shoe and the canonical [OnlineTableState]; every mutating method
/// validates the actor and returns the next state (also stored in [state]).
///
/// Rules mirror the single-player engine: dealer hits soft 17, blackjack pays
/// 3:2, double-on-any-two (one card then stand). Splits are intentionally left
/// out of the online MVP to keep the seat/turn model simple.
class OnlineTableLogic {
  final DeckManager _shoe;
  OnlineTableState state;

  /// Maximum seats at an online table.
  static const maxSeats = 5;

  static const startingBankroll = 1000;

  OnlineTableLogic({
    required String roomCode,
    required String hostId,
    int numDecks = 6,
  })  : _shoe = DeckManager(numDecks: numDecks),
        state = OnlineTableState(roomCode: roomCode, hostId: hostId);

  // ─── Roster ────────────────────────────────────────────────────────────

  /// Seat a player (or update their name if already seated). New players start
  /// with the default bankroll and sit out until they place a bet.
  OnlineTableState addPlayer(String id, String name) {
    final existing = state.seatById(id);
    if (existing != null) {
      return _replaceSeat(existing.copyWith(name: name));
    }
    if (state.seats.length >= maxSeats) return state;
    final seat = OnlineSeat(id: id, name: name, bankroll: startingBankroll);
    state = state.copyWith(seats: [...state.seats, seat]);
    return state;
  }

  /// Remove a player. If they were the one to act, play advances cleanly.
  OnlineTableState removePlayer(String id) {
    final seats = state.seats.where((s) => s.id != id).toList();
    state = state.copyWith(seats: seats);
    if (state.phase == OnlinePhase.playerTurns) {
      return _advanceAfterAction();
    }
    return state;
  }

  // ─── Betting ───────────────────────────────────────────────────────────

  OnlineTableState placeBet(String actorId, int amount) {
    if (state.phase != OnlinePhase.betting || amount <= 0) return state;
    final seat = state.seatById(actorId);
    if (seat == null) return state;
    if (seat.bet + amount > seat.bankroll) return state;
    return _replaceSeat(seat.copyWith(bet: seat.bet + amount));
  }

  OnlineTableState clearBet(String actorId) {
    if (state.phase != OnlinePhase.betting) return state;
    final seat = state.seatById(actorId);
    if (seat == null || seat.bet == 0) return state;
    return _replaceSeat(seat.copyWith(bet: 0));
  }

  /// Host starts the deal. Only seats with a bet take cards; empty seats sit
  /// the round out.
  OnlineTableState startDeal(String actorId) {
    if (actorId != state.hostId || state.phase != OnlinePhase.betting) {
      return state;
    }
    final funded = state.seats.where((s) => s.bet > 0).toList();
    if (funded.isEmpty) return state;

    if (_shoe.needsReshuffle) _shoe.reset();

    // Deal one card to each funded seat, dealer up-card, a second to each, then
    // the dealer's face-down hole card.
    final firstCards = {for (final s in funded) s.id: _draw()};
    final dealerUp = _draw();
    final secondCards = {for (final s in funded) s.id: _draw()};
    final dealerHole = _shoe.draw(faceUp: false);

    final newSeats = [
      for (final s in state.seats)
        if (s.bet > 0)
          s.copyWith(
            bankroll: s.bankroll - s.bet,
            hand: HandModel(cards: [firstCards[s.id]!, secondCards[s.id]!], bet: s.bet),
            result: null,
            stood: false,
          )
        else
          s.copyWith(hand: const HandModel(), result: null, stood: false),
    ];

    state = state.copyWith(
      seats: newSeats,
      dealer: HandModel(cards: [dealerUp, dealerHole]),
      phase: OnlinePhase.playerTurns,
      activeSeat: -1,
      message: null,
    );

    // Dealer blackjack (peek) ends the round immediately; otherwise start with
    // the first seat that needs to act.
    if (state.dealer.isBlackjack) {
      return _resolve();
    }
    final first = _firstActionable();
    if (first < 0) return _resolve();
    state = state.copyWith(activeSeat: first);
    return state;
  }

  // ─── Player actions (only the active seat may act) ───────────────────────

  OnlineTableState hit(String actorId) {
    final seat = _activeIfActor(actorId);
    if (seat == null) return state;
    _replaceSeat(seat.copyWith(hand: seat.hand.addCard(_draw())));
    return _advanceAfterAction();
  }

  OnlineTableState stand(String actorId) {
    final seat = _activeIfActor(actorId);
    if (seat == null) return state;
    _replaceSeat(seat.copyWith(stood: true));
    return _advanceAfterAction();
  }

  OnlineTableState doubleDown(String actorId) {
    final seat = _activeIfActor(actorId);
    if (seat == null) return state;
    if (seat.hand.cards.length != 2 || seat.bankroll < seat.bet) return state;
    _replaceSeat(seat.copyWith(
      bankroll: seat.bankroll - seat.bet,
      hand: seat.hand.addCard(_draw()).markDoubled(),
      stood: true,
    ));
    return _advanceAfterAction();
  }

  // ─── Round lifecycle ─────────────────────────────────────────────────────

  /// Host deals the next round: clears hands/bets/results, keeps bankrolls.
  OnlineTableState nextRound(String actorId) {
    if (actorId != state.hostId || state.phase != OnlinePhase.results) {
      return state;
    }
    final seats = [
      for (final s in state.seats)
        s.copyWith(
          bet: 0,
          hand: const HandModel(),
          result: null,
          stood: false,
        ),
    ];
    state = state.copyWith(
      seats: seats,
      dealer: const HandModel(),
      phase: OnlinePhase.betting,
      activeSeat: -1,
      round: state.round + 1,
      message: null,
    );
    return state;
  }

  // ─── Internals ───────────────────────────────────────────────────────────

  CardModel _draw() => _shoe.draw(faceUp: true);

  OnlineTableState _replaceSeat(OnlineSeat seat) {
    final seats = [
      for (final s in state.seats) if (s.id == seat.id) seat else s,
    ];
    state = state.copyWith(seats: seats);
    return state;
  }

  OnlineSeat? _activeIfActor(String actorId) {
    if (state.phase != OnlinePhase.playerTurns) return null;
    final active = state.activeSeatOrNull;
    if (active == null || active.id != actorId) return null;
    return active;
  }

  /// Index of the first seat that still needs to act, or -1 if none. All
  /// already-played seats are stood/bust/21, so scanning from the top always
  /// lands on the correct next player.
  int _firstActionable() {
    for (var i = 0; i < state.seats.length; i++) {
      if (state.seats[i].needsAction) return i;
    }
    return -1;
  }

  /// After any player action or a mid-round leave, either move to the next
  /// actionable seat or run the dealer and settle.
  OnlineTableState _advanceAfterAction() {
    final next = _firstActionable();
    if (next < 0) return _resolve();
    state = state.copyWith(activeSeat: next);
    return state;
  }

  OnlineTableState _resolve() {
    // Reveal the hole card and let the dealer draw to a stand.
    var dealer = state.dealer.revealAll();
    while (_dealerShouldHit(dealer)) {
      dealer = dealer.addCard(_draw());
    }

    final seats = [
      for (final s in state.seats)
        if (s.inRound)
          settleSeat(s, dealer)
        else
          s,
    ];

    state = state.copyWith(
      seats: seats,
      dealer: dealer,
      phase: OnlinePhase.results,
      activeSeat: -1,
    );
    return state;
  }

  bool _dealerShouldHit(HandModel d) => dealerShouldHit(d);

  /// Whether the dealer must draw another card. Dealer hits soft 17.
  static bool dealerShouldHit(HandModel d) =>
      d.value < 17 || (d.isSoft && d.value == 17);

  /// Settle a single seat against the revealed [dealer] hand, returning the
  /// seat with its result and updated bankroll. Static and pure so it can be
  /// unit-tested with constructed hands.
  static OnlineSeat settleSeat(OnlineSeat seat, HandModel dealer) {
    final result = resolveHand(seat.hand, dealer);
    final handBet = seat.hand.isDoubled ? seat.bet * 2 : seat.bet;
    return seat.copyWith(
      bankroll: seat.bankroll + payout(result, handBet),
      result: result,
    );
  }

  static GameResult resolveHand(HandModel player, HandModel dealer) {
    final playerBJ = player.isBlackjack;
    final dealerBJ = dealer.isBlackjack;
    if (playerBJ && !dealerBJ) return GameResult.blackjack;
    if (dealerBJ && !playerBJ) return GameResult.loss;
    if (player.isBust) return GameResult.bust;
    if (dealer.isBust) return GameResult.dealerBust;
    if (player.value > dealer.value) return GameResult.win;
    if (player.value < dealer.value) return GameResult.loss;
    return GameResult.push;
  }

  /// Total chips returned to the bankroll for a settled hand (stake + profit).
  static int payout(GameResult result, int bet) {
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
}

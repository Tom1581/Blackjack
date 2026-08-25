import '../../core/engine/deck_manager.dart';
import '../../core/engine/hi_lo_counter.dart';
import '../../core/models/card_model.dart';
import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';
import 'online_state.dart';

/// Authoritative multiplayer table logic, run only on the host device. Holds
/// the shared shoe and the canonical [OnlineTableState]; every mutating method
/// validates the actor and returns the next state (also stored in [state]).
///
/// Rules mirror the single-player engine: dealer hits soft 17, blackjack pays
/// 3:2, double on any two, split up to four hands, split aces draw one card,
/// a two-card 21 from a split pays even money, insurance pays 2:1.
///
/// Every phase runs on a clock so one unresponsive player can never stall the
/// table: [tick] applies the timeout for whichever phase is current.
class OnlineTableLogic {
  final DeckManager _shoe;
  final HiLoCounter _counter;
  final DateTime Function() _now;

  OnlineTableState state;

  /// Maximum seats at an online table.
  static const maxSeats = 5;

  static const startingBankroll = 1000;

  /// Chips handed out when a broke player buys back in.
  static const rebuyAmount = 500;

  /// Smallest chip a player can put on the felt. A stack below this is as
  /// unplayable as an empty one, so it is what qualifies for a rebuy.
  static const minBet = 5;

  /// A seat may be split until the player holds this many hands.
  static const maxHandsPerSeat = 4;

  static const bettingClock = Duration(seconds: 25);
  static const insuranceClock = Duration(seconds: 12);
  static const turnClock = Duration(seconds: 25);
  static const resultsClock = Duration(seconds: 12);

  /// How long a dropped player's seat (and chips) are held for them.
  static const reconnectGrace = Duration(seconds: 60);

  DateTime? _deadline;
  final Map<String, DateTime> _droppedAt = {};

  OnlineTableLogic({
    required String roomCode,
    required String hostId,
    int numDecks = 6,
    DateTime Function()? now,
  })  : _shoe = DeckManager(numDecks: numDecks),
        _counter = HiLoCounter(totalDecks: numDecks),
        _now = now ?? DateTime.now,
        state = OnlineTableState(roomCode: roomCode, hostId: hostId) {
    _syncShoe();
  }

  // ─── Roster ────────────────────────────────────────────────────────────

  /// Seat a player, or reclaim the seat they dropped from.
  ///
  /// Reconnecting keeps the existing seat and its bankroll. Previously a
  /// presence blip deleted the seat and the rejoin minted a fresh 1000 chips,
  /// which lost real balances and let a losing player reset by force-quitting.
  OnlineTableState addPlayer(String id, String name) {
    final existing = state.seatById(id);
    if (existing != null) {
      _droppedAt.remove(id);
      if (existing.connected && existing.name == name) return state;
      return _replaceSeat(existing.copyWith(name: name, connected: true));
    }
    if (state.seats.length >= maxSeats) return state;
    final seat = OnlineSeat(id: id, name: name, bankroll: startingBankroll);
    state = state.copyWith(seats: [...state.seats, seat]);
    return state;
  }

  /// Presence lost this player. The seat is kept (so their chips survive a
  /// tunnel) but any live hand stands immediately so the round still settles
  /// instead of hanging on someone who is gone.
  OnlineTableState markDisconnected(String id) {
    final seat = state.seatById(id);
    if (seat == null) return state;
    _droppedAt[id] = _now();

    var next = seat.copyWith(connected: false, ready: true);
    if (next.inRound && next.needsAction) {
      next = next.copyWith(
        hands: [for (final h in next.hands) h.copyWith(done: true)],
      );
    }
    if (!next.insuranceAnswered) {
      next = next.copyWith(insuranceAnswered: true);
    }
    _replaceSeat(next);

    switch (state.phase) {
      case OnlinePhase.playerTurns:
        return _advance();
      case OnlinePhase.insurance:
        return _maybeLeaveInsurance();
      case OnlinePhase.betting:
      case OnlinePhase.results:
        return state;
    }
  }

  /// Drop seats whose player has been gone longer than [reconnectGrace].
  /// Only between rounds, so nobody is removed with chips on the felt.
  OnlineTableState sweepAbandonedSeats() {
    if (state.phase != OnlinePhase.betting &&
        state.phase != OnlinePhase.results) {
      return state;
    }
    final now = _now();
    final expired = _droppedAt.entries
        .where((e) => now.difference(e.value) >= reconnectGrace)
        .map((e) => e.key)
        .toList();
    if (expired.isEmpty) return state;
    for (final id in expired) {
      _droppedAt.remove(id);
    }
    state = state.copyWith(
      seats: state.seats.where((s) => !expired.contains(s.id)).toList(),
    );
    return state;
  }

  /// Host removes a player. Allowed only between rounds so no wager is voided.
  OnlineTableState kick(String actorId, String targetId) {
    if (actorId != state.hostId || targetId == state.hostId) return state;
    if (state.phase != OnlinePhase.betting &&
        state.phase != OnlinePhase.results) {
      return state;
    }
    _droppedAt.remove(targetId);
    state = state.copyWith(
      seats: state.seats.where((s) => s.id != targetId).toList(),
    );
    return state;
  }

  // ─── Betting ───────────────────────────────────────────────────────────

  OnlineTableState placeBet(String actorId, int amount) {
    if (state.phase != OnlinePhase.betting || amount <= 0) return state;
    final seat = state.seatById(actorId);
    if (seat == null) return state;
    if (seat.bet + amount > seat.bankroll) return state;
    _replaceSeat(seat.copyWith(bet: seat.bet + amount, ready: false));
    // The first chip on the felt starts a countdown everyone can see, so the
    // host can no longer deal a player out before they have had a chance.
    if (_deadline == null) _setClock(bettingClock);
    return state;
  }

  OnlineTableState clearBet(String actorId) {
    if (state.phase != OnlinePhase.betting) return state;
    final seat = state.seatById(actorId);
    if (seat == null || seat.bet == 0) return state;
    return _replaceSeat(seat.copyWith(bet: 0, ready: false));
  }

  /// "I am done betting." Once every connected seat is ready the host can deal
  /// (and the table deals itself when the betting clock runs out).
  OnlineTableState setReady(String actorId, bool ready) {
    if (state.phase != OnlinePhase.betting) return state;
    final seat = state.seatById(actorId);
    if (seat == null) return state;
    _replaceSeat(seat.copyWith(ready: ready));
    if (_deadline == null) _setClock(bettingClock);
    return state;
  }

  /// Top a broke player back up so they are not stranded as a spectator.
  /// A stack too small to cover the minimum chip counts as broke — otherwise
  /// a player left holding $3 could neither bet nor buy in.
  OnlineTableState rebuy(String actorId) {
    if (state.phase != OnlinePhase.betting) return state;
    final seat = state.seatById(actorId);
    if (seat == null || seat.bankroll >= minBet || seat.inRound) return state;
    return _replaceSeat(seat.copyWith(
      bankroll: seat.bankroll + rebuyAmount,
      rebuys: seat.rebuys + 1,
    ));
  }

  /// Host starts the deal. Only seats with a bet take cards; empty seats sit
  /// the round out. [auto] is the betting clock dealing on the host's behalf.
  OnlineTableState startDeal(String actorId, {bool auto = false}) {
    if (!auto && actorId != state.hostId) return state;
    if (state.phase != OnlinePhase.betting) return state;
    if (!auto) {
      // Tapping DEAL is the host saying they are done betting too.
      final host = state.seatById(actorId);
      if (host != null && !host.ready) _replaceSeat(host.copyWith(ready: true));
      if (!canDeal) return state;
    }

    final funded = state.seats.where((s) => s.bet > 0).toList();
    if (funded.isEmpty) {
      _setClock(null);
      return state;
    }

    if (_shoe.needsReshuffle) {
      _shoe.reset();
      _counter.reset();
    }

    // Deal one card to each funded seat, dealer up-card, a second to each, then
    // the dealer's face-down hole card (not counted until it is turned over).
    final firstCards = {for (final s in funded) s.id: _draw()};
    final dealerUp = _draw();
    final secondCards = {for (final s in funded) s.id: _draw()};
    final dealerHole = _shoe.draw(faceUp: false);

    final newSeats = [
      for (final s in state.seats)
        if (s.bet > 0)
          s.copyWith(
            bankroll: s.bankroll - s.bet,
            hands: [
              SeatHand(
                hand: HandModel(
                  cards: [firstCards[s.id]!, secondCards[s.id]!],
                  bet: s.bet,
                ),
              ),
            ],
            activeHand: 0,
            insuranceBet: 0,
            insuranceAnswered: false,
            netLastRound: 0,
          )
        else
          s.copyWith(
            hands: const [],
            activeHand: 0,
            insuranceBet: 0,
            insuranceAnswered: true,
            netLastRound: 0,
          ),
    ];

    state = state.copyWith(
      seats: newSeats,
      dealer: HandModel(cards: [dealerUp, dealerHole]),
      activeSeat: -1,
      message: null,
    );
    _syncShoe();

    // A dealer ace offers insurance before anyone acts or the hole is peeked.
    if (dealerUp.rank == Rank.ace) {
      state = state.copyWith(phase: OnlinePhase.insurance);
      _setClock(insuranceClock);
      return _maybeLeaveInsurance();
    }

    state = state.copyWith(phase: OnlinePhase.playerTurns);
    return _afterInsurance();
  }

  // ─── Insurance ─────────────────────────────────────────────────────────

  OnlineTableState answerInsurance(String actorId, bool take) {
    if (state.phase != OnlinePhase.insurance) return state;
    final seat = state.seatById(actorId);
    if (seat == null || !seat.inRound || seat.insuranceAnswered) return state;

    var cost = take ? seat.bet ~/ 2 : 0;
    if (cost > seat.bankroll) cost = 0;
    _replaceSeat(seat.copyWith(
      insuranceBet: cost,
      insuranceAnswered: true,
      bankroll: seat.bankroll - cost,
    ));
    return _maybeLeaveInsurance();
  }

  OnlineTableState _maybeLeaveInsurance() {
    if (state.phase != OnlinePhase.insurance) return state;
    final pending = state.seats
        .where((s) => s.inRound && s.connected && !s.insuranceAnswered);
    if (pending.isNotEmpty) return state;
    return _closeInsurance();
  }

  OnlineTableState _closeInsurance() {
    state = state.copyWith(
      seats: [
        for (final s in state.seats)
          s.insuranceAnswered ? s : s.copyWith(insuranceAnswered: true),
      ],
      phase: OnlinePhase.playerTurns,
    );
    return _afterInsurance();
  }

  /// Peek the hole card, then either settle immediately or start play.
  OnlineTableState _afterInsurance() {
    if (state.dealer.isBlackjack) return _resolve();
    return _advance();
  }

  // ─── Player actions (only the active seat may act) ───────────────────────

  OnlineTableState hit(String actorId) {
    final ctx = _activeIfActor(actorId);
    if (ctx == null) return state;
    final (seat, idx, sh) = ctx;
    final hand = sh.hand.addCard(_draw());
    _replaceHand(seat, idx, sh.copyWith(
      hand: hand,
      done: hand.isBust || hand.value >= 21,
    ));
    _syncShoe();
    return _advance();
  }

  OnlineTableState stand(String actorId) {
    final ctx = _activeIfActor(actorId);
    if (ctx == null) return state;
    final (seat, idx, sh) = ctx;
    _replaceHand(seat, idx, sh.copyWith(done: true));
    return _advance();
  }

  OnlineTableState doubleDown(String actorId) {
    final ctx = _activeIfActor(actorId);
    if (ctx == null) return state;
    final (seat, idx, sh) = ctx;
    if (!canDoubleHand(seat, sh)) return state;
    final hand = sh.hand.addCard(_draw()).markDoubled();
    var next = seat.copyWith(bankroll: seat.bankroll - sh.hand.bet);
    next = _withHand(next, idx, sh.copyWith(hand: hand, done: true));
    _replaceSeat(next);
    _syncShoe();
    return _advance();
  }

  OnlineTableState split(String actorId) {
    final ctx = _activeIfActor(actorId);
    if (ctx == null) return state;
    final (seat, idx, sh) = ctx;
    if (!canSplitHand(seat, sh)) return state;

    final src = sh.hand;
    final isAces = src.cards[0].rank == Rank.ace;
    final left = HandModel(
      cards: [src.cards[0], _draw()],
      bet: src.bet,
      fromSplit: true,
    );
    final right = HandModel(
      cards: [src.cards[1], _draw()],
      bet: src.bet,
      fromSplit: true,
    );

    // Split aces draw exactly one card each and stand. Any other split keeps
    // playing the first new hand unless it already reached 21.
    SeatHand wrap(HandModel h) =>
        SeatHand(hand: h, done: isAces || h.value >= 21);

    final hands = [
      ...seat.hands.sublist(0, idx),
      wrap(left),
      wrap(right),
      ...seat.hands.sublist(idx + 1),
    ];

    _replaceSeat(seat.copyWith(
      hands: hands,
      bankroll: seat.bankroll - src.bet, // one extra base bet
    ));
    _syncShoe();
    return _advance();
  }

  // ─── Round lifecycle ─────────────────────────────────────────────────────

  /// Host deals the next round: clears hands/bets/results, keeps bankrolls.
  OnlineTableState nextRound(String actorId, {bool auto = false}) {
    if (!auto && actorId != state.hostId) return state;
    if (state.phase != OnlinePhase.results) return state;

    sweepAbandonedSeats();
    final seats = [
      for (final s in state.seats)
        s.copyWith(
          bet: 0,
          hands: const [],
          activeHand: 0,
          insuranceBet: 0,
          insuranceAnswered: false,
          ready: false,
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
    _setClock(null);
    return state;
  }

  // ─── Clocks ──────────────────────────────────────────────────────────────

  /// Advance the phase clock. Called about once a second by the host; applies
  /// the timeout for whichever phase is running so nobody can stall the table.
  OnlineTableState tick() {
    sweepAbandonedSeats();
    _syncClock();
    final deadline = _deadline;
    if (deadline == null || _now().isBefore(deadline)) return state;

    switch (state.phase) {
      case OnlinePhase.betting:
        if (state.seats.any((s) => s.bet > 0)) {
          return startDeal(state.hostId, auto: true);
        }
        _setClock(null);
        return state;
      case OnlinePhase.insurance:
        return _closeInsurance();
      case OnlinePhase.playerTurns:
        final active = state.activeSeatOrNull;
        if (active == null) return _advance();
        return stand(active.id);
      case OnlinePhase.results:
        return nextRound(state.hostId, auto: true);
    }
  }

  /// Recompute the countdown the guests render. Called before every broadcast.
  OnlineTableState refreshClock() {
    _syncClock();
    return state;
  }

  // ─── Queries the UI needs ────────────────────────────────────────────────

  /// Somebody funded a seat and every *other* connected player has finished
  /// betting. The host's own readiness is not part of this — pressing DEAL is
  /// what says they are done — but nobody else can be dealt out mid-decision.
  bool get canDeal {
    if (!state.seats.any((s) => s.bet > 0)) return false;
    return state.seats
        .where((s) =>
            s.connected &&
            s.id != state.hostId &&
            // A player too broke to bet is shown the buy-in panel instead of
            // the chips, so they have no READY button to press and must not
            // hold the rest of the table up.
            s.bankroll >= minBet)
        .every((s) => s.ready);
  }

  static bool canDoubleHand(OnlineSeat seat, SeatHand sh) =>
      sh.hand.cards.length == 2 &&
      !sh.done &&
      seat.bankroll >= sh.hand.bet;

  static bool canSplitHand(OnlineSeat seat, SeatHand sh) =>
      sh.hand.isPair &&
      !sh.done &&
      seat.hands.length < maxHandsPerSeat &&
      seat.bankroll >= sh.hand.bet;

  // ─── Internals ───────────────────────────────────────────────────────────

  CardModel _draw() {
    final card = _shoe.draw(faceUp: true);
    _counter.update(card);
    return card;
  }

  void _syncShoe() {
    _counter.updateDecksRemaining(_shoe.remaining);
    state = state.copyWith(
      runningCount: _counter.runningCount,
      trueCount: _counter.trueCount,
      cardsRemaining: _shoe.remaining,
      totalCards: _shoe.totalCards,
    );
  }

  void _setClock(Duration? d) {
    _deadline = d == null ? null : _now().add(d);
    _syncClock();
  }

  void _syncClock() {
    final deadline = _deadline;
    if (deadline == null) {
      if (state.clockMs != null) state = state.copyWith(clockMs: null);
      return;
    }
    final ms = deadline.difference(_now()).inMilliseconds;
    state = state.copyWith(clockMs: ms < 0 ? 0 : ms);
  }

  OnlineTableState _replaceSeat(OnlineSeat seat) {
    state = state.copyWith(seats: [
      for (final s in state.seats)
        if (s.id == seat.id) seat else s,
    ]);
    return state;
  }

  OnlineSeat _withHand(OnlineSeat seat, int idx, SeatHand hand) => seat.copyWith(
        hands: [
          ...seat.hands.sublist(0, idx),
          hand,
          ...seat.hands.sublist(idx + 1),
        ],
      );

  void _replaceHand(OnlineSeat seat, int idx, SeatHand hand) {
    _replaceSeat(_withHand(seat, idx, hand));
  }

  /// The acting seat, the index of the hand it is playing, and that hand —
  /// or null when [actorId] is not the player whose turn it is.
  (OnlineSeat, int, SeatHand)? _activeIfActor(String actorId) {
    if (state.phase != OnlinePhase.playerTurns) return null;
    final active = state.activeSeatOrNull;
    if (active == null || active.id != actorId) return null;
    final idx = active.nextHandIndex;
    if (idx < 0) return null;
    return (active, idx, active.hands[idx]);
  }

  /// Move to whoever acts next — the next unfinished hand at this seat, then
  /// the next seat — or run the dealer when the whole table is done.
  OnlineTableState _advance() {
    for (var i = 0; i < state.seats.length; i++) {
      final seat = state.seats[i];
      final hand = seat.nextHandIndex;
      if (hand < 0) continue;
      if (seat.activeHand != hand) {
        _replaceSeat(seat.copyWith(activeHand: hand));
      }
      state = state.copyWith(activeSeat: i);
      _setClock(turnClock);
      return state;
    }
    return _resolve();
  }

  OnlineTableState _resolve() {
    // Turn the hole card over — and only now count it.
    final hole = state.dealer.cards.length > 1 ? state.dealer.cards[1] : null;
    if (hole != null && !hole.faceUp) _counter.update(hole);
    var dealer = state.dealer.revealAll();

    // A dealer with no live hand to beat does not draw. Previously the dealer
    // played out even when every player had busted, burning shoe cards on a
    // round that was already decided.
    final anyLive = state.seats.any(
      (s) => s.inRound && s.hands.any((h) => !h.hand.isBust),
    );
    if (anyLive) {
      while (dealerShouldHit(dealer)) {
        dealer = dealer.addCard(_draw());
      }
    }

    final dealerBJ = dealer.isBlackjack;
    final seats = [
      for (final s in state.seats)
        if (s.inRound || s.insuranceBet > 0)
          settleSeat(s, dealer, dealerBlackjack: dealerBJ)
        else
          s,
    ];

    state = state.copyWith(
      seats: seats,
      dealer: dealer,
      phase: OnlinePhase.results,
      activeSeat: -1,
    );
    _syncShoe();
    _setClock(resultsClock);
    return state;
  }

  /// Whether the dealer must draw another card. Dealer hits soft 17.
  static bool dealerShouldHit(HandModel d) =>
      d.value < 17 || (d.isSoft && d.value == 17);

  /// Settle every hand at a seat against the revealed [dealer], returning the
  /// seat with its results, bankroll, and round net filled in. Static and pure
  /// so it can be unit-tested with constructed hands.
  static OnlineSeat settleSeat(
    OnlineSeat seat,
    HandModel dealer, {
    bool? dealerBlackjack,
  }) {
    final dealerBJ = dealerBlackjack ?? dealer.isBlackjack;
    var returned = 0;

    // Insurance settles first and pays 2:1 — three chips back per two staked.
    if (seat.insuranceBet > 0 && dealerBJ) {
      returned += seat.insuranceBet * 3;
    }

    final hands = <SeatHand>[];
    for (final sh in seat.hands) {
      final result = resolveHand(sh.hand, dealer);
      final handBet = sh.hand.isDoubled ? sh.hand.bet * 2 : sh.hand.bet;
      returned += payout(result, handBet);
      hands.add(sh.copyWith(result: result, done: true));
    }

    return seat.copyWith(
      hands: hands,
      bankroll: seat.bankroll + returned,
      netLastRound: returned - seat.staked,
    );
  }

  /// Resolve one hand. A two-card 21 that came from a split is an ordinary 21,
  /// not a natural, so it never pays the 3:2 bonus.
  static GameResult resolveHand(HandModel player, HandModel dealer) {
    final playerBJ = !player.fromSplit && player.isBlackjack;
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

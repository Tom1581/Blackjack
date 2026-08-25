import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';

/// Wire-format version of [OnlineTableState].
///
/// Bumped whenever the shape changes. A client that receives a table from a
/// different version refuses to render it and tells the player to update,
/// rather than silently mis-parsing someone else's build.
const int onlineWireVersion = 2;

/// Phases of an online multiplayer round. Simpler than the single-player
/// [GamePhase] because several players share one dealer.
enum OnlinePhase {
  /// Players are joining and placing bets. The host starts the deal.
  betting,

  /// The dealer is showing an ace; every seat in the round answers insurance.
  insurance,

  /// Cards are dealt; players act in seat order.
  playerTurns,

  /// The round is settled and results are shown until the host deals again.
  results,
}

const _sentinel = Object();

/// One hand belonging to a seat. A seat has several of these only after a
/// split; before that there is exactly one.
class SeatHand {
  final HandModel hand;
  final GameResult? result;

  /// The player has finished acting on this hand — stood, doubled, busted,
  /// reached 21, or drawn the single card a split ace is allowed.
  final bool done;

  const SeatHand({
    this.hand = const HandModel(),
    this.result,
    this.done = false,
  });

  SeatHand copyWith({
    HandModel? hand,
    Object? result = _sentinel,
    bool? done,
  }) =>
      SeatHand(
        hand: hand ?? this.hand,
        result: result == _sentinel ? this.result : result as GameResult?,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'h': hand.toJson(),
        'r': result?.index,
        'd': done,
      };

  factory SeatHand.fromJson(Map<String, dynamic> json) => SeatHand(
        hand: HandModel.fromJson(Map<String, dynamic>.from(json['h'] as Map)),
        result: json['r'] == null ? null : GameResult.values[json['r'] as int],
        done: json['d'] as bool? ?? false,
      );
}

/// One player's seat at an online table.
class OnlineSeat {
  final String id; // stable device/player id
  final String name;
  final int bankroll;

  /// The wager staked per hand this round. Set during [OnlinePhase.betting];
  /// once cards are out each hand also carries its own copy in [HandModel.bet].
  final int bet;

  final List<SeatHand> hands;

  /// Which of [hands] this seat is currently playing.
  final int activeHand;

  final int insuranceBet;

  /// This seat has answered the insurance prompt (taken or declined).
  final bool insuranceAnswered;

  /// Presence says this player is here. A seat that drops mid-session is kept
  /// (and its chips with it) for a grace period rather than being deleted.
  final bool connected;

  /// The player has locked in their bet and is waiting for the deal.
  final bool ready;

  /// Chips won (+) or lost (−) across the whole of the last settled round.
  final int netLastRound;

  /// How many times this player has topped up after going broke.
  final int rebuys;

  const OnlineSeat({
    required this.id,
    required this.name,
    this.bankroll = 1000,
    this.bet = 0,
    this.hands = const [],
    this.activeHand = 0,
    this.insuranceBet = 0,
    this.insuranceAnswered = false,
    this.connected = true,
    this.ready = false,
    this.netLastRound = 0,
    this.rebuys = 0,
  });

  bool get inRound => hands.isNotEmpty;

  /// Index of the first hand still needing a decision, or -1 when this seat is
  /// finished for the round.
  int get nextHandIndex {
    for (var i = 0; i < hands.length; i++) {
      if (!hands[i].done) return i;
    }
    return -1;
  }

  /// Whether this seat still needs a decision during [OnlinePhase.playerTurns].
  bool get needsAction => inRound && nextHandIndex >= 0;

  SeatHand? get currentHand =>
      (activeHand >= 0 && activeHand < hands.length) ? hands[activeHand] : null;

  /// Everything this seat has put on the felt this round — used to report an
  /// honest net at settlement.
  int get staked {
    var total = insuranceBet;
    for (final h in hands) {
      total += h.hand.isDoubled ? h.hand.bet * 2 : h.hand.bet;
    }
    return total;
  }

  bool get isSplit => hands.length > 1;

  OnlineSeat copyWith({
    String? name,
    int? bankroll,
    int? bet,
    List<SeatHand>? hands,
    int? activeHand,
    int? insuranceBet,
    bool? insuranceAnswered,
    bool? connected,
    bool? ready,
    int? netLastRound,
    int? rebuys,
  }) {
    return OnlineSeat(
      id: id,
      name: name ?? this.name,
      bankroll: bankroll ?? this.bankroll,
      bet: bet ?? this.bet,
      hands: hands ?? this.hands,
      activeHand: activeHand ?? this.activeHand,
      insuranceBet: insuranceBet ?? this.insuranceBet,
      insuranceAnswered: insuranceAnswered ?? this.insuranceAnswered,
      connected: connected ?? this.connected,
      ready: ready ?? this.ready,
      netLastRound: netLastRound ?? this.netLastRound,
      rebuys: rebuys ?? this.rebuys,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bankroll': bankroll,
        'bet': bet,
        'hands': hands.map((h) => h.toJson()).toList(),
        'ah': activeHand,
        'ins': insuranceBet,
        'insA': insuranceAnswered,
        'conn': connected,
        'rdy': ready,
        'net': netLastRound,
        'rb': rebuys,
      };

  factory OnlineSeat.fromJson(Map<String, dynamic> json) => OnlineSeat(
        id: json['id'] as String,
        name: json['name'] as String,
        bankroll: json['bankroll'] as int? ?? 1000,
        bet: json['bet'] as int? ?? 0,
        hands: [
          for (final h in (json['hands'] as List? ?? const []))
            SeatHand.fromJson(Map<String, dynamic>.from(h as Map)),
        ],
        activeHand: json['ah'] as int? ?? 0,
        insuranceBet: json['ins'] as int? ?? 0,
        insuranceAnswered: json['insA'] as bool? ?? false,
        connected: json['conn'] as bool? ?? true,
        ready: json['rdy'] as bool? ?? false,
        netLastRound: json['net'] as int? ?? 0,
        rebuys: json['rb'] as int? ?? 0,
      );
}

/// The full shared state of an online table, broadcast by the host to every
/// guest. Guests render exactly this; the host owns the authoritative copy.
class OnlineTableState {
  final int version;
  final String roomCode;
  final String hostId;
  final List<OnlineSeat> seats;
  final HandModel dealer;
  final OnlinePhase phase;

  /// Index into [seats] whose turn it is during [OnlinePhase.playerTurns];
  /// -1 when no one is acting.
  final int activeSeat;

  final int round;

  /// Monotonic broadcast counter. Guests drop anything not newer than what
  /// they already hold, so a delayed or duplicated message can never rewind
  /// the table.
  final int seq;

  /// Milliseconds left on whatever clock the current phase is running (betting
  /// countdown, insurance prompt, or the active player's turn). Null when no
  /// clock is ticking. Sent as a duration rather than a wall-clock deadline so
  /// it survives clock skew between devices.
  final int? clockMs;

  final String? message;

  // ─── Shared shoe telemetry (the whole point of this app) ────────────────
  final int runningCount;
  final double trueCount;
  final int cardsRemaining;
  final int totalCards;

  const OnlineTableState({
    required this.roomCode,
    required this.hostId,
    this.version = onlineWireVersion,
    this.seats = const [],
    this.dealer = const HandModel(),
    this.phase = OnlinePhase.betting,
    this.activeSeat = -1,
    this.round = 0,
    this.seq = 0,
    this.clockMs,
    this.message,
    this.runningCount = 0,
    this.trueCount = 0,
    this.cardsRemaining = 0,
    this.totalCards = 0,
  });

  OnlineSeat? seatById(String id) {
    for (final s in seats) {
      if (s.id == id) return s;
    }
    return null;
  }

  int seatIndexById(String id) {
    for (var i = 0; i < seats.length; i++) {
      if (seats[i].id == id) return i;
    }
    return -1;
  }

  OnlineSeat? get activeSeatOrNull =>
      (activeSeat >= 0 && activeSeat < seats.length) ? seats[activeSeat] : null;

  bool isActivePlayer(String id) {
    final s = activeSeatOrNull;
    return s != null && s.id == id;
  }

  double get penetration =>
      totalCards == 0 ? 0 : 1 - (cardsRemaining / totalCards);

  OnlineTableState copyWith({
    List<OnlineSeat>? seats,
    HandModel? dealer,
    OnlinePhase? phase,
    int? activeSeat,
    int? round,
    int? seq,
    Object? clockMs = _sentinel,
    Object? message = _sentinel,
    int? runningCount,
    double? trueCount,
    int? cardsRemaining,
    int? totalCards,
  }) {
    return OnlineTableState(
      version: version,
      roomCode: roomCode,
      hostId: hostId,
      seats: seats ?? this.seats,
      dealer: dealer ?? this.dealer,
      phase: phase ?? this.phase,
      activeSeat: activeSeat ?? this.activeSeat,
      round: round ?? this.round,
      seq: seq ?? this.seq,
      clockMs: clockMs == _sentinel ? this.clockMs : clockMs as int?,
      message: message == _sentinel ? this.message : message as String?,
      runningCount: runningCount ?? this.runningCount,
      trueCount: trueCount ?? this.trueCount,
      cardsRemaining: cardsRemaining ?? this.cardsRemaining,
      totalCards: totalCards ?? this.totalCards,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': version,
        'roomCode': roomCode,
        'hostId': hostId,
        'seats': seats.map((s) => s.toJson()).toList(),
        'dealer': dealer.toJson(),
        'phase': phase.index,
        'activeSeat': activeSeat,
        'round': round,
        'seq': seq,
        'clock': clockMs,
        'message': message,
        'rc': runningCount,
        'tc': trueCount,
        'cr': cardsRemaining,
        'tot': totalCards,
      };

  factory OnlineTableState.fromJson(Map<String, dynamic> json) =>
      OnlineTableState(
        version: json['v'] as int? ?? 1,
        roomCode: json['roomCode'] as String,
        hostId: json['hostId'] as String,
        seats: [
          for (final s in (json['seats'] as List? ?? const []))
            OnlineSeat.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        dealer:
            HandModel.fromJson(Map<String, dynamic>.from(json['dealer'] as Map)),
        phase: OnlinePhase.values[json['phase'] as int],
        activeSeat: json['activeSeat'] as int? ?? -1,
        round: json['round'] as int? ?? 0,
        seq: json['seq'] as int? ?? 0,
        clockMs: json['clock'] as int?,
        message: json['message'] as String?,
        runningCount: json['rc'] as int? ?? 0,
        trueCount: (json['tc'] as num?)?.toDouble() ?? 0,
        cardsRemaining: json['cr'] as int? ?? 0,
        totalCards: json['tot'] as int? ?? 0,
      );
}

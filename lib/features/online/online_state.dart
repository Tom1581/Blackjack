import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';

/// Phases of an online multiplayer round. Simpler than the single-player
/// [GamePhase] because several players share one dealer.
enum OnlinePhase {
  /// Players are joining and placing bets. The host starts the deal.
  betting,

  /// Cards are dealt; players act in seat order.
  playerTurns,

  /// The round is settled and results are shown until the host deals again.
  results,
}

/// One player's seat at an online table.
class OnlineSeat {
  final String id; // stable device/player id
  final String name;
  final int bankroll;
  final int bet;
  final HandModel hand;
  final GameResult? result;

  /// The player has finished acting this round (stood, doubled, busted, or 21).
  final bool stood;

  const OnlineSeat({
    required this.id,
    required this.name,
    this.bankroll = 1000,
    this.bet = 0,
    this.hand = const HandModel(),
    this.result,
    this.stood = false,
  });

  bool get inRound => bet > 0 && hand.cards.isNotEmpty;

  /// Whether this seat still needs a decision during [OnlinePhase.playerTurns].
  bool get needsAction =>
      inRound && !stood && !hand.isBust && hand.value < 21;

  OnlineSeat copyWith({
    String? name,
    int? bankroll,
    int? bet,
    HandModel? hand,
    Object? result = _sentinel,
    bool? stood,
  }) {
    return OnlineSeat(
      id: id,
      name: name ?? this.name,
      bankroll: bankroll ?? this.bankroll,
      bet: bet ?? this.bet,
      hand: hand ?? this.hand,
      result: result == _sentinel ? this.result : result as GameResult?,
      stood: stood ?? this.stood,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bankroll': bankroll,
        'bet': bet,
        'hand': hand.toJson(),
        'result': result?.index,
        'stood': stood,
      };

  factory OnlineSeat.fromJson(Map<String, dynamic> json) => OnlineSeat(
        id: json['id'] as String,
        name: json['name'] as String,
        bankroll: json['bankroll'] as int? ?? 1000,
        bet: json['bet'] as int? ?? 0,
        hand: HandModel.fromJson(Map<String, dynamic>.from(json['hand'] as Map)),
        result: json['result'] == null
            ? null
            : GameResult.values[json['result'] as int],
        stood: json['stood'] as bool? ?? false,
      );
}

const _sentinel = Object();

/// The full shared state of an online table, broadcast by the host to every
/// guest. Guests render exactly this; the host owns the authoritative copy.
class OnlineTableState {
  final String roomCode;
  final String hostId;
  final List<OnlineSeat> seats;
  final HandModel dealer;
  final OnlinePhase phase;

  /// Index into [seats] whose turn it is during [OnlinePhase.playerTurns];
  /// -1 when no one is acting.
  final int activeSeat;

  final int round;
  final String? message;

  const OnlineTableState({
    required this.roomCode,
    required this.hostId,
    this.seats = const [],
    this.dealer = const HandModel(),
    this.phase = OnlinePhase.betting,
    this.activeSeat = -1,
    this.round = 0,
    this.message,
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

  OnlineTableState copyWith({
    List<OnlineSeat>? seats,
    HandModel? dealer,
    OnlinePhase? phase,
    int? activeSeat,
    int? round,
    Object? message = _sentinel,
  }) {
    return OnlineTableState(
      roomCode: roomCode,
      hostId: hostId,
      seats: seats ?? this.seats,
      dealer: dealer ?? this.dealer,
      phase: phase ?? this.phase,
      activeSeat: activeSeat ?? this.activeSeat,
      round: round ?? this.round,
      message: message == _sentinel ? this.message : message as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'hostId': hostId,
        'seats': seats.map((s) => s.toJson()).toList(),
        'dealer': dealer.toJson(),
        'phase': phase.index,
        'activeSeat': activeSeat,
        'round': round,
        'message': message,
      };

  factory OnlineTableState.fromJson(Map<String, dynamic> json) =>
      OnlineTableState(
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
        message: json['message'] as String?,
      );
}

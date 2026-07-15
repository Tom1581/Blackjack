import 'hand_model.dart';

enum GamePhase { betting, dealing, playerTurn, dealerTurn, result }

enum GameResult { win, loss, push, blackjack, bust, dealerBust }

enum InsuranceState { notOffered, offered, taken, declined }

class GameState {
  final GamePhase phase;
  final List<HandModel> playerHands;
  final int activeHandIndex;
  final HandModel dealerHand;
  final int bankroll;

  // Total main wager across every betting spot for the current hand. During
  // the betting phase this equals the sum of [spotBets]; after the deal it is
  // the total staked on all dealt hands.
  final int currentBet;

  // Per-spot pending main bet during the betting phase. The list length is the
  // number of betting spots the player has enabled (1–3). A spot with a bet of
  // 0 is skipped when the cards are dealt.
  final List<int> spotBets;

  final int insuranceBet;
  final int sideBet;
  final int runningCount;
  final double trueCount;
  final double deckPenetration; // 0.0–1.0
  final int cardsRemaining;
  final List<GameResult?> handResults;
  final InsuranceState insuranceState;

  // Net chips won (+) or lost (−) across the whole round, computed at
  // settlement. Aggregates every hand plus the side and insurance bets so the
  // result banner can show one honest number even with multiple hands.
  final int roundNet;

  final String? message;

  const GameState({
    this.phase = GamePhase.betting,
    this.playerHands = const [HandModel()],
    this.activeHandIndex = 0,
    this.dealerHand = const HandModel(),
    this.bankroll = 1000,
    this.currentBet = 0,
    this.spotBets = const [0],
    this.insuranceBet = 0,
    this.sideBet = 0,
    this.runningCount = 0,
    this.trueCount = 0,
    this.deckPenetration = 0,
    this.cardsRemaining = 312,
    this.handResults = const [null],
    this.insuranceState = InsuranceState.notOffered,
    this.roundNet = 0,
    this.message,
  });

  HandModel get activeHand => playerHands[activeHandIndex];

  bool get allHandsPlayed => activeHandIndex >= playerHands.length;

  /// Number of betting spots currently enabled.
  int get spotCount => spotBets.length;

  GameState copyWith({
    GamePhase? phase,
    List<HandModel>? playerHands,
    int? activeHandIndex,
    HandModel? dealerHand,
    int? bankroll,
    int? currentBet,
    List<int>? spotBets,
    int? insuranceBet,
    int? sideBet,
    int? runningCount,
    double? trueCount,
    double? deckPenetration,
    int? cardsRemaining,
    List<GameResult?>? handResults,
    InsuranceState? insuranceState,
    int? roundNet,
    String? message,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      playerHands: playerHands ?? this.playerHands,
      activeHandIndex: activeHandIndex ?? this.activeHandIndex,
      dealerHand: dealerHand ?? this.dealerHand,
      bankroll: bankroll ?? this.bankroll,
      currentBet: currentBet ?? this.currentBet,
      spotBets: spotBets ?? this.spotBets,
      insuranceBet: insuranceBet ?? this.insuranceBet,
      sideBet: sideBet ?? this.sideBet,
      runningCount: runningCount ?? this.runningCount,
      trueCount: trueCount ?? this.trueCount,
      deckPenetration: deckPenetration ?? this.deckPenetration,
      cardsRemaining: cardsRemaining ?? this.cardsRemaining,
      handResults: handResults ?? this.handResults,
      insuranceState: insuranceState ?? this.insuranceState,
      roundNet: roundNet ?? this.roundNet,
      message: message ?? this.message,
    );
  }
}

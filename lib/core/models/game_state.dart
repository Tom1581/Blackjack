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
  final int currentBet;
  // The base wager set at deal-time — the per-hand stake before any
  // splits or doubles. Used for accurate per-hand payouts.
  final int originalBet;
  final int insuranceBet;
  final int sideBet;
  final int runningCount;
  final double trueCount;
  final double deckPenetration; // 0.0–1.0
  final int cardsRemaining;
  final List<GameResult?> handResults;
  final InsuranceState insuranceState;
  final String? message;

  const GameState({
    this.phase = GamePhase.betting,
    this.playerHands = const [HandModel()],
    this.activeHandIndex = 0,
    this.dealerHand = const HandModel(),
    this.bankroll = 1000,
    this.currentBet = 0,
    this.originalBet = 0,
    this.insuranceBet = 0,
    this.sideBet = 0,
    this.runningCount = 0,
    this.trueCount = 0,
    this.deckPenetration = 0,
    this.cardsRemaining = 312,
    this.handResults = const [null],
    this.insuranceState = InsuranceState.notOffered,
    this.message,
  });

  HandModel get activeHand => playerHands[activeHandIndex];

  bool get allHandsPlayed => activeHandIndex >= playerHands.length;

  GameState copyWith({
    GamePhase? phase,
    List<HandModel>? playerHands,
    int? activeHandIndex,
    HandModel? dealerHand,
    int? bankroll,
    int? currentBet,
    int? originalBet,
    int? insuranceBet,
    int? sideBet,
    int? runningCount,
    double? trueCount,
    double? deckPenetration,
    int? cardsRemaining,
    List<GameResult?>? handResults,
    InsuranceState? insuranceState,
    String? message,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      playerHands: playerHands ?? this.playerHands,
      activeHandIndex: activeHandIndex ?? this.activeHandIndex,
      dealerHand: dealerHand ?? this.dealerHand,
      bankroll: bankroll ?? this.bankroll,
      currentBet: currentBet ?? this.currentBet,
      originalBet: originalBet ?? this.originalBet,
      insuranceBet: insuranceBet ?? this.insuranceBet,
      sideBet: sideBet ?? this.sideBet,
      runningCount: runningCount ?? this.runningCount,
      trueCount: trueCount ?? this.trueCount,
      deckPenetration: deckPenetration ?? this.deckPenetration,
      cardsRemaining: cardsRemaining ?? this.cardsRemaining,
      handResults: handResults ?? this.handResults,
      insuranceState: insuranceState ?? this.insuranceState,
      message: message ?? this.message,
    );
  }
}

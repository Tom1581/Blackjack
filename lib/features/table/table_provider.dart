import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/engine/game_engine.dart';
import '../../core/models/game_state.dart';
import '../leaderboard/leaderboard_providers.dart';
import '../leaderboard/leaderboard_service.dart';

enum ShoeMode {
  /// Continuous shuffle machine — deck reshuffled after every hand.
  /// Card counting provides no benefit.
  continuousShuffle,

  /// 2-deck shoe — common pitch-game format. Higher penetration, easier
  /// counts, but smaller shoe means more reshuffles.
  twoDeck,

  /// 6-deck shoe — standard casino format. Counting still works but the
  /// True Count divides by ~6 decks so swings are smaller.
  sixDeck,
}

extension ShoeModeProps on ShoeMode {
  int get numDecks {
    switch (this) {
      case ShoeMode.continuousShuffle:
        return 6;
      case ShoeMode.twoDeck:
        return 2;
      case ShoeMode.sixDeck:
        return 6;
    }
  }

  bool get isContinuous => this == ShoeMode.continuousShuffle;
}

final shoeModeProvider = StateProvider<ShoeMode>((ref) => ShoeMode.sixDeck);

/// How many main betting spots (hands) the player plays at once. 1 is the
/// classic single-hand game; 2–3 deal that many simultaneous hands. Chosen in
/// the lobby before sitting down.
final spotCountProvider = StateProvider<int>((ref) => 1);

/// Which betting circle the next chip click should land in: the main wager
/// or the dealer-bust side bet.
enum BetTarget { main, side }

final betTargetProvider = StateProvider<BetTarget>((ref) => BetTarget.main);

/// Which main betting spot the next chip lands in (0-based). Only meaningful
/// while [betTargetProvider] is [BetTarget.main].
final activeSpotProvider = StateProvider<int>((ref) => 0);

/// Backwards-compatible deck count derived from the shoe mode.
final deckCountProvider = Provider<int>((ref) {
  return ref.watch(shoeModeProvider).numDecks;
});

final _engineProvider = Provider<GameEngine>((ref) {
  final mode = ref.watch(shoeModeProvider);
  return GameEngine(numDecks: mode.numDecks, continuous: mode.isContinuous);
});

final showCountProvider = StateProvider<bool>((ref) => true);

final tableProvider = NotifierProvider<TableNotifier, GameState>(TableNotifier.new);

class TableNotifier extends Notifier<GameState> {
  late GameEngine _engine;
  int? _bankrollBeforeHand; // snapshot at deal() to compute weekly delta

  @override
  GameState build() {
    _engine = ref.read(_engineProvider);
    final spots = ref.read(spotCountProvider);
    ref.listen(shoeModeProvider, (_, __) {
      _engine = ref.read(_engineProvider);
      state = _freshBetting(state.bankroll, ref.read(spotCountProvider));
      _resetSelectors();
    });
    // Changing the number of hands in the lobby re-lays the empty spots — but
    // only while betting, so a live round is never disturbed.
    ref.listen(spotCountProvider, (_, next) {
      if (state.phase == GamePhase.betting) {
        state = _freshBetting(state.bankroll, next);
        _resetSelectors();
      }
    });
    // Note: initial selectors already default to spot 0 / main. We intentionally
    // do NOT mutate them here — a provider must not modify other providers
    // during its own build.
    return _freshBetting(_loadBankroll(), spots);
  }

  /// A clean betting-phase state with [count] empty spots. Pure — it does not
  /// touch other providers, so it is safe to call from [build].
  GameState _freshBetting(int bankroll, int count) {
    final n = count.clamp(1, GameEngine.maxSpots);
    return GameState(
      bankroll: bankroll,
      spotBets: List<int>.filled(n, 0),
    );
  }

  /// Point the chip selectors back at spot 1 / main. Only call from event
  /// handlers (listeners, actions) — never from [build].
  void _resetSelectors() {
    ref.read(activeSpotProvider.notifier).state = 0;
    ref.read(betTargetProvider.notifier).state = BetTarget.main;
  }

  int _loadBankroll() => 1000; // default; actual persistence is async below

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('bankroll') ?? 1000;
    state = state.copyWith(bankroll: saved);
  }

  Future<void> _saveBankroll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bankroll', state.bankroll);
  }

  void addChip(int amount) {
    if (state.phase != GamePhase.betting) return;
    if (state.currentBet + state.sideBet + amount > state.bankroll) return;
    final spot = ref.read(activeSpotProvider).clamp(0, state.spotCount - 1);
    state = _engine.placeBet(state, amount, spot);
  }

  /// Add to the dealer-bust side bet (max $50). Silently ignored if the
  /// chip would exceed either the bankroll or the side-bet cap.
  void addSideChip(int amount) {
    if (state.phase != GamePhase.betting) return;
    state = _engine.placeSideBet(state, amount);
  }

  void clearBet() {
    if (state.phase != GamePhase.betting) return;
    state = _engine.clearBet(state);
  }

  void deal() {
    if (state.phase != GamePhase.betting || state.currentBet == 0) return;
    _bankrollBeforeHand = state.bankroll;
    state = state.copyWith(phase: GamePhase.dealing);
    state = _engine.dealInitial(state);
    _onAction();
  }

  void takeInsurance(bool take) {
    state = _engine.handleInsurance(state, take);
    _onAction();
  }

  void hit() {
    if (state.phase != GamePhase.playerTurn) return;
    state = _engine.hit(state);
    _onAction();
  }

  void stand() {
    if (state.phase != GamePhase.playerTurn) return;
    state = _engine.stand(state);
    _onAction();
  }

  void doubleDown() {
    if (state.phase != GamePhase.playerTurn) return;
    if (!state.activeHand.canDouble) return;
    // Doubling stakes one extra base bet for *this* hand only — affordability
    // is per-hand, not the cumulative total across all hands.
    if (state.bankroll < state.activeHand.bet) return;
    state = _engine.doubleDown(state);
    _onAction();
  }

  void split() {
    if (state.phase != GamePhase.playerTurn) return;
    if (!state.activeHand.isPair) return;
    // Splitting also stakes exactly one more base bet (so re-splits remain
    // affordable as long as one more of this hand's bet is left).
    if (state.bankroll < state.activeHand.bet) return;
    state = _engine.split(state);
    _onAction();
  }

  /// Common post-action hook. If the engine has handed off to the dealer,
  /// kick off the paced reveal sequence; otherwise just persist progress.
  void _onAction() {
    if (state.phase == GamePhase.dealerTurn) {
      _runDealerSequence();
    } else {
      _maybeAutoFinish();
    }
  }

  // Pacing constants for the dealer reveal — slow enough that each card
  // registers visually instead of all popping in at once.
  static const _dealerHoleRevealPause = Duration(milliseconds: 380);
  static const _dealerAfterRevealPause = Duration(milliseconds: 800);
  static const _dealerBetweenHitsPause = Duration(milliseconds: 720);
  static const _dealerBeforeResolvePause = Duration(milliseconds: 480);

  Future<void> _runDealerSequence() async {
    // Brief beat so the player's last card lands first.
    await Future.delayed(_dealerHoleRevealPause);
    if (!_stillInDealerTurn()) return;

    // Flip the hole card.
    state = _engine.revealDealerHole(state);
    await Future.delayed(_dealerAfterRevealPause);
    if (!_stillInDealerTurn()) return;

    // Draw additional dealer cards one at a time, paced for the eye.
    while (_engine.dealerShouldHit(state)) {
      state = _engine.dealerHit(state);
      await Future.delayed(_dealerBetweenHitsPause);
      if (!_stillInDealerTurn()) return;
    }

    // Settle the books.
    await Future.delayed(_dealerBeforeResolvePause);
    if (!_stillInDealerTurn()) return;
    state = _engine.resolveAll(state);
    _maybeAutoFinish();
  }

  /// Guard against the rare case where the user backs out of the table
  /// mid-sequence (notifier disposed) — Dart will throw if we keep mutating
  /// state. Riverpod sets phase to [GamePhase.betting] on rebuild, so
  /// anything other than dealerTurn means we should bail.
  bool _stillInDealerTurn() => state.phase == GamePhase.dealerTurn;

  void nextHand() {
    state = _engine.newHand(state);
    // Re-lay the spots to match the currently selected hand count (it may have
    // changed since the round started) and reset the spot/target selectors.
    final count = ref.read(spotCountProvider).clamp(1, GameEngine.maxSpots);
    state = state.copyWith(spotBets: List<int>.filled(count, 0));
    _resetSelectors();
    _saveBankroll();
  }

  /// Award chips (e.g. from watching a rewarded ad).
  void addReward(int amount) {
    state = state.copyWith(bankroll: state.bankroll + amount);
    _saveBankroll();
  }

  void _maybeAutoFinish() {
    if (state.phase == GamePhase.result) {
      _saveBankroll();
      _recordWeeklyDelta();
    }
  }

  void _recordWeeklyDelta() {
    final snapshot = _bankrollBeforeHand;
    _bankrollBeforeHand = null;
    if (snapshot == null) return;
    final delta = state.bankroll - snapshot;
    if (delta != 0) {
      LeaderboardService.recordHand(delta).then((_) {
        // Bump the refresh tick so the lobby Top-3 and the leaderboard
        // screen pick up the new profit immediately.
        ref.read(boardRefreshTickProvider.notifier).state++;
      });
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/audio/sound_service.dart';
import '../../core/engine/game_engine.dart';
import '../../core/models/card_model.dart';
import '../../core/models/game_state.dart';
import '../../core/rules/rule_set.dart';
import '../../core/rules/rules_store.dart';
import '../../core/strategy/basic_strategy.dart';
import '../../core/strategy/strategy_coach.dart';
import '../../core/reviews/review_prompter.dart';
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

/// The table the player is practising against. Changing it re-deals the felt
/// but never disturbs a live round — see the listener in [TableNotifier.build].
final rulesProvider = StateProvider<RuleSet>((ref) => RulesStore.current);

final _engineProvider = Provider<GameEngine>((ref) {
  final mode = ref.watch(shoeModeProvider);
  return GameEngine(
    numDecks: mode.numDecks,
    continuous: mode.isContinuous,
    rules: ref.watch(rulesProvider),
  );
});

final showCountProvider = StateProvider<bool>((ref) => true);

/// Whether the table would allow doubling the active hand right now. The
/// action bar reads this rather than assuming any particular rule.
final canDoubleProvider = Provider<bool>((ref) {
  final state = ref.watch(tableProvider);
  if (state.phase != GamePhase.playerTurn) return false;
  return ref.watch(_engineProvider).canDoubleActiveHand(state);
});

/// Whether the table would allow splitting the active hand right now.
final canSplitProvider = Provider<bool>((ref) {
  final state = ref.watch(tableProvider);
  if (state.phase != GamePhase.playerTurn) return false;
  return ref.watch(_engineProvider).canSplitActiveHand(state);
});

/// The most recent misplay, shown briefly next to the action bar and cleared
/// on the next decision.
final strategyFeedbackProvider = StateProvider<StrategyFeedback?>((ref) => null);

/// What basic strategy would do with the hand in front of the player right
/// now, or null when it is not their turn. Drives the hint on the action bar.
final strategyHintProvider = Provider<StrategyMove?>((ref) {
  final state = ref.watch(tableProvider);
  if (state.phase != GamePhase.playerTurn) return null;
  if (state.dealerHand.cards.isEmpty) return null;
  final hand = state.activeHand;
  if (hand.cards.length < 2) return null;
  final engine = ref.watch(_engineProvider);
  return BasicStrategy.best(
    hand: hand,
    dealerUp: state.dealerHand.cards.first,
    canDouble: engine.canDoubleActiveHand(state),
    canSplit: engine.canSplitActiveHand(state),
    rules: engine.rules,
  );
});

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
    // Switching tables starts a fresh shoe under the new rules.
    ref.listen(rulesProvider, (_, __) {
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
    SoundService.play(Sfx.chip);
  }

  /// Add to the dealer-bust side bet (max $50). Silently ignored if the
  /// chip would exceed either the bankroll or the side-bet cap.
  void addSideChip(int amount) {
    if (state.phase != GamePhase.betting) return;
    state = _engine.placeSideBet(state, amount);
    SoundService.play(Sfx.chip);
  }

  void clearBet() {
    if (state.phase != GamePhase.betting) return;
    state = _engine.clearBet(state);
  }

  void deal() {
    if (state.phase != GamePhase.betting || state.currentBet == 0) return;
    ref.read(strategyFeedbackProvider.notifier).state = null;
    _bankrollBeforeHand = state.bankroll;
    state = state.copyWith(phase: GamePhase.dealing);
    state = _engine.dealInitial(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  void takeInsurance(bool take) {
    state = _engine.handleInsurance(state, take);
    _onAction();
  }

  void hit() {
    if (state.phase != GamePhase.playerTurn) return;
    _scoreDecision(StrategyMove.hit);
    state = _engine.hit(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  void stand() {
    if (state.phase != GamePhase.playerTurn) return;
    _scoreDecision(StrategyMove.stand);
    state = _engine.stand(state);
    _onAction();
  }

  void doubleDown() {
    if (state.phase != GamePhase.playerTurn) return;
    // Whether a double is legal — two cards, affordable, permitted by the
    // table's doubling rule, and allowed after a split — is the rules' call.
    if (!_engine.canDoubleActiveHand(state)) return;
    _scoreDecision(StrategyMove.double);
    state = _engine.doubleDown(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  void split() {
    if (state.phase != GamePhase.playerTurn) return;
    // Pair, affordable, and within the table's hand limit.
    if (!_engine.canSplitActiveHand(state)) return;
    _scoreDecision(StrategyMove.split);
    state = _engine.split(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  /// Compare what the player just did with what basic strategy says, record
  /// it, and surface the difference. Called before the state moves on, because
  /// the decision has to be judged on the hand they were actually looking at.
  void _scoreDecision(StrategyMove played) {
    final dealer = state.dealerHand;
    if (dealer.cards.isEmpty) return;
    final hand = state.activeHand;
    if (hand.cards.length < 2) return;

    final best = BasicStrategy.best(
      hand: hand,
      dealerUp: dealer.cards.first,
      canDouble: _engine.canDoubleActiveHand(state),
      canSplit: _engine.canSplitActiveHand(state),
      rules: _engine.rules,
    );
    final correct = best == played;
    StrategyCoach.record(correct: correct);
    ref.read(strategyFeedbackProvider.notifier).state = correct
        ? null
        : StrategyFeedback(
            played: played,
            best: best,
            handValue: hand.value,
            handWasSoft: hand.isSoft,
            dealerUp: dealer.cards.first.rank.display,
          );
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
    SoundService.play(Sfx.card);
    await Future.delayed(_dealerAfterRevealPause);
    if (!_stillInDealerTurn()) return;

    // Draw additional dealer cards one at a time, paced for the eye.
    while (_engine.dealerShouldHit(state)) {
      state = _engine.dealerHit(state);
      SoundService.play(Sfx.card);
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
      _playOutcome();
      _saveBankroll();
      _recordWeeklyDelta();
    }
  }

  /// One sound per round, picked from the best thing that happened — a
  /// blackjack on any hand is worth hearing about even alongside a loss.
  void _playOutcome() {
    if (state.handResults.contains(GameResult.blackjack)) {
      SoundService.play(Sfx.blackjack);
    } else if (state.roundNet > 0) {
      SoundService.play(Sfx.win);
    } else if (state.roundNet < 0) {
      SoundService.play(Sfx.lose);
    } else {
      SoundService.play(Sfx.push);
    }
  }

  void _recordWeeklyDelta() {
    final snapshot = _bankrollBeforeHand;
    _bankrollBeforeHand = null;
    if (snapshot == null) return;
    final delta = state.bankroll - snapshot;
    // A finished round is the natural place to ask for a rating — but only
    // after a win, and only at the milestones ReviewPrompter enforces.
    ReviewPrompter.onRoundFinished(delta);
    if (delta != 0) {
      LeaderboardService.recordHand(delta).then((_) {
        // Bump the refresh tick so the lobby Top-3 and the leaderboard
        // screen pick up the new profit immediately.
        ref.read(boardRefreshTickProvider.notifier).state++;
      });
    }
  }
}

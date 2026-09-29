import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/audio/sound_service.dart';
import '../../core/engine/game_engine.dart';
import '../../core/models/card_model.dart';
import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';
import '../../core/progress/player_stats.dart';
import '../../core/rules/rule_set.dart';
import '../../core/rules/rules_store.dart';
import '../../core/strategy/basic_strategy.dart';
import '../../core/strategy/bet_ramp.dart';
import '../../core/strategy/deviations.dart';
import '../../core/strategy/strategy_coach.dart';
import '../../core/strategy/table_coach.dart';
import '../../core/reviews/review_prompter.dart';
import '../../core/settings/table_prefs.dart';
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

  /// 8-deck shoe — Atlantic City and most of Asia. The multi-deck chart is
  /// correct here too; the count just moves more slowly still.
  eightDeck,
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
      case ShoeMode.eightDeck:
        return 8;
    }
  }

  bool get isContinuous => this == ShoeMode.continuousShuffle;

  static ShoeMode fromName(String? name) {
    for (final mode in ShoeMode.values) {
      if (mode.name == name) return mode;
    }
    return ShoeMode.sixDeck;
  }
}

/// Remembered across launches — see [TablePrefs].
final shoeModeProvider =
    StateProvider<ShoeMode>((ref) => ShoeModeProps.fromName(TablePrefs.shoe));

/// How many main betting spots (hands) the player plays at once. 1 is the
/// classic single-hand game; 2–3 deal that many simultaneous hands. Chosen in
/// the lobby before sitting down.
final spotCountProvider = StateProvider<int>((ref) => TablePrefs.spots);

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

final showCountProvider = StateProvider<bool>((ref) => TablePrefs.showCount);

/// Whether the table quizzes the running count every few rounds while the
/// HUD is hidden. Has no effect while the HUD is showing the answer.
final countCheckEnabledProvider =
    StateProvider<bool>((ref) => TablePrefs.countCheck);

/// Whether the coach grades against the Hi-Lo index plays (Illustrious 18 and
/// Fab 4) rather than basic strategy alone.
final indexPlaysProvider = StateProvider<bool>((ref) => TablePrefs.indexPlays);

/// Whether the betting panel shows, and the deal checks, the bet the true
/// count calls for.
final betCoachProvider = StateProvider<bool>((ref) => TablePrefs.betCoach);

/// The player's betting unit for the bet-spread coach.
final betUnitProvider = StateProvider<int>((ref) => TablePrefs.betUnit);

/// Rounds between running-count quizzes.
const countCheckEvery = 5;

/// A running-count quiz waiting for the player's answer.
class CountCheck {
  /// The running count the player should be holding.
  final int answer;

  const CountCheck(this.answer);
}

/// The open count quiz, or null. Set by [TableNotifier.nextHand].
final countCheckProvider = StateProvider<CountCheck?>((ref) => null);

/// The engine dealing the round on the table right now.
///
/// Owned by [TableNotifier] rather than derived from the settings: when the
/// rules or shoe change mid-round the new engine waits until the round is
/// settled, and until then the buttons, the coach and the felt must all
/// describe the table actually being played.
final tableEngineProvider = Provider<GameEngine>((ref) {
  ref.watch(tableProvider); // re-read whenever the table moves
  return ref.read(tableProvider.notifier).engine;
});

/// The rules of the round being played — what the felt should print.
final tableRulesProvider =
    Provider<RuleSet>((ref) => ref.watch(tableEngineProvider).rules);

/// Whether REBET can put last round's bets back down right now.
final canRebetProvider = Provider<bool>((ref) {
  final state = ref.watch(tableProvider);
  if (state.phase != GamePhase.betting) return false;
  if (state.currentBet > 0 || state.sideBet > 0) return false;
  return ref.watch(tableEngineProvider).rebetFor(state) != null;
});

/// Whether the player is being asked to act on a hand right now: their turn,
/// a real hand to act on, and no insurance question in front of it.
bool _awaitingDecision(GameState state) =>
    state.phase == GamePhase.playerTurn &&
    state.hasActiveHand &&
    state.insuranceState != InsuranceState.offered;

/// Whether the table would allow doubling the active hand right now. The
/// action bar reads this rather than assuming any particular rule.
final canDoubleProvider = Provider<bool>((ref) {
  final state = ref.watch(tableProvider);
  if (!_awaitingDecision(state)) return false;
  return ref.watch(tableEngineProvider).canDoubleActiveHand(state);
});

/// Whether the table would allow splitting the active hand right now.
final canSplitProvider = Provider<bool>((ref) {
  final state = ref.watch(tableProvider);
  if (!_awaitingDecision(state)) return false;
  return ref.watch(tableEngineProvider).canSplitActiveHand(state);
});

/// Whether the table would allow surrendering the active hand right now.
final canSurrenderProvider = Provider<bool>((ref) {
  final state = ref.watch(tableProvider);
  if (!_awaitingDecision(state)) return false;
  return ref.watch(tableEngineProvider).canSurrenderActiveHand(state);
});

/// The most recent misplay, shown briefly next to the action bar and cleared
/// on the next decision.
final strategyFeedbackProvider =
    StateProvider<StrategyFeedback?>((ref) => null);

/// The coach's pick for the hand in front of the player right now, or null
/// when it is not their turn. Drives the hint on the action bar.
///
/// With index plays on and the count HUD hidden, a hand an index play governs
/// gets no hint: the hint would give the count away.
final strategyHintProvider = Provider<StrategyMove?>((ref) {
  final state = ref.watch(tableProvider);
  if (!_awaitingDecision(state)) return null;
  final verdict = TableCoach.verdict(
    state,
    ref.watch(tableEngineProvider),
    indexPlays: ref.watch(indexPlaysProvider),
  );
  if (verdict == null) return null;
  if (verdict.index != null && !ref.watch(showCountProvider)) return null;
  return verdict.best;
});

final tableProvider =
    NotifierProvider<TableNotifier, GameState>(TableNotifier.new);

class TableNotifier extends Notifier<GameState> {
  late GameEngine _engine;
  int? _bankrollBeforeHand; // snapshot at deal() to compute weekly delta
  double _trueCountAtDeal = 0;

  /// Set when the rules or shoe changed while a round was live. The new
  /// engine takes over once that round is settled — see [_onTableChanged].
  bool _engineStale = false;

  int _roundsSinceCountCheck = 0;

  /// Set when the provider is torn down, so a dealer sequence still waiting
  /// on a timer stops instead of writing to a disposed notifier.
  bool _disposed = false;

  /// The engine dealing the current round.
  GameEngine get engine => _engine;

  @override
  GameState build() {
    _engine = _buildEngine();
    final spots = ref.read(spotCountProvider);
    // Switching the shoe or the table rules starts a fresh shoe — but never
    // under a live round. Doing it immediately used to throw the round away,
    // stake and all: the chips had already left the bankroll at the deal.
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    ref.listen(shoeModeProvider, (_, __) => _onTableChanged());
    ref.listen(rulesProvider, (_, __) => _onTableChanged());
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

  /// A new shoe or new rules were picked. Applied now while betting (no chips
  /// are at risk yet), otherwise held until the live round is settled.
  void _onTableChanged() {
    if (state.phase != GamePhase.betting) {
      _engineStale = true;
      return;
    }
    _swapEngine();
    _resetSelectors();
  }

  void _swapEngine() {
    _engine = _buildEngine();
    _engineStale = false;
    state = _freshBetting(state.bankroll, ref.read(spotCountProvider)).copyWith(
      // A counter needs to hear that the count went back to zero.
      freshShoe: true,
      lastSpotBets: state.lastSpotBets,
      lastSideBet: state.lastSideBet,
    );
  }

  /// An engine for the shoe and rules selected right now.
  ///
  /// Built from the settings directly. It used to be read from a derived
  /// provider inside the settings listener, and on the first change after
  /// launch that provider had not yet been invalidated — so the dealer kept
  /// the old rules (still hitting soft 17 on an S17 table) while the coach,
  /// which read the provider later, graded against the new ones.
  GameEngine _buildEngine() {
    final mode = ref.read(shoeModeProvider);
    return GameEngine(
      numDecks: mode.numDecks,
      continuous: mode.isContinuous,
      rules: ref.read(rulesProvider),
    );
  }

  /// A clean betting-phase state with [count] empty spots. Pure — it does not
  /// touch other providers, so it is safe to call from [build].
  GameState _freshBetting(int bankroll, int count) {
    final n = count.clamp(1, GameEngine.maxSpots);
    return _engine.attachShoe(GameState(
      bankroll: bankroll,
      spotBets: List<int>.filled(n, 0),
    ));
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

  /// Put last round's bets back down.
  void rebet() {
    if (state.phase != GamePhase.betting) return;
    final next = _engine.rebet(state);
    if (identical(next, state)) return;
    state = next;
    SoundService.play(Sfx.chip);
  }

  void deal() {
    if (state.phase != GamePhase.betting || state.currentBet == 0) return;
    ref.read(strategyFeedbackProvider.notifier).state = null;
    ref.read(countCheckProvider.notifier).state = null;
    _bankrollBeforeHand = state.bankroll;
    // The count the bet was sized on — what the stats chart plots.
    _trueCountAtDeal = state.trueCount;
    _checkBet();
    state = state.copyWith(phase: GamePhase.dealing);
    state = _engine.dealInitial(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  /// With the bet-spread coach on, compare the bet with the ramp before the
  /// cards come out. A continuous shuffler is skipped: there is no count to
  /// bet on.
  void _checkBet() {
    if (!ref.read(betCoachProvider) || _engine.continuous) return;
    final unit = ref.read(betUnitProvider);
    final tc = state.trueCount;
    final bet = state.currentBet;
    final correct = BetRamp.matches(bet, tc, unit);
    PlayerStatsStore.recordBetCheck(correct: correct);
    if (!correct) {
      final units = BetRamp.units(tc);
      ref.read(strategyFeedbackProvider.notifier).state =
          StrategyFeedback.note(
        'Bet check: true count ${formatTrueCount(tc)} calls for $units '
        'unit${units == 1 ? '' : 's'} (\$${units * unit}) — you bet \$$bet',
      );
    }
  }

  void takeInsurance(bool take) {
    if (state.insuranceState != InsuranceState.offered) return;
    _scoreInsurance(take);
    state = _engine.handleInsurance(state, take);
    _onAction();
  }

  /// With index plays on, insurance is graded against the count: take it at
  /// +3 or higher, never below. Taking it when the bankroll cannot cover it
  /// declines, so only a decision that actually happened is graded.
  void _scoreInsurance(bool take) {
    if (!TableCoach.gradesInsurance(_engine,
        indexPlays: ref.read(indexPlaysProvider))) {
      return;
    }
    final affordable = state.currentBet ~/ 2 <= state.bankroll;
    final took = take && affordable;
    final tc = state.trueCount;
    final should = Deviations.shouldInsure(tc);
    final correct = took == should || (should && !affordable);
    StrategyCoach.recordIndex(correct: correct);
    ref.read(strategyFeedbackProvider.notifier).state = correct
        ? null
        : StrategyFeedback.note(
            'Insurance at true count ${formatTrueCount(tc)} — '
            '${should ? 'take it' : 'decline it'}: counters insure at '
            '+${Deviations.insuranceIndex} or higher',
          );
  }

  void hit() {
    if (!_awaitingDecision(state)) return;
    _scoreDecision(StrategyMove.hit);
    state = _engine.hit(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  void stand() {
    if (!_awaitingDecision(state)) return;
    _scoreDecision(StrategyMove.stand);
    state = _engine.stand(state);
    _onAction();
  }

  void doubleDown() {
    if (!_awaitingDecision(state)) return;
    // Whether a double is legal — two cards, affordable, permitted by the
    // table's doubling rule, and allowed after a split — is the rules' call.
    if (!_engine.canDoubleActiveHand(state)) return;
    _scoreDecision(StrategyMove.double);
    state = _engine.doubleDown(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  void split() {
    if (!_awaitingDecision(state)) return;
    // Pair, affordable, and within the table's hand limit.
    if (!_engine.canSplitActiveHand(state)) return;
    _scoreDecision(StrategyMove.split);
    state = _engine.split(state);
    SoundService.play(Sfx.card);
    _onAction();
  }

  /// Late surrender: half the bet back, and the hand is over.
  void surrender() {
    if (!_awaitingDecision(state)) return;
    if (!_engine.canSurrenderActiveHand(state)) return;
    _scoreDecision(StrategyMove.surrender);
    state = _engine.surrender(state);
    _onAction();
  }

  /// Compare what the player just did with what basic strategy says, record
  /// it, and surface the difference. Called before the state moves on, because
  /// the decision has to be judged on the hand they were actually looking at.
  void _scoreDecision(StrategyMove played) {
    final verdict = TableCoach.verdict(
      state,
      _engine,
      indexPlays: ref.read(indexPlaysProvider),
    );
    if (verdict == null) return;
    final dealer = state.dealerHand;
    final hand = state.activeHand;
    final best = verdict.best;
    final correct = best == played;
    final index = verdict.index;
    if (index != null) StrategyCoach.recordIndex(correct: correct);
    LeaderboardService.recordDecision(correct: correct);
    // The chart record measures the chart. A hand the count moved off basic
    // strategy is an index decision only — counting it as a chart cell would
    // put "16 v 10" on the most-missed list for someone who hit it by the
    // book, and the Strategy Drill would then drill the book answer.
    if (index == null || !index.departsFrom(verdict.basic)) {
      final canSplit = _engine.canSplitActiveHand(state);
      final category = canSplit && hand.isPair
          ? StrategyCategory.pair
          : hand.isSoft
              ? StrategyCategory.soft
              : StrategyCategory.hard;
      StrategyCoach.record(
        correct: correct,
        category: category,
        spot: chartSpotLabel(hand, dealer.cards.first, category),
      );
    }
    ref.read(strategyFeedbackProvider.notifier).state = correct
        ? null
        : StrategyFeedback(
            played: played,
            best: best,
            handValue: hand.value,
            handWasSoft: hand.isSoft,
            dealerUp: dealer.cards.first.rank.display,
            indexPlay: index?.play,
            trueCount: index == null ? null : state.trueCount,
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

    // Draw additional dealer cards one at a time, paced for the eye — unless
    // every hand is already decided, in which case a real dealer stops here.
    while (_engine.dealerMustPlay(state) && _engine.dealerShouldHit(state)) {
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
  bool _stillInDealerTurn() =>
      !_disposed && state.phase == GamePhase.dealerTurn;

  void nextHand() {
    if (_engineStale) {
      // The rules or shoe changed during the round just settled.
      _swapEngine();
    } else {
      state = _engine.newHand(state);
      // Re-lay the spots to match the currently selected hand count (it may
      // have changed since the round started).
      final count = ref.read(spotCountProvider).clamp(1, GameEngine.maxSpots);
      state = state.copyWith(spotBets: List<int>.filled(count, 0));
    }
    _resetSelectors();
    _saveBankroll();
    _maybeAskForCount();
  }

  /// Every [countCheckEvery] rounds with the HUD hidden, ask for the running
  /// count. Hiding the HUD is how a player practises keeping the count
  /// themselves, and without a check nothing ever tells them they drifted.
  void _maybeAskForCount() {
    if (ref.read(showCountProvider) || !ref.read(countCheckEnabledProvider)) {
      _roundsSinceCountCheck = 0;
      return;
    }
    _roundsSinceCountCheck++;
    // A brand-new shoe is always zero; asking then would teach nothing.
    if (state.freshShoe || _engine.continuous) return;
    if (_roundsSinceCountCheck < countCheckEvery) return;
    _roundsSinceCountCheck = 0;
    ref.read(countCheckProvider.notifier).state =
        CountCheck(state.runningCount);
  }

  /// Score the player's answer to the open count quiz. Returns whether it was
  /// right; the quiz stays open so the UI can show the answer, and
  /// [dismissCountCheck] closes it.
  bool answerCountCheck(int guess) {
    final check = ref.read(countCheckProvider);
    if (check == null) return false;
    final correct = guess == check.answer;
    PlayerStatsStore.recordCountCheck(correct: correct);
    return correct;
  }

  void dismissCountCheck() {
    ref.read(countCheckProvider.notifier).state = null;
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
      PlayerStatsStore.recordRound(
        results: state.handResults,
        roundNet: state.roundNet,
        trueCountAtDeal: _trueCountAtDeal,
      );
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

/// A chart cell written the way a strategy card labels it, e.g. "Hard 16 vs
/// 10", "Soft 18 vs A" or "8,8 vs 6". Faces are tens, because the chart does
/// not tell a king from a ten.
String chartSpotLabel(
  HandModel hand,
  CardModel dealerUp,
  StrategyCategory category,
) {
  String rankLabel(CardModel card) {
    final v = card.rank.value;
    return v == 11 ? 'A' : '$v';
  }

  final up = rankLabel(dealerUp);
  switch (category) {
    case StrategyCategory.pair:
      final r = rankLabel(hand.cards.first);
      return '$r,$r vs $up';
    case StrategyCategory.soft:
      return 'Soft ${hand.value} vs $up';
    case StrategyCategory.hard:
      return 'Hard ${hand.value} vs $up';
  }
}

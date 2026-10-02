import '../../core/progress/player_stats.dart';
import '../../core/strategy/strategy_coach.dart';
import '../hilo_training/hilo_game.dart';
import '../hilo_training/hilo_text.dart';
import '../hilo_training/hilo_training_progress.dart';
import '../training/drills.dart' show StrategyDrillFocus;

/// Where the home screen's "Today's next step" sends the player.
enum NextStepAction {
  /// The table, for someone who has not played a hand yet.
  playTable,

  /// Today's Daily Challenge, still unplayed.
  playDaily,

  /// The strategy drill on the hands they keep missing.
  drillMistakes,

  /// The strategy drill on their weakest part of the chart.
  drillCategory,

  /// Speed Count, when the running count keeps slipping at the table.
  speedCount,

  /// Hi-Lo Training's Survival, when everything else is in hand.
  survival,
}

/// One personalised suggestion: what to do next and why.
class NextStep {
  final NextStepAction action;
  final String title;
  final String detail;

  /// The chart category for [NextStepAction.drillCategory], or
  /// [StrategyDrillFocus.mistakes] for [NextStepAction.drillMistakes].
  final StrategyDrillFocus? focus;

  /// The Daily Challenge number for [NextStepAction.playDaily].
  final int? dailyNumber;

  const NextStep({
    required this.action,
    required this.title,
    required this.detail,
    this.focus,
    this.dailyNumber,
  });
}

/// The facts the suggestion is made from.
class NextStepInputs {
  final PlayerStats stats;
  final StrategyMastery mastery;
  final HiLoProfile hilo;

  /// Today's Daily Challenge number.
  final int today;

  const NextStepInputs({
    required this.stats,
    required this.mastery,
    required this.hilo,
    required this.today,
  });
}

/// A cell missed this often is worth a drill of its own.
const _missThreshold = 3;

/// Below this, a part of the chart (with enough decisions to judge) needs
/// work.
const _weakCategory = 0.9;

/// Below this, the running count (with enough checks) needs work.
const _weakCount = 0.8;

/// The single most useful thing to do now, in order: get started; play the
/// day's shoe while it is there; fix the hand they keep getting wrong; shore
/// up their weakest part of the chart; steady the count; otherwise, push
/// harder.
NextStep pickNextStep(NextStepInputs i) {
  final hilo = i.hilo;
  if (i.stats.hands == 0 && hilo.games == 0 && hilo.duels == 0) {
    return const NextStep(
      action: NextStepAction.playTable,
      title: 'Play your first hand',
      detail: 'The coach checks every decision against the chart.',
    );
  }

  if (!hilo.playedDaily(i.today)) {
    return NextStep(
      action: NextStepAction.playDaily,
      title: 'Play today\'s Daily Challenge',
      detail: 'Daily #${i.today} · ${tableLabel(HiLoDaily.configFor(i.today))}'
          ' · one ranked try',
      dailyNumber: i.today,
    );
  }

  final misses = i.mastery.topMisses;
  if (misses.isNotEmpty && misses.first.count >= _missThreshold) {
    final miss = misses.first;
    return NextStep(
      action: NextStepAction.drillMistakes,
      title: 'Improve ${spotLabel(miss.spot)}',
      detail: 'Missed ${miss.count} times. Drill the hands you get wrong.',
      focus: StrategyDrillFocus.mistakes,
    );
  }

  StrategyCategory? weakest;
  var weakestAccuracy = _weakCategory;
  for (final c in StrategyCategory.values) {
    final record = i.mastery.of(c);
    if (record.isMeaningful && record.accuracy < weakestAccuracy) {
      weakest = c;
      weakestAccuracy = record.accuracy;
    }
  }
  if (weakest != null) {
    return NextStep(
      action: NextStepAction.drillCategory,
      title: 'Practice ${weakest.label.toLowerCase()}',
      detail: '${i.mastery.of(weakest).accuracyPercent}% right so far. '
          'Twenty hands, instant feedback.',
      focus: switch (weakest) {
        StrategyCategory.hard => StrategyDrillFocus.hard,
        StrategyCategory.soft => StrategyDrillFocus.soft,
        StrategyCategory.pair => StrategyDrillFocus.pairs,
      },
    );
  }

  final checks = i.stats.countChecks;
  if (checks >= 5 && i.stats.countChecksCorrect / checks < _weakCount) {
    return NextStep(
      action: NextStepAction.speedCount,
      title: 'Sharpen your running count',
      detail: '${i.stats.countCheckPercent}% of table count checks right. '
          'Speed Count builds it back.',
    );
  }

  return const NextStep(
    action: NextStepAction.survival,
    title: 'Keep the count under pressure',
    detail: 'Survival: three lives, and the dealer speeds up as you go.',
  );
}

/// "16 vs 10" for "Hard 16 vs 10" — hard totals are the default; soft and
/// pair spots keep their word.
String spotLabel(String spot) =>
    spot.startsWith('Hard ') ? spot.substring(5) : spot;

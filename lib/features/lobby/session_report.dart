import '../../core/progress/player_stats.dart';
import '../../core/strategy/strategy_coach.dart';

/// The table's running totals at one moment. A session's report is the
/// difference between the snapshot taken as the player sits down and the one
/// taken when they get up.
class TableSnapshot {
  final PlayerStats stats;
  final StrategyRecord strategy;

  /// Every tracked cell and how often it has been missed.
  final Map<String, int> misses;

  const TableSnapshot({
    required this.stats,
    required this.strategy,
    required this.misses,
  });

  static Future<TableSnapshot> take() async => TableSnapshot(
        stats: await PlayerStatsStore.read(),
        strategy: await StrategyCoach.read(),
        misses: await StrategyCoach.readMissCounts(),
      );
}

/// What the report points the player at next.
enum NextDrill {
  /// The strategy drill on the hands they keep missing.
  mistakes('Drill the hands you missed'),

  /// The full strategy drill.
  strategy('Run the strategy drill'),

  /// Speed Count, for a count that slipped.
  speedCount('Sharpen your count in Speed Count'),

  /// Hi-Lo Training, when the session was clean.
  hiLoTraining('Count at speed in Hi-Lo Training');

  const NextDrill(this.label);
  final String label;
}

/// One table session: how it went, the mistake that mattered most, and the
/// drill to do next.
class SessionReport {
  final int hands;
  final int net;

  /// Chart decisions made this session, and how many were right.
  final StrategyRecord strategy;

  /// Count checks answered this session (only with the count HUD hidden).
  final StrategyRecord countChecks;

  /// The cell missed most this session, or null for a clean one.
  final StrategyMiss? biggestMistake;
  final NextDrill nextDrill;

  const SessionReport({
    required this.hands,
    required this.net,
    required this.strategy,
    required this.countChecks,
    required this.biggestMistake,
    required this.nextDrill,
  });

  /// Long enough to have something to say.
  bool get worthShowing => hands >= 3 || strategy.total >= 5;

  static SessionReport between(TableSnapshot before, TableSnapshot after) {
    final strategy = StrategyRecord(
      correct: after.strategy.correct - before.strategy.correct,
      total: after.strategy.total - before.strategy.total,
    );
    final countChecks = StrategyRecord(
      correct: after.stats.countChecksCorrect - before.stats.countChecksCorrect,
      total: after.stats.countChecks - before.stats.countChecks,
    );

    // The cell whose miss count rose most; a tie goes to the one missed more
    // often overall — the more stubborn habit.
    StrategyMiss? biggest;
    var biggestTotal = 0;
    for (final e in after.misses.entries) {
      final grew = e.value - (before.misses[e.key] ?? 0);
      if (grew <= 0) continue;
      if (biggest == null ||
          grew > biggest.count ||
          (grew == biggest.count && e.value > biggestTotal)) {
        biggest = StrategyMiss(e.key, grew);
        biggestTotal = e.value;
      }
    }

    final NextDrill next;
    if (biggest != null) {
      next = NextDrill.mistakes;
    } else if (countChecks.total > 0 && countChecks.accuracy < 0.8) {
      next = NextDrill.speedCount;
    } else if (strategy.total >= 5 && strategy.accuracy < 0.9) {
      next = NextDrill.strategy;
    } else {
      next = NextDrill.hiLoTraining;
    }

    return SessionReport(
      hands: after.stats.hands - before.stats.hands,
      net: after.stats.tableNet - before.stats.tableNet,
      strategy: strategy,
      countChecks: countChecks,
      biggestMistake: biggest,
      nextDrill: next,
    );
  }
}

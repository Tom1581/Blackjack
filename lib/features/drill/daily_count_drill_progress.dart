import 'package:shared_preferences/shared_preferences.dart';

import 'daily_count_drill.dart';

class DailyCountDrillBest {
  final int correct;
  final int bestStreak;

  const DailyCountDrillBest({
    required this.correct,
    required this.bestStreak,
  });
}

/// Stores only the best practice result for the current local calendar day.
class DailyCountDrillProgress {
  static const _dayKey = 'daily_count_drill_day';
  static const _correctKey = 'daily_count_drill_best_correct';
  static const _streakKey = 'daily_count_drill_best_streak';

  static Future<DailyCountDrillBest?> load(int dayKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getInt(_dayKey) != dayKey) return null;

    return DailyCountDrillBest(
      correct: prefs.getInt(_correctKey) ?? 0,
      bestStreak: prefs.getInt(_streakKey) ?? 0,
    );
  }

  static Future<DailyCountDrillBest> record(
      DailyCountDrillResult result) async {
    final previous = await load(result.dayKey);
    final best = DailyCountDrillBest(
      correct: previous == null || result.correct > previous.correct
          ? result.correct
          : previous.correct,
      bestStreak: previous == null || result.bestStreak > previous.bestStreak
          ? result.bestStreak
          : previous.bestStreak,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dayKey, result.dayKey);
    await prefs.setInt(_correctKey, best.correct);
    await prefs.setInt(_streakKey, best.bestStreak);
    return best;
  }
}

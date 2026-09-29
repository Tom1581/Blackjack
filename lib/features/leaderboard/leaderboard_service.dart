import 'package:shared_preferences/shared_preferences.dart';

/// Tracks this device's weekly profit and rolls it over when a new week
/// begins. The shared ranking itself lives in [WeeklyBoardService]; this is
/// the local source of truth that gets pushed to it.
///
/// The board used to be padded out with 25 invented competitors generated from
/// a seeded RNG. That has been removed: players now rank against real people,
/// so nothing here fabricates an opponent.
class LeaderboardService {
  const LeaderboardService._();

  static const _kProfitKey = 'lb_weekly_profit';
  static const _kHandsKey = 'lb_weekly_hands';
  static const _kWeekKey = 'lb_week_id';
  static const _kDecisionsKey = 'lb_weekly_decisions';
  static const _kCorrectKey = 'lb_weekly_correct';

  // Weeks are anchored to Monday 2024-01-01 (which was a Monday).
  static final DateTime _epoch = DateTime(2024, 1, 1);

  // ─── Week math ─────────────────────────────────────────────────────────

  static int _weekIndex([DateTime? at]) {
    final now = at ?? DateTime.now();
    final days =
        DateTime(now.year, now.month, now.day).difference(_epoch).inDays;
    return days ~/ 7;
  }

  /// Identifier for the current week, shared with the server so every device
  /// agrees on which board a score belongs to.
  static String weekKey([DateTime? at]) => 'W${_weekIndex(at)}';

  static DateTime currentWeekStart() =>
      _epoch.add(Duration(days: _weekIndex() * 7));

  static DateTime nextResetTime() =>
      currentWeekStart().add(const Duration(days: 7));

  static Duration timeUntilReset() =>
      nextResetTime().difference(DateTime.now());

  // ─── User profit tracking ──────────────────────────────────────────────

  /// Reads the current weekly profit, resetting to 0 if the week rolled over.
  static Future<int> readWeeklyProfit() async {
    final prefs = await SharedPreferences.getInstance();
    return _readProfitWithRollover(prefs);
  }

  static Future<int> _readProfitWithRollover(SharedPreferences prefs) async {
    final stored = prefs.getString(_kWeekKey);
    final current = weekKey();
    if (stored != current) {
      await prefs.setString(_kWeekKey, current);
      await prefs.setInt(_kProfitKey, 0);
      await prefs.setInt(_kHandsKey, 0);
      await prefs.setInt(_kDecisionsKey, 0);
      await prefs.setInt(_kCorrectKey, 0);
      return 0;
    }
    return prefs.getInt(_kProfitKey) ?? 0;
  }

  static Future<int> readHandsPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    await _readProfitWithRollover(prefs); // ensures the week is current
    return prefs.getInt(_kHandsKey) ?? 0;
  }

  /// This week's graded decisions: how many, and how many matched the coach.
  static Future<({int decisions, int correct})> readWeeklyDecisions() async {
    final prefs = await SharedPreferences.getInstance();
    await _readProfitWithRollover(prefs); // ensures the week is current
    return (
      decisions: prefs.getInt(_kDecisionsKey) ?? 0,
      correct: prefs.getInt(_kCorrectKey) ?? 0,
    );
  }

  /// Count one graded decision toward this week's accuracy league.
  static Future<void> recordDecision({required bool correct}) async {
    final prefs = await SharedPreferences.getInstance();
    await _readProfitWithRollover(prefs);
    await prefs.setInt(_kDecisionsKey, (prefs.getInt(_kDecisionsKey) ?? 0) + 1);
    if (correct) {
      await prefs.setInt(_kCorrectKey, (prefs.getInt(_kCorrectKey) ?? 0) + 1);
    }
  }

  /// Adds a per-hand delta to the running weekly profit.
  static Future<void> recordHand(int delta) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readProfitWithRollover(prefs);
    await prefs.setInt(_kProfitKey, current + delta);
    final hands = prefs.getInt(_kHandsKey) ?? 0;
    await prefs.setInt(_kHandsKey, hands + 1);
  }
}

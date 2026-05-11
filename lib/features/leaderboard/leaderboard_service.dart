import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// One row of the weekly leaderboard.
class LeaderboardEntry {
  final String name;
  final int profit;
  final bool isCurrentUser;

  const LeaderboardEntry({
    required this.name,
    required this.profit,
    this.isCurrentUser = false,
  });
}

/// Tracks the player's weekly profit, generates simulated competitors, and
/// rolls everything over when a new week begins.
///
/// There is no backend, so competitors are deterministic per-week (seeded by
/// the week key). This keeps the same standings stable when the player
/// reopens the app within the same week.
class LeaderboardService {
  static const _kProfitKey = 'lb_weekly_profit';
  static const _kHandsKey = 'lb_weekly_hands';
  static const _kWeekKey = 'lb_week_id';

  // Weeks are anchored to Monday 2024-01-01 (which was a Monday).
  static final DateTime _epoch = DateTime(2024, 1, 1);

  static const _competitorNames = [
    'Marco', 'Sofia', 'Yuki', 'Aisha', 'Diego', 'Maya', 'Kai', 'Priya',
    'Theo', 'Iris', 'Leo', 'Hana', 'Ben', 'Nora', 'Chen', 'Eva',
    'Jamal', 'Lin', 'Zoe', 'Alex', 'Mira', 'Owen', 'Cleo', 'Finn',
    'Asha', 'Reza', 'Tomo', 'Sage', 'Vera', 'Niko',
  ];

  // ─── Week math ─────────────────────────────────────────────────────────

  static int _weekIndex([DateTime? at]) {
    final now = at ?? DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(_epoch).inDays;
    return days ~/ 7;
  }

  static String _weekKey([DateTime? at]) => 'W${_weekIndex(at)}';

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
    final current = _weekKey();
    if (stored != current) {
      await prefs.setString(_kWeekKey, current);
      await prefs.setInt(_kProfitKey, 0);
      await prefs.setInt(_kHandsKey, 0);
      return 0;
    }
    return prefs.getInt(_kProfitKey) ?? 0;
  }

  static Future<int> readHandsPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    await _readProfitWithRollover(prefs); // ensures week is current
    return prefs.getInt(_kHandsKey) ?? 0;
  }

  /// Adds a per-hand delta to the running weekly profit.
  static Future<void> recordHand(int delta) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readProfitWithRollover(prefs);
    await prefs.setInt(_kProfitKey, current + delta);
    final hands = prefs.getInt(_kHandsKey) ?? 0;
    await prefs.setInt(_kHandsKey, hands + 1);
  }

  // ─── Competitors ───────────────────────────────────────────────────────

  /// Builds a deterministic, varied set of simulated competitors for the
  /// current week. The seed is the week key, so reopening the app within
  /// the same week shows the same competitors.
  static List<LeaderboardEntry> _simulatedCompetitors() {
    final rng = Random(_weekKey().hashCode);
    final names = List<String>.from(_competitorNames)..shuffle(rng);
    final entries = <LeaderboardEntry>[];

    // Distribution buckets so the board feels realistic:
    //   3 high rollers, 5 strong winners, 12 mid-pack, 5 in the red.
    int profitFor(int rank) {
      if (rank < 3) return 6500 + rng.nextInt(8500); // 6.5k–15k
      if (rank < 8) return 2500 + rng.nextInt(3500); // 2.5k–6k
      if (rank < 20) return -400 + rng.nextInt(2900); // -400 to 2.5k
      return -2200 + rng.nextInt(1700); // -2.2k to -500
    }

    for (var i = 0; i < 25; i++) {
      entries.add(LeaderboardEntry(
        name: names[i % names.length],
        profit: profitFor(i),
      ));
    }
    return entries;
  }

  /// Returns the full ranked board (descending by profit) including the user.
  static Future<List<LeaderboardEntry>> rankedBoard() async {
    final userProfit = await readWeeklyProfit();
    final entries = [
      ..._simulatedCompetitors(),
      LeaderboardEntry(
        name: 'You',
        profit: userProfit,
        isCurrentUser: true,
      ),
    ];
    entries.sort((a, b) => b.profit.compareTo(a.profit));
    return entries;
  }
}

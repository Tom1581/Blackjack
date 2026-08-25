import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the player's streak looks like right now.
@immutable
class StreakState {
  /// Consecutive days played, including today once claimed.
  final int streak;

  /// The longest streak this player has ever run.
  final int best;

  /// Today's reward has already been taken.
  final bool claimedToday;

  /// Chips waiting to be claimed today.
  final int todayReward;

  /// What tomorrow is worth if they come back.
  final int tomorrowReward;

  /// True when yesterday was missed, so today starts a new run.
  final bool streakBroken;

  /// The streak length claiming right now would produce. Equals [streak] once
  /// today has been claimed.
  final int pendingDay;

  /// Today's reward has already been doubled by watching an ad.
  final bool doubledToday;

  const StreakState({
    required this.streak,
    required this.best,
    required this.claimedToday,
    required this.todayReward,
    required this.tomorrowReward,
    required this.pendingDay,
    this.streakBroken = false,
    this.doubledToday = false,
  });

  /// Whether the "watch to double" offer still applies. The reward has to have
  /// been claimed first — doubling nothing is not an offer.
  bool get canDouble => claimedToday && !doubledToday;

  /// Position of [streak] within the seven-day cycle, 1–7.
  int get dayInCycle => DailyStreak.cyclePosition(streak);

  /// Position the next claim lands on — the pip the UI lights up as "today".
  int get pendingDayInCycle => DailyStreak.cyclePosition(pendingDay);

  /// Whether the pip for [day] should read as already earned this cycle.
  bool pipFilled(int day) =>
      claimedToday ? day <= dayInCycle : day < pendingDayInCycle;

  /// Whether the pip for [day] is the one on offer right now.
  bool pipIsToday(int day) => !claimedToday && day == pendingDayInCycle;
}

/// A once-a-day chip reward that grows across a week.
///
/// Deliberately plain: no countdown pressure, no "your streak expires in 4
/// hours!", no penalty for missing a day beyond starting the ladder again.
/// The point is to give someone a reason to open the app tomorrow, not to
/// make them anxious about not doing so.
class DailyStreak {
  const DailyStreak._();

  static const _kLastClaimDay = 'streak_last_claim_day';
  static const _kStreak = 'streak_days';
  static const _kBest = 'streak_best';
  static const _kDoubledDay = 'streak_doubled_day';

  /// Chips for day 1 through day 7. Day 7 onwards repeats the top rung.
  static const rewards = [200, 300, 400, 600, 800, 1200, 2000];

  static int get cycleLength => rewards.length;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Whole local days since the epoch — the unit a "daily" reward is measured
  /// in. Using the date rather than a 24-hour timer means a player who opens
  /// the app at 9am and again at 8am the next day is not told to wait.
  static int today() {
    final n = now();
    return DateTime(n.year, n.month, n.day)
        .difference(DateTime(1970)) // local midnight to local midnight
        .inDays;
  }

  /// Where a streak length sits in the 1–7 cycle.
  static int cyclePosition(int streakDay) {
    if (streakDay <= 0) return 1;
    final position = streakDay % cycleLength;
    return position == 0 ? cycleLength : position;
  }

  static int rewardFor(int streakDay) {
    if (streakDay <= 0) return rewards.first;
    final index = (streakDay - 1) % rewards.length;
    return rewards[index];
  }

  /// Read the current state without changing anything.
  static Future<StreakState> read() async {
    final prefs = await SharedPreferences.getInstance();
    return _derive(prefs);
  }

  static StreakState _derive(SharedPreferences prefs) {
    final lastClaim = prefs.getInt(_kLastClaimDay);
    final stored = prefs.getInt(_kStreak) ?? 0;
    final best = prefs.getInt(_kBest) ?? 0;
    final day = today();

    if (lastClaim == day) {
      return StreakState(
        streak: stored,
        best: best,
        claimedToday: true,
        todayReward: rewardFor(stored),
        tomorrowReward: rewardFor(stored + 1),
        pendingDay: stored,
        doubledToday: prefs.getInt(_kDoubledDay) == day,
      );
    }

    // A claim yesterday continues the run; anything older starts a new one.
    final continues = lastClaim != null && lastClaim == day - 1;
    final pending = continues ? stored + 1 : 1;
    return StreakState(
      streak: stored,
      best: best,
      claimedToday: false,
      todayReward: rewardFor(pending),
      tomorrowReward: rewardFor(pending + 1),
      pendingDay: pending,
      streakBroken: !continues && stored > 0,
    );
  }

  /// Take today's reward. Returns the chips granted, or 0 if today's was
  /// already claimed.
  static Future<int> claim() async {
    final prefs = await SharedPreferences.getInstance();
    final state = _derive(prefs);
    if (state.claimedToday) return 0;

    final day = today();
    final lastClaim = prefs.getInt(_kLastClaimDay);
    final stored = prefs.getInt(_kStreak) ?? 0;
    final continues = lastClaim != null && lastClaim == day - 1;
    final streak = continues ? stored + 1 : 1;

    await prefs.setInt(_kLastClaimDay, day);
    await prefs.setInt(_kStreak, streak);
    final best = prefs.getInt(_kBest) ?? 0;
    if (streak > best) await prefs.setInt(_kBest, streak);

    return rewardFor(streak);
  }

  /// Double today's reward, once, after watching an ad. Returns the extra
  /// chips, or 0 if today has not been claimed or was already doubled.
  ///
  /// The caller is responsible for only reaching here once the ad has actually
  /// been watched to completion.
  static Future<int> claimDouble() async {
    final prefs = await SharedPreferences.getInstance();
    final state = _derive(prefs);
    if (!state.canDouble) return 0;
    await prefs.setInt(_kDoubledDay, today());
    return state.todayReward;
  }

  @visibleForTesting
  static void resetForTest() => now = DateTime.now;
}

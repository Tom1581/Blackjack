import 'dart:math';

/// What one answer scored: a flat amount for being right, a bonus for being
/// quick, both multiplied by the combo the streak has built.
class HiLoPoints {
  final int base;
  final int speed;
  final int combo;

  /// A flat bonus for a right true count, outside the combo.
  final int trueCount;

  const HiLoPoints({
    required this.base,
    required this.speed,
    required this.combo,
    this.trueCount = 0,
  });

  static const none = HiLoPoints(base: 0, speed: 0, combo: 1);

  int get total => (base + speed) * combo + trueCount;

  HiLoPoints withTrueCount(int bonus) =>
      HiLoPoints(base: base, speed: speed, combo: combo, trueCount: bonus);
}

/// How answers turn into points.
///
/// A right count is worth [base]. Answering inside [fullSpeedWithin] adds up
/// to [maxSpeedBonus], shrinking to nothing at [noSpeedAfter] — at a table the
/// count has to be ready before the next hand, not eventually. A run of right
/// answers multiplies both: x2 from the third in a row, x3 from the sixth, x4
/// from the tenth. A wrong answer scores nothing and breaks the run.
class HiLoScoring {
  const HiLoScoring._();

  static const base = 100;
  static const maxSpeedBonus = 100;

  /// For a right true count, on top of the running count's points.
  static const trueCountBonus = 50;
  static const fullSpeedWithin = Duration(seconds: 2);
  static const noSpeedAfter = Duration(seconds: 10);

  /// The multiplier for an answer that brings the streak to [streak].
  static int comboFor(int streak) {
    if (streak >= 10) return 4;
    if (streak >= 6) return 3;
    if (streak >= 3) return 2;
    return 1;
  }

  /// Right answers still needed for the next multiplier, or null at the top.
  static int? toNextCombo(int streak) {
    for (final step in const [3, 6, 10]) {
      if (streak < step) return step - streak;
    }
    return null;
  }

  static int speedBonus(Duration took) {
    final ms = took.inMilliseconds;
    final full = fullSpeedWithin.inMilliseconds;
    final none = noSpeedAfter.inMilliseconds;
    if (ms <= full) return maxSpeedBonus;
    if (ms >= none) return 0;
    return (maxSpeedBonus * (none - ms) / (none - full)).round();
  }

  /// Points for one answer. [streak] is the run of right answers *including*
  /// this one, so it is 0 for a wrong answer.
  static HiLoPoints score({
    required bool correct,
    required Duration took,
    required int streak,
  }) {
    if (!correct) return HiLoPoints.none;
    return HiLoPoints(
      base: base,
      speed: speedBonus(took),
      combo: comboFor(max(1, streak)),
    );
  }
}

/// Survival gets harder as it goes: every [answersPerLevel] right counts the
/// dealer deals faster, and every other level another player sits down.
class SurvivalLevel {
  const SurvivalLevel._();

  static const answersPerLevel = 5;
  static const lives = 3;
  static const answerLimit = Duration(seconds: 12);

  static const _firstPaceMs = 1200;
  static const _fastestPaceMs = 420;

  static int levelFor(int correct) => 1 + correct ~/ answersPerLevel;

  static Duration paceFor(int level) => Duration(
        milliseconds: max(
          _fastestPaceMs,
          (_firstPaceMs * pow(0.88, level - 1)).round(),
        ),
      );

  /// Two seats at level 1, a fifth by level 7.
  static int playersFor(int level) => min(5, 1 + (level + 1) ~/ 2);
}

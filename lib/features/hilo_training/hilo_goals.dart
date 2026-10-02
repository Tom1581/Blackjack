import 'dart:math';

import 'hilo_training_progress.dart';

/// Where a goal's button takes the player.
enum HiLoGoalAction {
  practice('PLAY PRACTICE'),
  survival('START A SURVIVAL RUN'),
  daily('PLAY TODAY\'S DAILY'),
  duel('START A DUEL'),
  enterCode('ENTER A FRIEND\'S CODE');

  const HiLoGoalAction(this.label);
  final String label;
}

/// The next achievement to chase: how far along it is and where to go to
/// finish it. Turns a grid of identical locks into one thing to do.
class HiLoGoal {
  final HiLoAchievement achievement;
  final int current;
  final int target;
  final HiLoGoalAction action;

  const HiLoGoal({
    required this.achievement,
    required this.current,
    required this.target,
    required this.action,
  });

  double get progress => (current / target).clamp(0.0, 1.0);

  /// "7 / 10" for a count to reach; null for a one-off feat.
  String? get progressLabel => target > 1 ? '$current / $target' : null;
}

/// Progress toward every locked achievement, as far as the profile records
/// it. Feats the profile cannot count toward (a perfect game, a quick
/// answer) are 0 of 1 until done.
List<HiLoGoal> lockedGoals(HiLoProfile p, {required int today}) {
  HiLoGoal goal(
          HiLoAchievement a, int current, int target, HiLoGoalAction act) =>
      HiLoGoal(
        achievement: a,
        current: min(current, target),
        target: target,
        action: act,
      );

  // A Survival level of L means at least 5 × (L − 1) right in that run.
  final bestSurvivalRun = max(0, (p.survivalBestLevel - 1) * 5);
  final all = [
    goal(HiLoAchievement.firstCount, p.correct, 1, HiLoGoalAction.practice),
    goal(HiLoAchievement.quickDraw, 0, 1, HiLoGoalAction.practice),
    goal(HiLoAchievement.pokerFace, p.holeCardReads, 10,
        HiLoGoalAction.practice),
    goal(HiLoAchievement.perfectTen, 0, 1, HiLoGoalAction.practice),
    goal(HiLoAchievement.casinoSpeed, 0, 1, HiLoGoalAction.practice),
    goal(HiLoAchievement.fullHouse, 0, 1, HiLoGoalAction.practice),
    goal(
        HiLoAchievement.unshakeable, p.bestStreak, 25, HiLoGoalAction.survival),
    goal(
        HiLoAchievement.survivor, bestSurvivalRun, 20, HiLoGoalAction.survival),
    goal(HiLoAchievement.pitBoss, p.survivalBestLevel, 7,
        HiLoGoalAction.survival),
    goal(HiLoAchievement.regular, p.dailyStreakOn(today), 3,
        HiLoGoalAction.daily),
    goal(HiLoAchievement.everyDay, p.dailyStreakOn(today), 7,
        HiLoGoalAction.daily),
    goal(HiLoAchievement.duelist, p.duels, 1, HiLoGoalAction.duel),
    goal(HiLoAchievement.challengeAccepted, p.challengesWon, 1,
        HiLoGoalAction.enterCode),
    goal(HiLoAchievement.centurion, p.correct, 100, HiLoGoalAction.practice),
    goal(HiLoAchievement.trueBeliever, p.trueCountsRight, 10,
        HiLoGoalAction.practice),
  ];
  return [
    for (final g in all)
      if (!p.achievements.contains(g.achievement)) g,
  ];
}

/// The locked achievement closest to done; the first in the list when none
/// has been started. Null once everything is unlocked.
HiLoGoal? nextGoal(HiLoProfile p, {required int today}) {
  final locked = lockedGoals(p, today: today);
  if (locked.isEmpty) return null;
  var best = locked.first;
  for (final g in locked.skip(1)) {
    if (g.progress > best.progress) best = g;
  }
  return best;
}

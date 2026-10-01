import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../hilo_training_progress.dart';

IconData achievementIcon(HiLoAchievement a) => switch (a) {
      HiLoAchievement.firstCount => Icons.looks_one_outlined,
      HiLoAchievement.quickDraw => Icons.flash_on_outlined,
      HiLoAchievement.pokerFace => Icons.visibility_off_outlined,
      HiLoAchievement.perfectTen => Icons.workspace_premium_outlined,
      HiLoAchievement.casinoSpeed => Icons.speed,
      HiLoAchievement.fullHouse => Icons.groups_outlined,
      HiLoAchievement.unshakeable => Icons.shield_outlined,
      HiLoAchievement.survivor => Icons.favorite_outline,
      HiLoAchievement.pitBoss => Icons.trending_up,
      HiLoAchievement.regular => Icons.event_available_outlined,
      HiLoAchievement.everyDay => Icons.calendar_month_outlined,
      HiLoAchievement.duelist => Icons.people_alt_outlined,
      HiLoAchievement.challengeAccepted => Icons.emoji_events_outlined,
      HiLoAchievement.centurion => Icons.military_tech_outlined,
      HiLoAchievement.trueBeliever => Icons.functions,
    };

IconData rankIcon(HiLoRank r) => switch (r) {
      HiLoRank.rookie => Icons.school_outlined,
      HiLoRank.cardWatcher => Icons.visibility_outlined,
      HiLoRank.counter => Icons.calculate_outlined,
      HiLoRank.shoeReader => Icons.auto_stories_outlined,
      HiLoRank.advantagePlayer => Icons.trending_up,
      HiLoRank.pitBossNightmare => Icons.local_fire_department_outlined,
      HiLoRank.legend => Icons.diamond_outlined,
    };

/// Bronze through gold to a legendary violet.
Color rankColor(HiLoRank r) => switch (r) {
      HiLoRank.rookie => const Color(0xFFB08D57),
      HiLoRank.cardWatcher => const Color(0xFFC0C7CF),
      HiLoRank.counter => AppColors.gold,
      HiLoRank.shoeReader => const Color(0xFF5FD4A0),
      HiLoRank.advantagePlayer => const Color(0xFF5AB0FF),
      HiLoRank.pitBossNightmare => const Color(0xFFFF7A59),
      HiLoRank.legend => const Color(0xFFC08CFF),
    };

/// A round medal for a rank.
class RankEmblem extends StatelessWidget {
  final HiLoRank rank;
  final double size;

  const RankEmblem({super.key, required this.rank, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final color = rankColor(rank);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.1)],
        ),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14),
        ],
      ),
      child: Icon(rankIcon(rank), color: color, size: size * 0.5),
    );
  }
}

/// An achievement medal, greyed out while locked.
class AchievementBadge extends StatelessWidget {
  final HiLoAchievement achievement;
  final bool unlocked;
  final double size;

  const AchievementBadge({
    super.key,
    required this.achievement,
    required this.unlocked,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final color = unlocked ? AppColors.gold : Colors.white24;
    return Semantics(
      label: '${achievement.title}, ${unlocked ? 'unlocked' : 'locked'}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: unlocked
              ? AppColors.gold.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.25),
          border: Border.all(color: color, width: unlocked ? 1.6 : 1),
        ),
        child: Icon(
          unlocked ? achievementIcon(achievement) : Icons.lock_outline,
          color: color,
          size: size * 0.5,
        ),
      ),
    );
  }
}

/// A bar that fills to [progress] with a gold sheen.
class HiLoProgressBar extends StatelessWidget {
  final double progress;
  final Color color;
  final double height;

  const HiLoProgressBar({
    super.key,
    required this.progress,
    this.color = AppColors.gold,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.1)),
            ),
            FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.7), color],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every achievement with what it takes, for the hub's "see all".
Future<void> showAchievementsSheet(
  BuildContext context,
  Set<HiLoAchievement> unlocked,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(
            'ACHIEVEMENTS  ·  ${unlocked.length}/${HiLoAchievement.values.length}',
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          for (final a in HiLoAchievement.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  AchievementBadge(
                      achievement: a, unlocked: unlocked.contains(a)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.title,
                          style: TextStyle(
                            color: unlocked.contains(a)
                                ? Colors.white
                                : Colors.white60,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.description,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

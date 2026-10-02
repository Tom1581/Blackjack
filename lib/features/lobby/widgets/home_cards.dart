import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../profile/player_identity.dart';
import '../../table/table_screen.dart' show formatChips;
import '../next_step.dart';

/// Who is playing and what they have: the player's avatar and name (tap to
/// change it) beside the bankroll. One compact row, so the next step and the
/// PLAY button stay above the fold on a small phone.
class ProfileBankrollRow extends StatelessWidget {
  final String name;
  final int bankroll;
  final VoidCallback onEditName;

  const ProfileBankrollRow({
    super.key,
    required this.name,
    required this.bankroll,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final hasName = name.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('home-profile'),
              borderRadius: BorderRadius.circular(28),
              onTap: () {
                HapticFeedback.selectionClick();
                onEditName();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 4, 8, 4),
                child: Row(
                  children: [
                    PlayerAvatar(name: name, size: 38, isMe: true),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hasName ? name : 'Add your name',
                            key: const ValueKey('home-profile-name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasName ? Colors.white : AppColors.gold,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            hasName ? 'Tap to change' : 'Tap to set it',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.edit_outlined,
                        size: 15, color: Colors.white.withValues(alpha: 0.45)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          key: const ValueKey('home-bankroll'),
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF3A1808), Color(0xFF1F0A02)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.savings, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'BANKROLL',
                    style: TextStyle(
                      color: AppColors.gold.withValues(alpha: 0.85),
                      fontSize: 8.5,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '\$${formatChips(bankroll)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Today's next step": the one thing most worth doing now, picked from the
/// player's own record by [pickNextStep]. It sits above the fold so the home
/// screen leads with a plan instead of a row of equal buttons.
class NextStepCard extends StatelessWidget {
  /// Null while the player's record is loading.
  final NextStep? step;
  final VoidCallback? onTap;

  const NextStepCard({super.key, required this.step, this.onTap});

  static Color accentFor(NextStepAction action) => switch (action) {
        NextStepAction.playTable || NextStepAction.playDaily => AppColors.gold,
        _ => AppColors.drill,
      };

  static IconData iconFor(NextStepAction action) => switch (action) {
        NextStepAction.playTable => Icons.play_arrow_rounded,
        NextStepAction.playDaily => Icons.today,
        NextStepAction.drillMistakes => Icons.gps_fixed,
        NextStepAction.drillCategory => Icons.fact_check_outlined,
        NextStepAction.speedCount => Icons.bolt_outlined,
        NextStepAction.survival => Icons.favorite_outline,
      };

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    if (step == null) {
      // Hold the space so nothing below jumps when it loads.
      return const SizedBox(height: 86);
    }
    final accent = accentFor(step.action);
    return TweenAnimationBuilder<double>(
      key: ValueKey(step.title),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('home-next-step'),
          borderRadius: BorderRadius.circular(16),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                      accent.withValues(alpha: 0.14), AppColors.surface),
                  AppColors.surface,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: accent.withValues(alpha: 0.7), width: 1.4),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.16),
                    border: Border.all(color: accent.withValues(alpha: 0.7)),
                  ),
                  child: Icon(iconFor(step.action), color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TODAY\'S NEXT STEP',
                        style: TextStyle(
                          color: accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.title,
                        key: const ValueKey('home-next-step-title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        step.detail,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

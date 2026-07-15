import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/engine/game_engine.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

const _chips = [5, 25, 50, 100, 500];

class BetPanel extends ConsumerWidget {
  const BetPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final notifier = ref.read(tableProvider.notifier);
    final target = ref.watch(betTargetProvider);
    final spotCount = state.spotCount;
    final activeSpot = ref.watch(activeSpotProvider).clamp(0, spotCount - 1);
    // Total staked across every main spot — drives affordability, CLEAR and
    // DEAL. The MAIN tab, in multi-hand mode, shows just the active spot's bet.
    final totalMain = state.currentBet;
    final activeSpotBet = state.spotBets[activeSpot];
    final sideBet = state.sideBet;
    final bankroll = state.bankroll;

    bool canAffordChip(int value) {
      final totalAfter = totalMain + sideBet + value;
      if (totalAfter > bankroll) return false;
      if (target == BetTarget.side) {
        if (sideBet + value > GameEngine.sideBetMax) return false;
      }
      return true;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.wood,
        border: Border(
          top: BorderSide(
              color: AppColors.gold.withValues(alpha: 0.35), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // MAIN / SIDE target tabs
          _BetTargetTabs(
            target: target,
            mainLabel: spotCount > 1 ? 'HAND ${activeSpot + 1}' : 'MAIN',
            mainBet: spotCount > 1 ? activeSpotBet : totalMain,
            sideBet: sideBet,
            onSelect: (t) {
              HapticFeedback.selectionClick();
              ref.read(betTargetProvider.notifier).state = t;
            },
          ),
          const SizedBox(height: 6),

          // Hint about the active target
          SizedBox(
            height: 14,
            child: target == BetTarget.side
                ? Text(
                    'DEALER BUST · pays 2× / 4× / 15× / 50× / 100×',
                    style: TextStyle(
                      color: AppColors.gold.withValues(alpha: 0.7),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  )
                : Text(
                    spotCount > 1
                        ? 'TAP A HAND CIRCLE, THEN CHIPS  ·  TOTAL \$$totalMain'
                        : 'TAP CHIPS TO BET',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
          ),
          const SizedBox(height: 8),

          // Chip row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _chips.asMap().entries.map((e) {
              final value = e.value;
              final color = AppColors.chipColors[e.key];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _CasinoChip(
                  value: value,
                  color: color,
                  enabled: canAffordChip(value),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (target == BetTarget.main) {
                      notifier.addChip(value);
                    } else {
                      notifier.addSideChip(value);
                    }
                  },
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (totalMain > 0 || sideBet > 0)
                      ? () {
                          HapticFeedback.lightImpact();
                          notifier.clearBet();
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'CLEAR',
                    style: TextStyle(letterSpacing: 1.5, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: totalMain > 0
                      ? () {
                          HapticFeedback.mediumImpact();
                          notifier.deal();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.wood,
                    disabledBackgroundColor:
                        AppColors.gold.withValues(alpha: 0.3),
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text(
                    'DEAL',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two-tab segmented control to choose which betting circle the next chip
/// will land in (main wager vs. dealer-bust side bet).
class _BetTargetTabs extends StatelessWidget {
  final BetTarget target;
  final String mainLabel;
  final int mainBet;
  final int sideBet;
  final ValueChanged<BetTarget> onSelect;

  const _BetTargetTabs({
    required this.target,
    required this.mainLabel,
    required this.mainBet,
    required this.sideBet,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tab(
            label: mainLabel,
            amount: mainBet,
            isActive: target == BetTarget.main,
            onTap: () => onSelect(BetTarget.main),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _tab(
            label: 'SIDE',
            amount: sideBet,
            isActive: target == BetTarget.side,
            onTap: () => onSelect(BetTarget.side),
            sublabel: 'max \$${GameEngine.sideBetMax}',
          ),
        ),
      ],
    );
  }

  Widget _tab({
    required String label,
    required int amount,
    required bool isActive,
    required VoidCallback onTap,
    String? sublabel,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.gold
              : Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? AppColors.gold
                : AppColors.gold.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppColors.wood : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              amount > 0 ? '\$$amount' : '—',
              style: TextStyle(
                color: isActive
                    ? AppColors.wood
                    : (amount > 0 ? Colors.white : Colors.white38),
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (sublabel != null && !isActive) ...[
              const SizedBox(width: 6),
              Text(
                sublabel,
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.6),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CasinoChip extends StatelessWidget {
  final int value;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _CasinoChip({
    required this.value,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.3,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3), width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
              ),
              Text(
                value >= 1000 ? '${value ~/ 1000}K' : '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

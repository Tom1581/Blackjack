import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/strategy/basic_strategy.dart';
import '../../../core/strategy/strategy_coach.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

class ActionBar extends ConsumerWidget {
  const ActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(tableProvider.notifier);
    // What this table actually permits: two cards, affordable, within the
    // doubling rule, after a split, and inside the hand limit.
    final canDouble = ref.watch(canDoubleProvider);
    final canSplit = ref.watch(canSplitProvider);
    // A surrender table shows the button all round, greyed out once the hand
    // has moved past its first decision, so the layout never jumps.
    final surrenderTable = ref.watch(tableRulesProvider).lateSurrender;
    final canSurrender = ref.watch(canSurrenderProvider);
    // The coach's recommendation, when the player has asked to see it.
    final hint =
        StrategyCoach.hintsEnabled ? ref.watch(strategyHintProvider) : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.wood,
        border: Border(
          top: BorderSide(color: AppColors.gold.withValues(alpha: 0.35), width: 1.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          surrenderTable ? 8 : 12, 10, surrenderTable ? 8 : 12, 18),
      child: Row(
        children: [
          if (surrenderTable) ...[
            _ActionBtn(
              label: 'Surrender',
              recommended: hint == StrategyMove.surrender,
              icon: Icons.flag_outlined,
              color: AppColors.btnSurrender,
              accentColor: const Color(0xFFC9CED8),
              enabled: canSurrender,
              onTap: () {
                HapticFeedback.mediumImpact();
                n.surrender();
              },
            ),
            const SizedBox(width: 6),
          ],
          _ActionBtn(
            label: 'Stand',
            recommended: hint == StrategyMove.stand,
            icon: Icons.pan_tool_outlined,
            color: AppColors.btnStand,
            accentColor: const Color(0xFFFF6B6B),
            onTap: () {
              HapticFeedback.mediumImpact();
              n.stand();
            },
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            label: 'Split',
            recommended: hint == StrategyMove.split,
            icon: Icons.call_split,
            color: AppColors.btnSplit,
            accentColor: const Color(0xFFFFBB55),
            enabled: canSplit,
            onTap: () {
              HapticFeedback.heavyImpact();
              n.split();
            },
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            label: 'Double',
            recommended: hint == StrategyMove.double,
            icon: Icons.add_circle_outline,
            color: AppColors.btnDouble,
            accentColor: const Color(0xFF5599FF),
            enabled: canDouble,
            onTap: () {
              HapticFeedback.heavyImpact();
              n.doubleDown();
            },
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            label: 'Hit',
            recommended: hint == StrategyMove.hit,
            icon: Icons.arrow_circle_down_outlined,
            color: AppColors.btnHit,
            accentColor: const Color(0xFF66DD88),
            onTap: () {
              HapticFeedback.mediumImpact();
              n.hit();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color accentColor;
  final bool enabled;

  /// Basic strategy's pick. Marked, never forced — the player still chooses,
  /// which is the only way anyone learns the chart.
  final bool recommended;

  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.accentColor,
    required this.onTap,
    this.enabled = true,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.28,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: recommended && enabled
                    ? AppColors.gold
                    : accentColor.withValues(alpha: 0.3),
                width: recommended && enabled ? 2 : 1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.9),
                  color,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                if (recommended && enabled)
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.45),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accentColor, size: 22),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

class ActionBar extends ConsumerWidget {
  const ActionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final n = ref.read(tableProvider.notifier);
    final hand = state.activeHand;
    // Both split and double stake exactly one more base bet for the active
    // hand — its own wager, independent of how many other hands are in play.
    final canAffordExtraBaseBet = state.bankroll >= hand.bet;

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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      child: Row(
        children: [
          _ActionBtn(
            label: 'Stand',
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
            icon: Icons.call_split,
            color: AppColors.btnSplit,
            accentColor: const Color(0xFFFFBB55),
            enabled: hand.isPair && canAffordExtraBaseBet,
            onTap: () {
              HapticFeedback.heavyImpact();
              n.split();
            },
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            label: 'Double',
            icon: Icons.add_circle_outline,
            color: AppColors.btnDouble,
            accentColor: const Color(0xFF5599FF),
            enabled: hand.canDouble && canAffordExtraBaseBet,
            onTap: () {
              HapticFeedback.heavyImpact();
              n.doubleDown();
            },
          ),
          const SizedBox(width: 8),
          _ActionBtn(
            label: 'Hit',
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
  final VoidCallback onTap;

  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.accentColor,
    required this.onTap,
    this.enabled = true,
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
                color: accentColor.withValues(alpha: 0.3),
                width: 1,
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
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accentColor, size: 22),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
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

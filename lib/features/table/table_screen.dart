import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/game_state.dart';
import '../../theme/app_theme.dart';
import 'table_provider.dart';
import 'widgets/action_bar.dart';
import 'widgets/bet_panel.dart';
import 'widgets/broke_modal.dart';
import 'widgets/chip_stack.dart';
import 'widgets/count_hud.dart';
import 'widgets/dealer_area.dart';
import 'widgets/insurance_prompt.dart';
import 'widgets/player_area.dart';
import 'widgets/result_overlay.dart';

const _minChipValue = 5;

class TableScreen extends ConsumerWidget {
  const TableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final notifier = ref.read(tableProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.table,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Wood top rail
                _TopRail(bankroll: state.bankroll),

                // Felt play area
                Expanded(
                  child: Column(
                    children: [
                      const Flexible(flex: 5, child: DealerArea()),
                      const _FeltBanner(),
                      const _TableChips(),
                      const Flexible(flex: 6, child: PlayerArea()),
                    ],
                  ),
                ),

                // Bottom controls (bet or action)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _bottomControls(state, notifier),
                ),
              ],
            ),

            if (state.insuranceState == InsuranceState.offered)
              const InsurancePrompt(),
            if (state.phase == GamePhase.result)
              const ResultOverlay(),
            if (state.phase == GamePhase.betting &&
                state.bankroll < _minChipValue)
              const BrokeModal(),
          ],
        ),
      ),
    );
  }

  Widget _bottomControls(GameState state, TableNotifier notifier) {
    switch (state.phase) {
      case GamePhase.betting:
        return const BetPanel(key: ValueKey('bet'));
      case GamePhase.playerTurn:
        return const ActionBar(key: ValueKey('action'));
      default:
        return const SizedBox.shrink(key: ValueKey('empty'));
    }
  }
}

class _TopRail extends ConsumerWidget {
  final int bankroll;
  const _TopRail({required this.bankroll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.wood,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: AppColors.gold.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back_ios, color: AppColors.gold, size: 20),
          ),
          const SizedBox(width: 10),
          const CountHud(),
          const Spacer(),
          _BankrollPill(bankroll: bankroll),
        ],
      ),
    );
  }
}

class _BankrollPill extends StatelessWidget {
  final int bankroll;
  const _BankrollPill({required this.bankroll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\$ ',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              _fmt(bankroll),
              key: ValueKey(bankroll),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int v) {
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return '$v';
  }
}

class _FeltBanner extends StatelessWidget {
  const _FeltBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            'BLACKJACK  PAYS  3  TO  2',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.18),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Dealer Must Hit on Soft 17   •   Insurance Pays 2 to 1',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.12),
              fontSize: 7.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// On-felt betting circles — a big one for the main bet, a smaller one for
/// the dealer-bust side bet. Always visible so the player can see *where*
/// their chips will land. Tap a circle to switch the active bet target.
class _TableChips extends ConsumerWidget {
  const _TableChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        height: 130,
        child: Center(
          child: SizedBox(
            width: 200,
            height: 130,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Main bet circle — bigger, lower-left
                Positioned(
                  left: 6,
                  bottom: 0,
                  child: _BettingCircle(
                    amount: state.currentBet,
                    size: 100,
                    emptyLabel: 'BET',
                    bottomLabel: 'MAIN',
                    borderColor: AppColors.gold,
                    chipSize: 22,
                    maxVisibleChips: 5,
                    target: BetTarget.main,
                  ),
                ),
                // Side bet circle — smaller, upper-right (the "bonus" spot)
                Positioned(
                  right: 6,
                  top: 0,
                  child: _BettingCircle(
                    amount: state.sideBet,
                    size: 60,
                    emptyLabel: 'BUST',
                    bottomLabel: 'SIDE',
                    borderColor: AppColors.unfavorable,
                    chipSize: 16,
                    maxVisibleChips: 3,
                    target: BetTarget.side,
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

/// A casino-style betting spot painted on the felt: an outlined circle
/// (ringed in [borderColor]), with either an empty-state label or a stack
/// of chips inside, and a small caps label below.
///
/// During the betting phase the circle is tappable — tapping it makes its
/// [target] the active spot for the next chip click.
class _BettingCircle extends ConsumerWidget {
  final int amount;
  final double size;
  final String emptyLabel;
  final String bottomLabel;
  final Color borderColor;
  final double chipSize;
  final int maxVisibleChips;
  final BetTarget target;

  const _BettingCircle({
    required this.amount,
    required this.size,
    required this.emptyLabel,
    required this.bottomLabel,
    required this.borderColor,
    required this.chipSize,
    required this.maxVisibleChips,
    required this.target,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTarget = ref.watch(betTargetProvider);
    final phase = ref.watch(tableProvider.select((s) => s.phase));
    final isActive = activeTarget == target;
    final canTap = phase == GamePhase.betting;

    return GestureDetector(
      onTap: canTap
          ? () {
              HapticFeedback.selectionClick();
              ref.read(betTargetProvider.notifier).state = target;
            }
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.22),
              border: Border.all(
                color: borderColor.withValues(
                    alpha: canTap && isActive ? 0.95 : 0.5),
                width: canTap && isActive ? 2.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
                if (canTap && isActive)
                  BoxShadow(
                    color: borderColor.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
              ],
            ),
            alignment: Alignment.center,
            child: amount > 0
                ? ChipStack(
                    amount: amount,
                    chipSize: chipSize,
                    maxVisibleChips: maxVisibleChips,
                    showAmount: false,
                  )
                : Text(
                    emptyLabel,
                    style: TextStyle(
                      color: borderColor.withValues(alpha: 0.85),
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 3),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            amount > 0 ? '$bottomLabel · \$$amount' : bottomLabel,
            style: TextStyle(
              color: amount > 0
                  ? borderColor
                  : Colors.white.withValues(alpha: 0.45),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              shadows: amount > 0
                  ? [
                      Shadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 3),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

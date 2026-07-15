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

/// On-felt betting circles — one per main betting spot plus a smaller circle
/// for the dealer-bust side bet. Always visible so the player can see *where*
/// their chips will land. Tap a circle to make it the active bet target.
class _TableChips extends ConsumerWidget {
  const _TableChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotBets = ref.watch(tableProvider.select((s) => s.spotBets));
    final sideBet = ref.watch(tableProvider.select((s) => s.sideBet));
    final phase = ref.watch(tableProvider.select((s) => s.phase));
    final target = ref.watch(betTargetProvider);
    final activeSpot = ref.watch(activeSpotProvider);

    final count = spotBets.length;
    final canTap = phase == GamePhase.betting;
    // Shrink the circles as more spots share the felt width.
    final mainSize = count >= 3
        ? 78.0
        : count == 2
            ? 88.0
            : 96.0;
    final mainChip = count >= 3 ? 17.0 : 20.0;

    List<Widget> circles = [
      for (var i = 0; i < count; i++)
        _BettingCircle(
          amount: spotBets[i],
          size: mainSize,
          emptyLabel: 'BET',
          bottomLabel: count == 1 ? 'MAIN' : 'HAND ${i + 1}',
          borderColor: AppColors.gold,
          chipSize: mainChip,
          maxVisibleChips: 5,
          isActive: target == BetTarget.main && activeSpot == i,
          canTap: canTap,
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(activeSpotProvider.notifier).state = i;
            ref.read(betTargetProvider.notifier).state = BetTarget.main;
          },
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        height: 132,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in circles) ...[
                  c,
                  const SizedBox(width: 10),
                ],
                // Side bet circle — smaller "bonus" spot on the right.
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _BettingCircle(
                    amount: sideBet,
                    size: 58,
                    emptyLabel: 'BUST',
                    bottomLabel: 'SIDE',
                    borderColor: AppColors.unfavorable,
                    chipSize: 16,
                    maxVisibleChips: 3,
                    isActive: target == BetTarget.side,
                    canTap: canTap,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(betTargetProvider.notifier).state =
                          BetTarget.side;
                    },
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
/// During the betting phase the circle is tappable — tapping it makes it the
/// active spot for the next chip click.
class _BettingCircle extends StatelessWidget {
  final int amount;
  final double size;
  final String emptyLabel;
  final String bottomLabel;
  final Color borderColor;
  final double chipSize;
  final int maxVisibleChips;
  final bool isActive;
  final bool canTap;
  final VoidCallback onTap;

  const _BettingCircle({
    required this.amount,
    required this.size,
    required this.emptyLabel,
    required this.bottomLabel,
    required this.borderColor,
    required this.chipSize,
    required this.maxVisibleChips,
    required this.isActive,
    required this.canTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = canTap && isActive;

    return GestureDetector(
      onTap: canTap ? onTap : null,
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
                color: borderColor.withValues(alpha: highlight ? 0.95 : 0.5),
                width: highlight ? 2.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
                if (highlight)
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

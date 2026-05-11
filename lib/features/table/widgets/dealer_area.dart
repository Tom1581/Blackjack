import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/game_state.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';
import 'card_widget.dart';

class DealerArea extends ConsumerWidget {
  const DealerArea({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final dealer = state.dealerHand;
    final isResult = state.phase == GamePhase.result;
    final cards = dealer.cards;

    final displayValue = isResult ? dealer.revealAll().value : dealer.value;
    final isBust = isResult && dealer.isBust;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Score badge
        if (cards.isNotEmpty)
          _HandBadge(
            value: displayValue,
            isBust: isBust,
            isBlackjack: isResult && dealer.isBlackjack,
          )
        else
          Text(
            'DEALER',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.2),
              fontSize: 10,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        const SizedBox(height: 8),

        // Card row
        SizedBox(
          height: 108,
          child: cards.isEmpty
              ? _emptyRow()
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < cards.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                              left: i == 0 ? 0 : 6, right: 0),
                          child: CardWidget(card: cards[i]),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CardWidget(card: null, width: 72),
        const SizedBox(width: 8),
        CardWidget(card: null, width: 72),
      ],
    );
  }
}

class _HandBadge extends StatelessWidget {
  final int value;
  final bool isBust;
  final bool isBlackjack;

  const _HandBadge({
    required this.value,
    this.isBust = false,
    this.isBlackjack = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final String label;

    if (isBust) {
      bgColor = AppColors.unfavorable.withValues(alpha: 0.85);
      textColor = Colors.white;
      label = 'BUST';
    } else if (isBlackjack) {
      bgColor = AppColors.gold.withValues(alpha: 0.9);
      textColor = AppColors.wood;
      label = 'BJ!';
    } else {
      bgColor = Colors.black.withValues(alpha: 0.65);
      textColor = Colors.white;
      label = '$value';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

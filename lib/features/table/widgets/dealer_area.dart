import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/card_model.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';
import 'card_widget.dart';
import 'discard_tray.dart';

class DealerArea extends ConsumerWidget {
  final bool compact;

  const DealerArea({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final decks = ref.watch(tableEngineProvider).numDecks;
    final dealer = state.dealerHand;
    final cards = dealer.cards;

    // Only what is face up. The badge used to read the full hand value, which
    // includes the face-down hole card — so "17" over a lone ten gave the hole
    // card away on every hand.
    final holeDown = dealer.hasFaceDown;
    final isBust = !holeDown && dealer.isBust;
    final gap = compact ? 6.0 : 8.0;

    // Cards shrink to the height the felt leaves rather than overflowing it
    // on a short phone.
    return LayoutBuilder(builder: (context, constraints) {
      final preferred = compact ? 60.0 : 72.0;
      final fits = (constraints.maxHeight - gap - 30) / 1.4;
      final cardWidth =
          fits.isFinite ? fits.clamp(30.0, preferred).toDouble() : preferred;
      final cardHeight = cardWidth * 1.4;
      final trayHeight = constraints.maxHeight.isFinite
          ? (constraints.maxHeight - 30)
              .clamp(24.0, compact ? 50.0 : 68.0)
              .toDouble()
          : (compact ? 50.0 : 68.0);

      return Stack(
        children: [
          Positioned.fill(
              child: _dealerColumn(
            cards: cards,
            badge: cards.isEmpty
                ? null
                : _HandBadge(
                    label: holeDown ? '${dealer.visibleValue} + ?' : null,
                    value: dealer.visibleValue,
                    isBust: isBust,
                    isBlackjack: !holeDown && dealer.isBlackjack,
                  ),
            cardWidth: cardWidth,
            cardHeight: cardHeight,
          )),
          // The shoe's discards, for estimating decks left — the true count's
          // divisor. Hidden for a continuous shuffler, where nothing piles up.
          if (!ref.watch(tableEngineProvider).continuous)
            Positioned(
              top: compact ? 4 : 10,
              right: 14,
              child: DiscardTray(
                penetration: state.deckPenetration,
                decks: decks,
                height: trayHeight,
              ),
            ),
        ],
      );
    });
  }

  Widget _dealerColumn({
    required List<CardModel> cards,
    required Widget? badge,
    required double cardWidth,
    required double cardHeight,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Score badge
        if (badge != null)
          badge
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
        SizedBox(height: compact ? 6 : 8),

        // Card row
        SizedBox(
          height: cardHeight,
          child: cards.isEmpty
              ? _emptyRow(cardWidth)
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < cards.length; i++)
                        Padding(
                          padding:
                              EdgeInsets.only(left: i == 0 ? 0 : 6, right: 0),
                          child: CardWidget(card: cards[i], width: cardWidth),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _emptyRow(double cardWidth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CardWidget(card: null, width: cardWidth),
        const SizedBox(width: 8),
        CardWidget(card: null, width: cardWidth),
      ],
    );
  }
}

class _HandBadge extends StatelessWidget {
  final int value;
  final bool isBust;
  final bool isBlackjack;

  /// Overrides the plain number, e.g. "10 + ?" while the hole card is down.
  final String? label;

  const _HandBadge({
    required this.value,
    this.label,
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
      label = this.label ?? '$value';
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

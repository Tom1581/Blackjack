import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/game_state.dart';
import '../../../core/models/hand_model.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';
import 'card_widget.dart';

class PlayerArea extends ConsumerWidget {
  final bool compact;

  const PlayerArea({super.key, this.compact = false});

  /// Room the score badge and the gap above it take under the cards.
  static const _badgeAllowance = 30.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final hands = state.playerHands;
    final split = hands.length > 1;
    final gap = compact ? 6.0 : 8.0;

    // Size the cards to the space the felt actually leaves. They used to be a
    // fixed size, so a short phone showing three hands and a coaching note
    // overflowed the bottom of the table.
    return LayoutBuilder(builder: (context, constraints) {
      final pointer = split ? (compact ? 30.0 : 36.0) : 0.0;
      final preferred = compact ? 60.0 : 72.0;
      final fits =
          (constraints.maxHeight - pointer - gap - _badgeAllowance) / 1.4;
      final cardWidth =
          fits.isFinite ? fits.clamp(30.0, preferred).toDouble() : preferred;

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!split)
            _handRow(hands[0], 0, state,
                isSplit: false, cardWidth: cardWidth, pointer: 0)
          else
            SizedBox(
              height: pointer + cardWidth * 1.4 + gap + _badgeAllowance,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: hands.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) => _handRow(hands[i], i, state,
                    isSplit: true, cardWidth: cardWidth, pointer: pointer),
              ),
            ),
        ],
      );
    });
  }

  Widget _handRow(
    HandModel hand,
    int index,
    GameState state, {
    required bool isSplit,
    required double cardWidth,
    required double pointer,
  }) {
    final isActive =
        index == state.activeHandIndex && state.phase == GamePhase.playerTurn;
    final result =
        state.handResults.length > index ? state.handResults[index] : null;
    final showPointer = isSplit && isActive;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reserve space for the active-hand pointer above split hands so all
        // siblings have the same vertical alignment. Only the active one
        // actually renders the pill.
        if (isSplit)
          SizedBox(
            height: pointer,
            child:
                showPointer ? const Center(child: _ActiveHandPointer()) : null,
          ),

        // Card row
        SizedBox(
          height: cardWidth * 1.4,
          child: hand.cards.isEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CardWidget(card: null, width: cardWidth),
                    const SizedBox(width: 8),
                    CardWidget(card: null, width: cardWidth),
                  ],
                )
              : hand.cards.length <= 4
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < hand.cards.length; i++)
                          Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                            child: CardWidget(
                              card: hand.cards[i],
                              width: cardWidth,
                            ),
                          ),
                      ],
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < hand.cards.length; i++)
                            Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                              child: CardWidget(
                                card: hand.cards[i],
                                width: cardWidth,
                              ),
                            ),
                        ],
                      ),
                    ),
        ),
        SizedBox(height: compact ? 6 : 8),

        // Score badge
        if (hand.cards.isNotEmpty)
          _HandBadge(hand: hand, isActive: isActive, result: result),
      ],
    );
  }
}

/// Gold pill ("PLAYING ↓") that bounces above the currently active split
/// hand so the player can tell which hand will receive Hit/Stand/Double.
class _ActiveHandPointer extends StatefulWidget {
  const _ActiveHandPointer();

  @override
  State<_ActiveHandPointer> createState() => _ActiveHandPointerState();
}

class _ActiveHandPointerState extends State<_ActiveHandPointer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 750),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // Bounce 0..5px downward so the arrow appears to "tap" the cards.
        final dy = _ctrl.value * 5;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.55),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PLAYING',
                  style: TextStyle(
                    color: AppColors.wood,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_downward_rounded,
                  color: AppColors.wood,
                  size: 16,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HandBadge extends StatelessWidget {
  final HandModel hand;
  final bool isActive;
  final GameResult? result;

  const _HandBadge({
    required this.hand,
    required this.isActive,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor = Colors.white;
    String label = '${hand.value}';

    if (hand.surrendered) {
      label = 'SURRENDERED';
      bgColor = Colors.black.withValues(alpha: 0.65);
      textColor = AppColors.neutral;
    } else if (hand.isBust) {
      label = 'BUST';
      bgColor = AppColors.unfavorable.withValues(alpha: 0.85);
    } else if (hand.isBlackjack) {
      label = 'BJ!';
      bgColor = AppColors.gold.withValues(alpha: 0.9);
      textColor = AppColors.wood;
    } else if (result == GameResult.win ||
        result == GameResult.dealerBust ||
        result == GameResult.blackjack) {
      bgColor = AppColors.favorable.withValues(alpha: 0.8);
    } else if (result == GameResult.loss || result == GameResult.bust) {
      bgColor = AppColors.unfavorable.withValues(alpha: 0.8);
    } else if (isActive) {
      bgColor = AppColors.gold.withValues(alpha: 0.9);
      textColor = AppColors.wood;
    } else {
      bgColor = Colors.black.withValues(alpha: 0.65);
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? AppColors.gold.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.2),
          width: isActive ? 1.5 : 1,
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

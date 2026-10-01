import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/card_model.dart';
import '../../../core/models/hand_model.dart';
import '../../../theme/app_theme.dart';
import '../../table/widgets/card_widget.dart';
import '../hilo_training_session.dart';

/// The felt: the dealer's hand across the top and the seats in a row below,
/// first base on the right. That is the dealer's left, where every round
/// starts, so the cards travel across the screen the way they do at a table.
///
/// Card size follows the space: five seats on a 320dp phone get smaller cards
/// than one seat on a tablet, and nothing overflows either way.
class HiLoTableView extends StatelessWidget {
  final HiLoTrainingSession session;

  const HiLoTableView({super.key, required this.session});

  static const maxCardWidth = 64.0;
  static const _seatGap = 8.0;
  static const _labelHeight = 18.0;

  /// Room between a seat's total and the top of its betting box.
  static const _seatBoxGap = 8.0;

  /// A seat has room for this many cards at full spacing before they close up.
  static const _seatCardsAtFullSpacing = 4;
  static const _seatStepY = 0.26;
  static const _seatStepX = 0.14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final seats = session.seats;
      final n = seats.length;
      final seatWidth = ((c.maxWidth - _seatGap * (n - 1)) / n).floorToDouble();

      // Height budget: dealer label, card and total; the seats' totals and
      // cascades; and at least a small gap between them.
      const seatDepth = 1 + (_seatCardsAtFullSpacing - 1) * _seatStepY;
      final byHeight = (c.maxHeight - 3 * _labelHeight - _seatBoxGap - 16) /
          (1.4 * (1 + seatDepth));
      final cardWidth = math
          .min(maxCardWidth, math.min(seatWidth / 1.15, byHeight))
          .clamp(24.0, maxCardWidth);
      final cardHeight = cardWidth * 1.4;
      final seatBoxHeight = cardHeight * seatDepth;
      final round = session.round;

      return Column(
        children: [
          const _Label('DEALER'),
          _HandFan(
            cards: session.dealer.cards,
            cardWidth: cardWidth,
            width: c.maxWidth,
            height: cardHeight,
            stepX: cardWidth * 0.55,
            stepY: 0,
            keyPrefix: 'r$round-d',
          ),
          _Total(session.dealer, dealer: true),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First base (seat 0) sits on the right.
              for (var i = n - 1; i >= 0; i--) ...[
                SizedBox(
                  width: seatWidth,
                  // The total sits above the betting box, so it stays put
                  // while the cards cascade down.
                  child: Column(
                    children: [
                      _Total(seats[i]),
                      const SizedBox(height: _seatBoxGap),
                      _Seat(
                        hand: seats[i],
                        active: session.activeSeat == i,
                        cardWidth: cardWidth,
                        width: seatWidth,
                        height: seatBoxHeight,
                        keyPrefix: 'r$round-s$i',
                      ),
                    ],
                  ),
                ),
                if (i > 0) const SizedBox(width: _seatGap),
              ],
            ],
          ),
        ],
      );
    });
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: HiLoTableView._labelHeight,
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.gold.withValues(alpha: 0.6),
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.5,
        ),
      ),
    );
  }
}

/// A hand's total under its cards. The dealer's shows only what is face up.
class _Total extends StatelessWidget {
  final HandModel hand;
  final bool dealer;

  const _Total(this.hand, {this.dealer = false});

  @override
  Widget build(BuildContext context) {
    var text = '';
    var color = Colors.white.withValues(alpha: 0.75);
    if (hand.cards.isNotEmpty) {
      final value = dealer ? hand.visibleValue : hand.value;
      if (dealer && hand.hasFaceDown) {
        text = '$value';
      } else if (hand.isNatural) {
        text = 'BJ';
        color = AppColors.gold;
      } else if (value > 21) {
        text = 'BUST';
        color = AppColors.unfavorable;
      } else {
        text = '$value';
      }
    }
    return SizedBox(
      height: HiLoTableView._labelHeight,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// A seat's betting box with its cards cascading down it. The seat taking
/// cards is outlined in gold.
class _Seat extends StatelessWidget {
  final HandModel hand;
  final bool active;
  final double cardWidth;
  final double width;
  final double height;
  final String keyPrefix;

  const _Seat({
    required this.hand,
    required this.active,
    required this.cardWidth,
    required this.width,
    required this.height,
    required this.keyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final boxWidth = math.min(width, cardWidth + 10);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: boxWidth,
              height: cardWidth * 1.4 + 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active
                      ? AppColors.gold.withValues(alpha: 0.85)
                      : Colors.white.withValues(alpha: 0.12),
                  width: active ? 1.6 : 1,
                ),
              ),
            ),
          ),
          _HandFan(
            cards: hand.cards,
            cardWidth: cardWidth,
            width: width,
            height: height,
            stepX: cardWidth * HiLoTableView._seatStepX,
            stepY: cardWidth * 1.4 * HiLoTableView._seatStepY,
            keyPrefix: keyPrefix,
          ),
        ],
      ),
    );
  }
}

/// Cards laid out from the top-left, each [stepX] right and [stepY] down from
/// the one before, closing up when there are more than the box holds.
class _HandFan extends StatelessWidget {
  final List<CardModel> cards;
  final double cardWidth;
  final double width;
  final double height;
  final double stepX;
  final double stepY;
  final String keyPrefix;

  const _HandFan({
    required this.cards,
    required this.cardWidth,
    required this.width,
    required this.height,
    required this.stepX,
    required this.stepY,
    required this.keyPrefix,
  });

  @override
  Widget build(BuildContext context) {
    final n = cards.length;
    final cardHeight = cardWidth * 1.4;
    final dx = n < 2
        ? 0.0
        : math.max(0.0, math.min(stepX, (width - cardWidth) / (n - 1)));
    final dy = n < 2
        ? 0.0
        : math.max(0.0, math.min(stepY, (height - cardHeight) / (n - 1)));
    final left = (width - cardWidth - dx * (n - 1)) / 2;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: left + dx * i,
              top: dy * i,
              child: CardWidget(
                key: ValueKey('$keyPrefix$i'),
                card: cards[i],
                width: cardWidth,
              ),
            ),
        ],
      ),
    );
  }
}

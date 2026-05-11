import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/models/card_model.dart';
import '../../../theme/app_theme.dart';

class CardWidget extends StatefulWidget {
  final CardModel? card;
  final double width;
  final bool animate;

  const CardWidget({
    super.key,
    this.card,
    this.width = 72,
    this.animate = true,
  });

  @override
  State<CardWidget> createState() => _CardWidgetState();
}

class _CardWidgetState extends State<CardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _flip;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );
    _flip = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.animate && widget.card?.faceUp == true) {
      _ctrl.forward();
    } else if (widget.card?.faceUp == true) {
      _ctrl.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(CardWidget old) {
    super.didUpdateWidget(old);
    if (old.card?.faceUp != widget.card?.faceUp && widget.card?.faceUp == true) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * 1.4;

    if (widget.card == null) {
      return _emptySlot(w, h);
    }

    return AnimatedBuilder(
      animation: _flip,
      builder: (_, __) {
        final angle = _flip.value * pi;
        final showFront = angle <= pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle > pi / 2 ? pi - angle : angle),
          child: showFront
              ? _backFace(w, h)
              : _frontFace(widget.card!, w, h),
        );
      },
    );
  }

  Widget _frontFace(CardModel card, double w, double h) {
    final isRed = card.suit.isRed;
    final suitColor = isRed ? AppColors.hearts : AppColors.clubs;
    return _cardContainer(
      w,
      h,
      color: AppColors.cardFace,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Stack(
          children: [
            // Top-left rank + suit
            Positioned(
              top: 0,
              left: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.rank.display,
                    style: TextStyle(
                      color: suitColor,
                      fontSize: w * 0.26,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  Text(
                    card.suit.symbol,
                    style: TextStyle(color: suitColor, fontSize: w * 0.19),
                  ),
                ],
              ),
            ),
            // Center suit symbol
            Center(
              child: Text(
                card.suit.symbol,
                style: TextStyle(
                  color: suitColor,
                  fontSize: w * 0.44,
                ),
              ),
            ),
            // Bottom-right (rotated)
            Positioned(
              bottom: 0,
              right: 0,
              child: RotatedBox(
                quarterTurns: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.rank.display,
                      style: TextStyle(
                        color: suitColor,
                        fontSize: w * 0.26,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    Text(
                      card.suit.symbol,
                      style: TextStyle(color: suitColor, fontSize: w * 0.19),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _backFace(double w, double h) {
    return _cardContainer(
      w,
      h,
      color: AppColors.cardBack,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1,
              ),
              // Subtle diagonal pattern
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1A3D9A).withValues(alpha: 0.8),
                  const Color(0xFF2255C2),
                  const Color(0xFF1A3D9A).withValues(alpha: 0.8),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Center(
              child: Text(
                '♦',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: w * 0.35,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptySlot(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.5,
        ),
      ),
    );
  }

  Widget _cardContainer(double w, double h,
      {required Color color, required Widget child}) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(2, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 3,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

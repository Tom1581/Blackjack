import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// The discard tray, drawn the way it sits on a real table: a clear box whose
/// stack of used cards grows through the shoe, with a tick at every deck.
///
/// This is how a counter finds the true count in a casino — nobody announces
/// how many decks are left, you read it off the tray. It deliberately carries
/// no number: estimating from the stack is the skill being practised.
class DiscardTray extends StatelessWidget {
  /// 0–1, how much of the shoe has been dealt.
  final double penetration;
  final int decks;
  final double height;

  const DiscardTray({
    super.key,
    required this.penetration,
    required this.decks,
    this.height = 72,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Discard tray, about '
          '${(penetration * decks).toStringAsFixed(1)} of $decks decks played',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 30,
            height: height,
            child: CustomPaint(
              painter: _TrayPainter(
                fill: penetration.clamp(0.0, 1.0),
                decks: decks,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'DISCARDS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 6.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrayPainter extends CustomPainter {
  final double fill;
  final int decks;

  _TrayPainter({required this.fill, required this.decks});

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(
        box, Paint()..color = Colors.black.withValues(alpha: 0.28));

    // The stack of used cards, edges up, filling from the bottom.
    final inner = size.height - 4;
    final stackHeight = inner * fill;
    if (stackHeight > 0) {
      final stack = Rect.fromLTWH(
        3,
        size.height - 2 - stackHeight,
        size.width - 6,
        stackHeight,
      );
      canvas.drawRect(stack, Paint()..color = const Color(0xFFF4EFE3));
      // Card edges.
      final edge = Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..strokeWidth = 0.6;
      for (var y = stack.bottom - 2; y > stack.top; y -= 2.2) {
        canvas.drawLine(Offset(stack.left, y), Offset(stack.right, y), edge);
      }
    }

    // One tick per deck, so the stack can be read in decks.
    final tick = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.75)
      ..strokeWidth = 1;
    for (var d = 1; d < decks; d++) {
      final y = size.height - 2 - inner * d / decks;
      canvas.drawLine(Offset(0, y), Offset(5, y), tick);
      canvas.drawLine(Offset(size.width - 5, y), Offset(size.width, y), tick);
    }

    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(_TrayPainter old) =>
      old.fill != fill || old.decks != decks;
}

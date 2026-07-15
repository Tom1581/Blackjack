import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Shared casino-felt backdrop: a radial green gradient with faint scattered
/// suit watermarks, matching the lobby and single-player table. Wrap a screen's
/// content in this for a consistent premium look.
class FeltBackground extends StatelessWidget {
  final Widget child;
  const FeltBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.4),
                radius: 1.3,
                colors: [
                  Color(0xFF1E6A34),
                  Color(0xFF0E3D1E),
                  Color(0xFF05160B),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _SuitWatermarkPainter()),
          ),
        ),
        child,
      ],
    );
  }
}

class _SuitWatermarkPainter extends CustomPainter {
  static const _suits = ['♠', '♥', '♦', '♣'];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    for (var i = 0; i < 16; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final fontSize = 24 + rng.nextDouble() * 40;
      final suitIdx = rng.nextInt(4);
      final isRed = suitIdx == 1 || suitIdx == 2;
      final color = (isRed ? AppColors.hearts : Colors.white)
          .withValues(alpha: 0.03 + rng.nextDouble() * 0.03);

      final tp = TextPainter(
        text: TextSpan(
          text: _suits[suitIdx],
          style: TextStyle(color: color, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_SuitWatermarkPainter oldDelegate) => false;
}

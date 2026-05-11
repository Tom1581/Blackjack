import 'package:flutter/material.dart';

/// Stylized crown drawn as a CustomPaint so it can be tinted (gold for 1st,
/// silver for 2nd, bronze/copper for 3rd). Material doesn't ship a real
/// crown icon — the trophy/medal alternatives don't read as "crown" — so
/// this draws a simple 3-point crown with gem dots.
class CrownIcon extends StatelessWidget {
  final Color color;
  final double size;

  const CrownIcon({
    required this.color,
    this.size = 28,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CrownPainter(color)),
    );
  }
}

class _CrownPainter extends CustomPainter {
  final Color color;
  _CrownPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.04;

    // Crown body (5 points, 4 valleys)
    final path = Path()
      ..moveTo(w * 0.05, h * 0.85)
      ..lineTo(w * 0.05, h * 0.32)
      ..lineTo(w * 0.22, h * 0.55)
      ..lineTo(w * 0.32, h * 0.18)
      ..lineTo(w * 0.5, h * 0.5)
      ..lineTo(w * 0.68, h * 0.18)
      ..lineTo(w * 0.78, h * 0.55)
      ..lineTo(w * 0.95, h * 0.32)
      ..lineTo(w * 0.95, h * 0.85)
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    // Base bar
    final baseRect = Rect.fromLTRB(w * 0.02, h * 0.85, w * 0.98, h * 0.95);
    canvas.drawRRect(
      RRect.fromRectAndRadius(baseRect, Radius.circular(w * 0.04)),
      fill,
    );

    // Gem highlights at the top of each major peak
    final gemFill = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final gemStroke = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.02;

    for (final peak in [Offset(w * 0.32, h * 0.18), Offset(w * 0.68, h * 0.18)]) {
      canvas.drawCircle(peak, w * 0.05, gemFill);
      canvas.drawCircle(peak, w * 0.05, gemStroke);
    }
    // Center, slightly larger, tinted gem
    final centerGem = Paint()
      ..color = Color.lerp(color, Colors.white, 0.5) ?? Colors.white;
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.07, centerGem);
    canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.07, gemStroke);
  }

  @override
  bool shouldRepaint(_CrownPainter old) => old.color != color;
}

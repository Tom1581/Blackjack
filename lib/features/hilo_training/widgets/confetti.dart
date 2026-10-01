import 'dart:math';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// A one-shot burst of confetti for a new best, a perfect game or a won
/// challenge. Draws over whatever it sits on and never takes a tap.
class Confetti extends StatefulWidget {
  final int pieces;
  final Duration duration;

  const Confetti({
    super.key,
    this.pieces = 70,
    this.duration = const Duration(milliseconds: 2800),
  });

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _Piece {
  final double x;
  final double delay;
  final double speed;
  final double sway;
  final double spin;
  final double size;
  final Color color;

  _Piece(Random r)
      : x = r.nextDouble(),
        delay = r.nextDouble() * 0.35,
        speed = 0.7 + r.nextDouble() * 0.6,
        sway = (r.nextDouble() - 0.5) * 60,
        spin = (r.nextDouble() - 0.5) * 12,
        size = 5 + r.nextDouble() * 5,
        color = const [
          AppColors.gold,
          AppColors.goldLight,
          AppColors.favorable,
          AppColors.hearts,
          Colors.white,
          Color(0xFF5AB0FF),
        ][r.nextInt(6)];
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration)..forward();
  late final List<_Piece> _pieces = [
    for (var i = 0; i < widget.pieces; i++) _Piece(Random(i * 7919 + 13)),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => _ctrl.isCompleted
            ? const SizedBox.shrink()
            : CustomPaint(
                size: Size.infinite,
                painter: _ConfettiPainter(_pieces, _ctrl.value),
              ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;

  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = p.x * size.width + sin(local * pi * 3) * p.sway;
      paint.color = p.color.withValues(alpha: (1 - local * 0.6).clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * p.spin);
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: p.size, height: p.size * 0.5),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// The home screen's brand: "Hi-Lo Blackjack Trainer", the name on the Play
/// listing and under the icon, set as HI-LO / BLACKJACK / TRAINER around a
/// shimmering gold wordmark.
///
/// The wordmark is one word and must stay one: it is set at 44 with wide
/// tracking, which needs about 350 logical pixels — more than a 320 or 360
/// phone has — so it scales down to fit rather than breaking mid-word.
class BrandLockup extends StatelessWidget {
  final Animation<double> shimmer;

  const BrandLockup({super.key, required this.shimmer});

  static const name = 'Hi-Lo Blackjack Trainer';

  @override
  Widget build(BuildContext context) {
    final small = TextStyle(
      color: AppColors.gold.withValues(alpha: 0.9),
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 6,
    );
    return Semantics(
      header: true,
      label: name,
      excludeSemantics: true,
      child: Column(
        children: [
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Suit('♠', AppColors.neutral),
              SizedBox(width: 14),
              _Suit('♥', AppColors.hearts),
              SizedBox(width: 14),
              _Suit('♦', AppColors.diamonds),
              SizedBox(width: 14),
              _Suit('♣', AppColors.neutral),
            ],
          ),
          const SizedBox(height: 10),
          // Tracking leaves a gap after the last letter; pad the front to
          // match so each word stays centred.
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child:
                Text('HI-LO', key: const ValueKey('brand-hilo'), style: small),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: AnimatedBuilder(
              animation: shimmer,
              builder: (_, child) => ShaderMask(
                shaderCallback: (rect) {
                  final t = shimmer.value;
                  return LinearGradient(
                    begin: Alignment(-1.5 + t * 3, -0.4),
                    end: Alignment(0.5 + t * 3, 0.4),
                    colors: const [
                      Color(0xFFB8860B),
                      Color(0xFFD4AF37),
                      Color(0xFFFFE680),
                      Color(0xFFD4AF37),
                      Color(0xFFB8860B),
                    ],
                    stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                  ).createShader(rect);
                },
                child: child,
              ),
              child: const Text(
                'BLACKJACK',
                key: ValueKey('brand-wordmark'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 8,
                  shadows: [Shadow(color: Color(0x80D4AF37), blurRadius: 22)],
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Text(
              'TRAINER',
              key: const ValueKey('brand-trainer'),
              style: small.copyWith(letterSpacing: 9),
            ),
          ),
          const SizedBox(height: 12),
          const _OrnamentDivider(),
        ],
      ),
    );
  }
}

class _Suit extends StatelessWidget {
  final String symbol;
  final Color color;
  const _Suit(this.symbol, this.color);

  @override
  Widget build(BuildContext context) {
    return Text(
      symbol,
      style: TextStyle(
        color: color.withValues(alpha: 0.72),
        fontSize: 16,
        shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
      ),
    );
  }
}

class _OrnamentDivider extends StatelessWidget {
  const _OrnamentDivider();

  @override
  Widget build(BuildContext context) {
    Widget line(List<double> alphas) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                for (final a in alphas) AppColors.gold.withValues(alpha: a),
              ]),
            ),
          ),
        );
    const diamond = Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Icon(Icons.diamond, size: 9, color: AppColors.gold),
    );
    return Row(
      children: [
        line([0, 0.55]),
        diamond,
        line([0.55, 0.55]),
        diamond,
        line([0.55, 0]),
      ],
    );
  }
}

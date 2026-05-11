import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

/// Visualizes a bet amount as a vertical stack of casino chips on the felt.
/// Greedy denomination breakdown (500/100/50/25/5), largest at the bottom of
/// the stack. Animates when [amount] changes.
class ChipStack extends StatelessWidget {
  final int amount;
  final String? label;
  final Color? labelColor;
  final double chipSize;
  final int maxVisibleChips;

  /// When false the dollar total is omitted — useful when the parent (e.g.
  /// a betting circle) already displays the amount.
  final bool showAmount;

  const ChipStack({
    super.key,
    required this.amount,
    this.label,
    this.labelColor,
    this.chipSize = 30,
    this.maxVisibleChips = 8,
    this.showAmount = true,
  });

  static const _denoms = [500, 100, 50, 25, 5];
  static const _denomColors = [
    Color(0xFF6A1B9A), // 500 purple
    Color(0xFF1A1A1A), // 100 black
    Color(0xFF1155BB), // 50  blue
    Color(0xFF1E6B32), // 25  green
    Color(0xFFCC2222), // 5   red
  ];

  static List<int> breakdown(int amount) {
    final chips = <int>[];
    var rem = amount;
    for (final d in _denoms) {
      while (rem >= d) {
        chips.add(d);
        rem -= d;
      }
    }
    return chips;
  }

  static Color _colorFor(int denom) {
    final idx = _denoms.indexOf(denom);
    return idx >= 0 ? _denomColors[idx] : AppColors.gold;
  }

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) {
      return SizedBox(width: chipSize + 4, height: chipSize * 2);
    }

    // Largest at the bottom of the stack — paint order is bottom→top.
    final allChips = breakdown(amount);
    final visible = allChips.length <= maxVisibleChips
        ? allChips
        : allChips.take(maxVisibleChips).toList();
    final extra = allChips.length - visible.length;

    // Each chip exposes ~28% of itself above the chip below it.
    final exposed = chipSize * 0.28;
    final stackHeight = chipSize + (visible.length - 1) * exposed;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: labelColor ?? AppColors.gold.withValues(alpha: 0.85),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              shadows: [
                Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 3),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        SizedBox(
          width: chipSize + 12,
          height: stackHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              for (var i = 0; i < visible.length; i++)
                Positioned(
                  bottom: i * exposed,
                  child: _ChipDisc(
                    value: visible[i],
                    color: _colorFor(visible[i]),
                    size: chipSize,
                  ),
                ),
              if (extra > 0)
                Positioned(
                  top: -2,
                  right: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+$extra',
                      style: const TextStyle(
                        color: AppColors.wood,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (showAmount) ...[
          const SizedBox(height: 4),
          Text(
            '\$$amount',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(
                    color: Colors.black.withValues(alpha: 0.7), blurRadius: 4),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ChipDisc extends StatelessWidget {
  final int value;
  final Color color;
  final double size;

  const _ChipDisc({
    required this.value,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.7,
          height: size * 0.7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            value >= 1000 ? '${value ~/ 1000}K' : '$value',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.32,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

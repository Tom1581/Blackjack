import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

/// Compact Hi-Lo count HUD displayed in the top rail.
/// Shows running count, true count, and shoe penetration in one row.
class CountHud extends ConsumerStatefulWidget {
  const CountHud({super.key});

  @override
  ConsumerState<CountHud> createState() => _CountHudState();
}

class _CountHudState extends ConsumerState<CountHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tableProvider);
    final show = ref.watch(showCountProvider);

    if (!show) return const SizedBox.shrink();

    if (state.runningCount != _lastCount) {
      _lastCount = state.runningCount;
      _pulse.forward(from: 0);
    }

    final rc = state.runningCount;
    final tc = state.trueCount;
    final color = _signalColor(tc);
    final rcStr = rc >= 0 ? '+$rc' : '$rc';
    final tcStr = tc >= 0 ? '+${tc.toStringAsFixed(1)}' : tc.toStringAsFixed(1);
    final penetration = state.deckPenetration;

    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RC
            Text(
              'RC ',
              style: TextStyle(
                color: AppColors.neutral.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              rcStr,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            Container(
              width: 1,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 7),
              color: Colors.white.withValues(alpha: 0.2),
            ),
            // TC
            Text(
              'TC ',
              style: TextStyle(
                color: AppColors.neutral.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              tcStr,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            // Shoe bar
            const SizedBox(width: 8),
            _ShoeBar(penetration: penetration),
          ],
        ),
      ),
    );
  }

  Color _signalColor(double tc) {
    if (tc >= 2) return AppColors.favorable;
    if (tc <= -1) return AppColors.unfavorable;
    return AppColors.neutral;
  }
}

class _ShoeBar extends StatelessWidget {
  final double penetration;
  const _ShoeBar({required this.penetration});

  @override
  Widget build(BuildContext context) {
    final barColor = penetration > 0.75 ? AppColors.unfavorable : AppColors.gold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SHOE',
          style: TextStyle(
            color: AppColors.neutral.withValues(alpha: 0.6),
            fontSize: 7,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: 36,
            height: 4,
            child: LinearProgressIndicator(
              value: penetration.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/rules/rule_set.dart';
import '../../../theme/app_theme.dart';
import '../../table/table_screen.dart' show formatChips;
import '../../training/drills.dart' show StrategyDrillHand;
import '../next_step.dart' show spotLabel;
import '../session_report.dart';

/// After a table session: how it went, the one mistake that mattered, and
/// the drill to do next. Returns the drill if the player chose it.
Future<NextDrill?> showSessionReportSheet(
  BuildContext context, {
  required SessionReport report,
  required RuleSet rules,
  required int decks,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<NextDrill>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportSheet(report: report, rules: rules, decks: decks),
  );
}

class _ReportSheet extends StatelessWidget {
  final SessionReport report;
  final RuleSet rules;
  final int decks;

  const _ReportSheet({
    required this.report,
    required this.rules,
    required this.decks,
  });

  /// What the chart says for the missed spot, e.g. "Hit".
  String? _chartSays(String spot) {
    final hand = StrategyDrillHand.fromSpot(spot);
    return hand?.answer(rules, decks: decks).label;
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    final net = r.net;
    final miss = r.biggestMistake;
    final strategyPct = r.strategy.accuracyPercent;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('session-report'),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SESSION REPORT',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 13,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${r.hands} hand${r.hands == 1 ? '' : 's'} · '
              '${net >= 0 ? '+' : '−'}\$${formatChips(net.abs())}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _Appear(
              order: 0,
              child: Row(
                children: [
                  Expanded(
                    child: _Tile(
                      label: 'STRATEGY',
                      value: r.strategy.total == 0 ? '—' : '$strategyPct%',
                      detail: r.strategy.total == 0
                          ? 'No chart decisions'
                          : '${r.strategy.correct} of ${r.strategy.total} right',
                      color: r.strategy.total == 0
                          ? Colors.white54
                          : strategyPct >= 90
                              ? AppColors.success
                              : AppColors.gold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Tile(
                      label: 'COUNT',
                      value: r.countChecks.total == 0
                          ? '—'
                          : '${r.countChecks.correct}/${r.countChecks.total}',
                      detail: r.countChecks.total == 0
                          ? 'Hide the count HUD to be quizzed'
                          : 'count checks right',
                      color: r.countChecks.total == 0
                          ? Colors.white54
                          : r.countChecks.accuracy >= 0.8
                              ? AppColors.success
                              : AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Appear(
              order: 1,
              child: miss == null
                  ? const _Callout(
                      key: ValueKey('session-clean'),
                      color: AppColors.success,
                      icon: Icons.verified_outlined,
                      title: 'No chart mistakes',
                      body: 'Every decision the coach graded was right.',
                    )
                  : _Callout(
                      key: const ValueKey('session-mistake'),
                      color: AppColors.error,
                      icon: Icons.gps_fixed,
                      title: 'Biggest mistake: ${spotLabel(miss.spot)}',
                      body: [
                        'Missed ${miss.count == 1 ? 'once' : '${miss.count} times'} '
                            'this session.',
                        if (_chartSays(miss.spot) case final play?)
                          'The chart says $play.',
                      ].join(' '),
                    ),
            ),
            const SizedBox(height: 18),
            _Appear(
              order: 2,
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  key: const ValueKey('session-next-drill'),
                  onPressed: () => Navigator.pop(context, r.nextDrill),
                  icon: const Icon(Icons.fitness_center, size: 20),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(r.nextDrill.label.toUpperCase()),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.drill,
                    foregroundColor: AppColors.bg,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 46,
              child: OutlinedButton(
                key: const ValueKey('session-done'),
                onPressed: () => Navigator.pop(context),
                child: const Text('DONE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades and lifts in, a beat after the one before.
class _Appear extends StatelessWidget {
  final int order;
  final Widget child;
  const _Appear({required this.order, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + order * 140),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final Color color;

  const _Tile({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9.5,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            detail,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;

  const _Callout({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

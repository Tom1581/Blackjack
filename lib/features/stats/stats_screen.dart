import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/progress/player_stats.dart';
import '../../core/strategy/strategy_coach.dart';
import '../../theme/app_theme.dart';
import '../table/table_screen.dart' show formatChips;
import '../training/strategy_drill_screen.dart';

class _StatsSnapshot {
  final PlayerStats table;
  final StrategyRecord strategy;
  final StrategyRecord index;
  final StrategyMastery mastery;

  const _StatsSnapshot({
    required this.table,
    required this.strategy,
    required this.index,
    required this.mastery,
  });
}

/// Re-read every time the screen opens. This used to be a plain
/// FutureProvider, which caches forever — the second visit showed the numbers
/// from the first.
final _statsProvider = FutureProvider.autoDispose<_StatsSnapshot>((ref) async {
  final results = await Future.wait([
    PlayerStatsStore.read(),
    StrategyCoach.read(),
    StrategyCoach.readMastery(),
    StrategyCoach.readIndex(),
  ]);
  return _StatsSnapshot(
    table: results[0] as PlayerStats,
    strategy: results[1] as StrategyRecord,
    mastery: results[2] as StrategyMastery,
    index: results[3] as StrategyRecord,
  );
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'STATS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        centerTitle: true,
      ),
      body: statsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(
            child:
                Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (stats) => _StatsBody(stats: stats),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final _StatsSnapshot stats;

  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final t = stats.table;
    final profit = t.tableNet;
    final profitColor =
        profit >= 0 ? AppColors.favorable : AppColors.unfavorable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StrategyAccuracyCard(record: stats.strategy),
          const SizedBox(height: 12),
          _MasteryCard(mastery: stats.mastery),
          const SizedBox(height: 24),
          _sectionTitle('COUNTING'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  'Count checks',
                  t.countChecks == 0 ? '—' : '${t.countCheckPercent}%',
                  t.countChecks == 0
                      ? AppColors.neutral
                      : t.countCheckPercent >= 90
                          ? AppColors.favorable
                          : AppColors.gold,
                  caption: t.countChecks == 0
                      ? 'Hide the HUD to be quizzed'
                      : '${t.countChecksCorrect} of ${t.countChecks} exact',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statTile(
                  'Bet checks',
                  t.betChecks == 0 ? '—' : '${t.betCheckPercent}%',
                  t.betChecks == 0
                      ? AppColors.neutral
                      : t.betCheckPercent >= 90
                          ? AppColors.favorable
                          : AppColors.gold,
                  caption: t.betChecks == 0
                      ? 'Turn on the bet coach'
                      : '${t.betChecksCorrect} of ${t.betChecks} on the ramp',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statTile(
            'Index plays',
            stats.index.total == 0 ? '—' : '${stats.index.accuracyPercent}%',
            stats.index.total == 0
                ? AppColors.neutral
                : stats.index.accuracyPercent >= 90
                    ? AppColors.favorable
                    : AppColors.gold,
            caption: stats.index.total == 0
                ? 'Turn on index plays in Table Settings'
                : '${stats.index.correct} of ${stats.index.total} decided by '
                    'the count',
          ),
          const SizedBox(height: 24),
          _sectionTitle('TABLE RESULTS'),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: profitColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: profitColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(
                  profit >= 0 ? 'NET AT THE TABLE' : 'NET LOSS AT THE TABLE',
                  style: TextStyle(
                    color: profitColor.withValues(alpha: 0.8),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profit >= 0 ? '+' : '−'}\$${formatChips(profit.abs())}',
                  style: TextStyle(
                    color: profitColor,
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Winnings only — bonuses and reward chips are not counted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              _statTile('Hands played', '${t.hands}', Colors.white),
              _statTile(
                'Win rate',
                t.wins + t.losses == 0
                    ? '—'
                    : '${(t.winRate * 100).toStringAsFixed(1)}%',
                AppColors.favorable,
                caption: 'pushes left out',
              ),
              _statTile('Wins', '${t.wins}', AppColors.favorable),
              _statTile('Losses', '${t.losses}', AppColors.unfavorable),
              _statTile('Pushes', '${t.pushes}', AppColors.neutral),
              _statTile(
                  'Blackjacks', '${t.blackjacks}', const Color(0xFFfbbf24)),
              _statTile('Surrenders', '${t.surrenders}', AppColors.neutral,
                  caption: 'counted as losses'),
              _statTile('Biggest round', '+\$${formatChips(t.biggestWin)}',
                  AppColors.gold),
            ],
          ),
          const SizedBox(height: 28),
          _sectionTitle('TRUE COUNT AT EACH DEAL'),
          const SizedBox(height: 12),
          if (t.trueCountHistory.length < 2)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hands played yet.\n'
                  'Play some hands to see how the count moved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.neutral),
                ),
              ),
            )
          else
            _CountChart(history: t.trueCountHistory),
          const SizedBox(height: 12),
          _sectionTitle('WHAT THE COUNT MEANS'),
          const SizedBox(height: 12),
          _legendCard(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.neutral,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _statTile(String label, String value, Color color, {String? caption}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.neutral, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (caption != null)
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _legendCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow('True Count ≥ +2', 'FAVORABLE — Increase your bet',
              AppColors.favorable),
          const SizedBox(height: 8),
          _legendRow('True Count −1 to +1', 'NEUTRAL — Bet normally',
              AppColors.neutral),
          const SizedBox(height: 8),
          _legendRow('True Count ≤ −1', 'UNFAVORABLE — Reduce your bet',
              AppColors.unfavorable),
          const Divider(color: Colors.white10, height: 20),
          const Text(
            'Low cards (2–6) → +1  •  High cards (10,J,Q,K,A) → −1  •  Neutral (7–9) → 0',
            style: TextStyle(color: AppColors.neutral, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(String count, String meaning, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(count,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            Text(meaning,
                style: const TextStyle(color: AppColors.neutral, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

/// Per-category accuracy and the chart cells missed most, with a way straight
/// into drilling them.
class _MasteryCard extends StatelessWidget {
  final StrategyMastery mastery;

  const _MasteryCard({required this.mastery});

  @override
  Widget build(BuildContext context) {
    final anyDecisions =
        StrategyCategory.values.any((c) => mastery.of(c).total > 0);
    if (!anyDecisions) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in StrategyCategory.values) ...[
            _categoryBar(c.label, mastery.of(c)),
            const SizedBox(height: 10),
          ],
          if (mastery.topMisses.isNotEmpty) ...[
            const Divider(color: Colors.white10, height: 18),
            const Text(
              'MOST MISSED',
              style: TextStyle(
                color: AppColors.neutral,
                fontSize: 10.5,
                letterSpacing: 2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            for (final miss in mastery.topMisses)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        miss.spot,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '×${miss.count}',
                      style: const TextStyle(
                        color: AppColors.unfavorable,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const StrategyDrillScreen(),
                )),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('DRILL MY MISTAKES'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryBar(String label, StrategyRecord r) {
    final pct = r.accuracyPercent;
    final color = r.total == 0
        ? AppColors.neutral
        : pct >= 95
            ? AppColors.favorable
            : pct >= 85
                ? AppColors.gold
                : AppColors.unfavorable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ),
            Text(
              r.total == 0 ? '—' : '$pct%  ·  ${r.total}',
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: r.total == 0 ? 0 : r.accuracy,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// True count at each deal, most recent on the right.
class _CountChart extends StatelessWidget {
  final List<double> history;

  const _CountChart({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: CustomPaint(
        painter: _SparklinePainter(history),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;

  _SparklinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    // Always include zero, so a shoe that stayed positive still shows where
    // neutral is.
    var min = data.reduce((a, b) => a < b ? a : b);
    var max = data.reduce((a, b) => a > b ? a : b);
    if (min > 0) min = 0;
    if (max < 0) max = 0;
    final range = (max - min) == 0 ? 1.0 : (max - min);

    double yOf(double v) => size.height - ((v - min) / range) * size.height;

    canvas.drawLine(
      Offset(0, yOf(0)),
      Offset(size.width, yOf(0)),
      Paint()
        ..color = Colors.white12
        ..strokeWidth = 1,
    );

    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = yOf(data[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final last = data.last;
    final color = last >= 2
        ? AppColors.favorable
        : last <= -1
            ? AppColors.unfavorable
            : AppColors.neutral;
    canvas.drawCircle(Offset(size.width, yOf(last)), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.data != data;
}

/// Basic-strategy accuracy: the one number that says whether someone is
/// actually getting better, as opposed to just getting lucky.
class _StrategyAccuracyCard extends StatelessWidget {
  final StrategyRecord record;

  const _StrategyAccuracyCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final percent = record.accuracyPercent;
    final color = !record.isMeaningful
        ? AppColors.neutral
        : percent >= 95
            ? AppColors.favorable
            : percent >= 85
                ? AppColors.gold
                : AppColors.unfavorable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            'BASIC STRATEGY ACCURACY',
            style: TextStyle(
              color: color.withValues(alpha: 0.85),
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            record.total == 0 ? '—' : '$percent%',
            style: TextStyle(
              color: color,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            record.total == 0
                ? 'Play a few hands to start scoring your decisions'
                : record.isMeaningful
                    ? '${record.correct} of ${record.total} decisions '
                        '· ${record.mistakes} to work on'
                    : '${record.total} decisions so far — '
                        'keep going for a real read',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

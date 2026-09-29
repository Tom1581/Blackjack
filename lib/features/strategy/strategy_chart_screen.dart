import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/card_model.dart';
import '../../core/models/hand_model.dart';
import '../../core/rules/rule_set.dart';
import '../../core/strategy/strategy_chart.dart';
import '../../theme/app_theme.dart';
import '../table/table_provider.dart';

class StrategyChartScreen extends ConsumerWidget {
  const StrategyChartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(tableRulesProvider);
    final decks = ref.watch(tableEngineProvider).numDecks;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'STRATEGY CHART',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            Text(
              '${rules.name} · ${rules.summary}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.gold.withValues(alpha: 0.85),
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$decks-deck shoe — the exact chart the coach scores you '
              'against.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            _Legend(surrender: rules.lateSurrender),
            const SizedBox(height: 14),
            _ChartSection(
              title: 'HARD TOTALS',
              rows: [
                for (final t in StrategyChart.hardRows)
                  (
                    t == 8 ? '≤8' : (t == 18 ? '18+' : '$t'),
                    StrategyChart.hardHand(t),
                  ),
              ],
              rules: rules,
              decks: decks,
            ),
            const SizedBox(height: 16),
            _ChartSection(
              title: 'SOFT TOTALS',
              rows: [
                for (final k in StrategyChart.softRows)
                  ('A,${k.display}', StrategyChart.softHand(k)),
              ],
              rules: rules,
              decks: decks,
            ),
            const SizedBox(height: 16),
            _ChartSection(
              title: 'PAIRS',
              pairs: true,
              rows: [
                for (final r in StrategyChart.pairRows)
                  ('${r.display},${r.display}', StrategyChart.pairHand(r)),
              ],
              rules: rules,
              decks: decks,
            ),
          ],
        ),
      ),
    );
  }
}

Color chartPlayColor(ChartPlay play) {
  switch (play) {
    case ChartPlay.hit:
      return const Color(0xFF2E8B4A);
    case ChartPlay.stand:
      return const Color(0xFFB23A3A);
    case ChartPlay.double:
    case ChartPlay.doubleOrStand:
      return const Color(0xFF2F6FD0);
    case ChartPlay.split:
      return const Color(0xFFC98A1E);
    case ChartPlay.surrenderOrHit:
    case ChartPlay.surrenderOrStand:
    case ChartPlay.surrenderOrSplit:
      return const Color(0xFF6B6F7A);
  }
}

class _Legend extends StatelessWidget {
  final bool surrender;

  const _Legend({required this.surrender});

  @override
  Widget build(BuildContext context) {
    Widget item(ChartPlay p, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: chartPlayColor(p),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                p.code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        item(ChartPlay.hit, 'Hit'),
        item(ChartPlay.stand, 'Stand'),
        item(ChartPlay.double, 'Double, else hit'),
        item(ChartPlay.doubleOrStand, 'Double, else stand'),
        item(ChartPlay.split, 'Split'),
        if (surrender) ...[
          item(ChartPlay.surrenderOrHit, 'Surrender, else hit'),
          item(ChartPlay.surrenderOrStand, 'Surrender, else stand'),
          item(ChartPlay.surrenderOrSplit, 'Surrender, else split'),
        ],
      ],
    );
  }
}

class _ChartSection extends StatelessWidget {
  final String title;
  final List<(String, HandModel)> rows;
  final RuleSet rules;
  final int decks;
  final bool pairs;

  const _ChartSection({
    required this.title,
    required this.rows,
    required this.rules,
    required this.decks,
    this.pairs = false,
  });

  @override
  Widget build(BuildContext context) {
    const labelWidth = 40.0;
    TextStyle head = TextStyle(
      color: AppColors.gold.withValues(alpha: 0.9),
      fontSize: 11,
      fontWeight: FontWeight.w900,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.neutral,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text('DLR', style: head.copyWith(fontSize: 9)),
            ),
            for (final up in StrategyChart.dealerUps)
              Expanded(
                child: Center(
                  child:
                      Text(up == Rank.ace ? 'A' : '${up.value}', style: head),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        for (final (label, hand) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final up in StrategyChart.dealerUps)
                  Expanded(
                    child: _Cell(
                      play: StrategyChart.cell(hand, up, rules,
                          pairs: pairs, decks: decks),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  final ChartPlay play;

  const _Cell({required this.play});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chartPlayColor(play),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        play.code,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

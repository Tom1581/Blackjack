// Every cell of every basic strategy chart the app can deal — 2, 6 and 8
// decks; H17 and S17; with and without DAS; each doubling rule; with and
// without late surrender — against a published strategy engine.
//
// 48 charts × 320 cells. The reference data lives in
// test/fixtures/strategy_reference.dart; see tool/strategy_check/README.md
// for where it came from and how the 2-deck and surrender cells were
// cross-checked independently.

import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/strategy/strategy_chart.dart';

import 'fixtures/strategy_reference.dart';

/// The reference engine's one-letter codes.
String _letter(ChartPlay p) {
  switch (p) {
    case ChartPlay.hit:
      return 'H';
    case ChartPlay.stand:
      return 'S';
    case ChartPlay.double:
      return 'D';
    case ChartPlay.doubleOrStand:
      return 'd';
    case ChartPlay.split:
      return 'P';
    case ChartPlay.surrenderOrHit:
      return 'R';
    case ChartPlay.surrenderOrStand:
      return 'r';
    case ChartPlay.surrenderOrSplit:
      return 'p';
  }
}

const _upLabels = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'A'];

void main() {
  test('the reference covers every rule combination the app deals', () {
    expect(strategyReference, hasLength(48));
  });

  for (final entry in strategyReference.entries) {
    final parts = entry.key.split('_');
    final decks = int.parse(parts[0].substring(1));
    final rules = RuleSet(
      id: entry.key,
      name: entry.key,
      blurb: '',
      dealerHitsSoft17: parts[1] == 'h17',
      doubleAfterSplit: parts[2] == 'dasyes',
      doubleRule: switch (parts[3]) {
        'd9' => DoubleRule.nineToEleven,
        'd10' => DoubleRule.tenAndEleven,
        _ => DoubleRule.anyTwo,
      },
      lateSurrender: parts[4] == 'ls',
    );

    test('chart ${entry.key}', () {
      final ref = entry.value;
      final mismatches = <String>[];

      void check(String row, String expected, ChartPlay Function(Rank up) f) {
        for (var i = 0; i < StrategyChart.dealerUps.length; i++) {
          final got = _letter(f(StrategyChart.dealerUps[i]));
          if (got != expected[i]) {
            mismatches.add('$row v ${_upLabels[i]}: want ${expected[i]} '
                'got $got');
          }
        }
      }

      // Hard 5–17, then 18+ (checked with 18 and 19).
      final hard = ref['hard']!;
      expect(hard, hasLength(14));
      for (var t = 5; t <= 17; t++) {
        check('hard $t', hard[t - 5],
            (up) => StrategyChart.cell(StrategyChart.hardHand(t), up, rules,
                decks: decks));
      }
      for (final t in [18, 19]) {
        check('hard $t', hard[13],
            (up) => StrategyChart.cell(StrategyChart.hardHand(t), up, rules,
                decks: decks));
      }

      final soft = ref['soft']!;
      expect(soft, hasLength(8));
      for (var k = 0; k < StrategyChart.softRows.length; k++) {
        final kicker = StrategyChart.softRows[k];
        check('A,${kicker.display}', soft[k],
            (up) => StrategyChart.cell(StrategyChart.softHand(kicker), up,
                rules,
                decks: decks));
      }

      final pairs = ref['pairs']!;
      expect(pairs, hasLength(10));
      for (var k = 0; k < StrategyChart.pairRows.length; k++) {
        final rank = StrategyChart.pairRows[k];
        check('${rank.display},${rank.display}', pairs[k],
            (up) => StrategyChart.cell(StrategyChart.pairHand(rank), up, rules,
                pairs: true, decks: decks));
      }

      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    });
  }
}

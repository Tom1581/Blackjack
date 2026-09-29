// The Training Center: the strategy card, the drill generators, and a smoke
// test that every training screen opens and runs on a small phone.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_logic.dart';
import 'package:blackjack_app/core/strategy/strategy_chart.dart';
import 'package:blackjack_app/features/strategy/strategy_chart_screen.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/training/drills.dart';
import 'package:blackjack_app/features/training/speed_count_screen.dart';
import 'package:blackjack_app/features/training/strategy_drill_screen.dart';
import 'package:blackjack_app/features/training/training_center_screen.dart';
import 'package:blackjack_app/features/training/true_count_drill_screen.dart';

ChartPlay _hard(int t, Rank up, [RuleSet r = RuleSet.sixDeckH17]) =>
    StrategyChart.cell(StrategyChart.hardHand(t), up, r);
ChartPlay _soft(Rank k, Rank up, [RuleSet r = RuleSet.sixDeckH17]) =>
    StrategyChart.cell(StrategyChart.softHand(k), up, r);
ChartPlay _pair(Rank p, Rank up, [RuleSet r = RuleSet.sixDeckH17]) =>
    StrategyChart.cell(StrategyChart.pairHand(p), up, r, pairs: true);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StrategyCoach.resetForTest();
  });

  group('The strategy card matches a printed chart', () {
    test('hard rows are built from the right hands', () {
      for (final t in StrategyChart.hardRows) {
        final h = StrategyChart.hardHand(t);
        expect(h.value, t);
        expect(h.isSoft, isFalse);
        expect(h.isPair, isFalse);
      }
    });

    test('landmark cells, H17', () {
      expect(_hard(16, Rank.ten), ChartPlay.hit);
      expect(_hard(12, Rank.four), ChartPlay.stand);
      expect(_hard(11, Rank.ace), ChartPlay.double);
      expect(_hard(9, Rank.two), ChartPlay.hit);
      expect(_soft(Rank.seven, Rank.two), ChartPlay.doubleOrStand);
      expect(_soft(Rank.seven, Rank.nine), ChartPlay.hit);
      expect(_soft(Rank.eight, Rank.six), ChartPlay.doubleOrStand);
      expect(_soft(Rank.six, Rank.three), ChartPlay.double);
      expect(_pair(Rank.eight, Rank.ace), ChartPlay.split);
      expect(_pair(Rank.nine, Rank.seven), ChartPlay.stand);
      expect(_pair(Rank.five, Rank.nine), ChartPlay.double);
      expect(_pair(Rank.ten, Rank.six), ChartPlay.stand);
      expect(_pair(Rank.four, Rank.five), ChartPlay.split);
    });

    test('the card changes with the table rules', () {
      expect(_hard(11, Rank.ace, RuleSet.sixDeckS17), ChartPlay.hit);
      expect(_soft(Rank.seven, Rank.two, RuleSet.sixDeckS17), ChartPlay.stand);
      expect(_pair(Rank.four, Rank.five, RuleSet.sixDeckNoDas), ChartPlay.hit);
      expect(_soft(Rank.six, Rank.four, RuleSet.restrictedDouble),
          ChartPlay.hit,
          reason: 'no soft doubles at a hard-9-to-11 table');
    });
  });

  group('Drill generators', () {
    test('Hi-Lo tags', () {
      expect(hiLoTag(const CardModel(suit: Suit.clubs, rank: Rank.six)), 1);
      expect(hiLoTag(const CardModel(suit: Suit.clubs, rank: Rank.eight)), 0);
      expect(hiLoTag(const CardModel(suit: Suit.clubs, rank: Rank.queen)), -1);
      expect(hiLoTag(const CardModel(suit: Suit.clubs, rank: Rank.ace)), -1);
    });

    test('a deck countdown ends on minus what was held back', () {
      final rng = Random(3);
      for (var i = 0; i < 50; i++) {
        final round = SpeedCountRound.generate(SpeedCountLength.deck, rng: rng);
        expect(round.heldBack.length, inInclusiveRange(1, 3));
        expect(round.cards.length + round.heldBack.length, 52);
        expect(round.answer, -runningCountOf(round.heldBack));
      }
    });

    test('true count questions are unambiguous and offer the answer', () {
      final rng = Random(11);
      for (var i = 0; i < 300; i++) {
        final q = TrueCountQuestion.generate(rng: rng);
        final exact = q.runningCount / q.decksLeft;
        final frac = (exact - exact.truncate()).abs();
        expect((frac - 0.5).abs() > 1e-9, isTrue, reason: 'no coin tosses');
        expect(q.options, contains(q.answer));
        expect(q.options.toSet(), hasLength(4));
        expect(q.decksLeft, inInclusiveRange(0.5, 5.5));
      }
    });

    test('focused hands land in the category asked for', () {
      final rng = Random(5);
      for (var i = 0; i < 100; i++) {
        expect(StrategyDrillHand.random(StrategyDrillFocus.soft, rng: rng)
            .category, StrategyCategory.soft);
        expect(StrategyDrillHand.random(StrategyDrillFocus.pairs, rng: rng)
            .category, StrategyCategory.pair);
        final hard =
            StrategyDrillHand.random(StrategyDrillFocus.hard, rng: rng);
        expect(hard.category, StrategyCategory.hard);
        expect(hard.hand.value, inInclusiveRange(8, 17));
      }
    });

    test('a most-missed label deals that exact chart cell', () {
      final rng = Random(9);
      for (final spot in [
        'Hard 16 vs 10',
        'Hard 12 vs 4',
        'Soft 18 vs A',
        '8,8 vs 6',
        'A,A vs 10',
        '10,10 vs 5',
        'Hard 20 vs 9',
      ]) {
        final hand = StrategyDrillHand.fromSpot(spot, rng: rng);
        expect(hand, isNotNull, reason: spot);
        final h = hand!.hand;
        final up = hand.dealerUp.rank.value;
        final upLabel = up == 11 ? 'A' : '$up';
        final String label;
        if (h.isPair) {
          final v = h.cards.first.rank.value;
          final r = v == 11 ? 'A' : '$v';
          label = '$r,$r vs $upLabel';
        } else {
          label = '${h.isSoft ? 'Soft' : 'Hard'} ${h.value} vs $upLabel';
        }
        expect(label, spot);
      }
      expect(StrategyDrillHand.fromSpot('nonsense'), isNull);
    });

    test('the drill grades against the same chart as the coach', () {
      final hand = StrategyDrillHand.fromSpot('Soft 18 vs 2')!;
      expect(hand.answer(RuleSet.sixDeckH17), StrategyMove.double);
      expect(hand.answer(RuleSet.sixDeckS17), StrategyMove.stand);
    });
  });

  group('Online: naturals give the dealer nothing to draw for', () {
    test('a table of naturals leaves the dealer on two cards', () {
      var sampled = 0;
      for (var i = 0; i < 3000 && sampled < 5; i++) {
        final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
        logic.addPlayer('h', 'Host');
        logic.placeBet('h', 10);
        logic.startDeal('h');
        if (logic.state.phase == OnlinePhase.insurance) {
          logic.answerInsurance('h', false);
        }
        final seat = logic.state.seatById('h')!;
        if (seat.hands.length != 1 || !seat.hands.first.hand.isNatural) {
          continue;
        }
        if (logic.state.phase != OnlinePhase.results) continue;
        sampled++;
        expect(logic.state.dealer.cards, hasLength(2));
      }
      expect(sampled, greaterThan(0), reason: 'sanity: sampled a natural');
    });
  });

  group('Every training screen runs on a small phone', () {
    Future<void> open(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: screen)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('training center', (tester) async {
      await open(tester, const TrainingCenterScreen());
      expect(find.text('Speed Count'), findsOneWidget);
      expect(find.text('Daily Count Drill'), findsOneWidget,
          reason: 'the original drill is kept, not replaced');
      await tester.scrollUntilVisible(find.text('Index Plays'), 200);
      expect(find.text('Index Plays'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('strategy chart', (tester) async {
      await open(tester, const StrategyChartScreen());
      expect(find.text('HARD TOTALS'), findsOneWidget);
      expect(find.text('Surrender, else hit'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('strategy chart for a two-deck surrender table',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          rulesProvider.overrideWith((ref) => RuleSet.sixDeckH17Surrender),
          shoeModeProvider.overrideWith((ref) => ShoeMode.twoDeck),
        ],
        child: const MaterialApp(home: StrategyChartScreen()),
      ));
      await tester.pump();
      expect(find.textContaining('2-deck shoe'), findsOneWidget);
      expect(find.text('Surrender, else hit'), findsOneWidget);
      expect(find.text('Rs'), findsWidgets, reason: '17 v A under H17');
      expect(find.text('18+'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('speed count runs to the answer', (tester) async {
      await open(tester, const SpeedCountScreen());
      await tester.tap(find.text('Casino'));
      await tester.pump();
      await tester.tap(find.text('START'));
      for (var i = 0; i < 25; i++) {
        await tester.pump(SpeedCountPace.casino.perCard);
      }
      expect(find.text('CHECK'), findsOneWidget);
      await tester.tap(find.text('CHECK'));
      await tester.pump();
      expect(find.text('GO AGAIN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('true count takes an answer', (tester) async {
      await open(tester, const TrueCountDrillScreen());
      expect(find.text('RUNNING COUNT'), findsOneWidget);
      await tester.tap(find.byType(FilledButton).first);
      await tester.pump();
      expect(find.text('NEXT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('strategy drill deals and grades', (tester) async {
      await open(tester, const StrategyDrillScreen());
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.tap(find.text('STAND'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    });
  });
}

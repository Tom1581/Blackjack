// Hi-Lo index plays: the Illustrious 18 and Fab 4 lists, how they combine
// with the chart and surrender, the floor rule, and grading at the table.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/core/strategy/deviations.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';
import 'package:blackjack_app/features/training/drills.dart';
import 'package:blackjack_app/features/training/index_drill_screen.dart';

CardModel _c(int v, [Suit s = Suit.spades]) =>
    CardModel(suit: s, rank: v == 11 ? Rank.ace : Rank.values[v - 1]);
HandModel _h(int a, int b) => HandModel(cards: [_c(a), _c(b, Suit.hearts)]);

StrategyMove _best(
  HandModel hand,
  int up,
  double tc, {
  RuleSet rules = RuleSet.sixDeckH17,
  int decks = 6,
  bool canDouble = true,
  bool canSplit = true,
  bool canSurrender = false,
}) =>
    Deviations.best(
      hand: hand,
      dealerUp: _c(up, Suit.clubs),
      trueCount: tc,
      rules: rules,
      decks: decks,
      canDouble: canDouble,
      canSplit: canSplit,
      canSurrender: canSurrender,
    );

class _Seeded extends TableNotifier {
  _Seeded(this.seed);
  final GameState seed;

  @override
  GameState build() {
    super.build();
    return seed;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablePrefs.resetForTest();
    StrategyCoach.resetForTest();
  });

  group('The published lists', () {
    test('seventeen hand indices plus insurance, and four surrenders', () {
      expect(Deviations.illustrious18(h17: false), hasLength(17));
      expect(Deviations.fab4(h17: false), hasLength(4));
      expect(Deviations.insuranceIndex, 3);
    });

    test('S17 numbers, as the Wizard of Odds publishes them', () {
      final idx = {
        for (final p in Deviations.illustrious18(h17: false)) p.label: p.index,
        for (final p in Deviations.fab4(h17: false)) 'R ${p.label}': p.index,
      };
      expect(idx, {
        '16 v 10': 0,
        '15 v 10': 4,
        '10,10 v 5': 5,
        '10,10 v 6': 4,
        '10 v 10': 4,
        '12 v 3': 2,
        '12 v 2': 3,
        '11 v A': 1,
        '9 v 2': 1,
        '10 v A': 4,
        '9 v 7': 3,
        '16 v 9': 5,
        '13 v 2': -1,
        '12 v 4': 0,
        '12 v 5': -2,
        '12 v 6': -1,
        '13 v 3': -2,
        'R 14 v 10': 3,
        'R 15 v 10': 0,
        'R 15 v 9': 2,
        'R 15 v A': 1,
      });
    });

    test('H17 shifts exactly four numbers', () {
      Map<String, int> of(bool h17) => {
            for (final p in [
              ...Deviations.illustrious18(h17: h17),
              ...Deviations.fab4(h17: h17),
            ])
              '${p.set.name} ${p.label}': p.index,
          };
      final s17 = of(false), h17 = of(true);
      final changed = {
        for (final k in s17.keys)
          if (s17[k] != h17[k]) k: h17[k],
      };
      expect(changed, {
        'illustrious18 11 v A': -1,
        'illustrious18 10 v A': 3,
        'illustrious18 12 v 6': -3,
        'fab4 15 v A': -1,
      });
    });

    test('every index play reads as a rule', () {
      final p = Deviations.illustrious18(h17: false).first;
      expect(p.rule, 'Stand at 0 or higher, otherwise Hit');
      expect(Deviations.illustrious18(h17: false)[1].rule,
          'Stand at +4 or higher, otherwise Hit');
    });
  });

  group('Applying an index', () {
    test('every entry flips exactly at its index, floored', () {
      for (final h17 in [false, true]) {
        final rules = h17 ? RuleSet.sixDeckH17 : RuleSet.sixDeckS17;
        for (final play in Deviations.illustrious18(h17: h17)) {
          final hand = play.pair
              ? HandModel(cards: [_c(10), _c(10, Suit.hearts)])
              : (play.total >= 12
                  ? _h(10, play.total - 10)
                  : _h(play.total - (play.total ~/ 2 - 1),
                      play.total ~/ 2 - 1));
          expect(_best(hand, play.up, play.index.toDouble(), rules: rules),
              play.atOrAbove,
              reason: '${play.label} at its index, h17=$h17');
          expect(_best(hand, play.up, play.index - 0.1, rules: rules),
              play.below,
              reason: '${play.label} just below, h17=$h17');
        }
      }
    });

    test('+2.9 has not reached an index of +3', () {
      expect(_best(_h(10, 2), 2, 2.9), StrategyMove.hit); // 12 v 2 at +3
      expect(_best(_h(10, 2), 2, 3.0), StrategyMove.stand);
    });

    test('negative indices: 12 v 6 hits below its index', () {
      expect(_best(_h(10, 2), 6, -3.0), StrategyMove.stand); // H17: −3
      expect(_best(_h(10, 2), 6, -3.1), StrategyMove.hit);
      expect(_best(_h(10, 2), 6, -1.5, rules: RuleSet.sixDeckS17),
          StrategyMove.hit); // S17: −1
    });

    test('a pair the chart splits is never touched by a hard-total index', () {
      final eights = HandModel(cards: [_c(8), _c(8, Suit.hearts)]);
      expect(_best(eights, 10, 5), StrategyMove.split,
          reason: '16 v 10 stands at 0 — but 8,8 splits');
      final sixes = HandModel(cards: [_c(6), _c(6, Suit.hearts)]);
      expect(_best(sixes, 4, -5), StrategyMove.split,
          reason: '12 v 4 hits below 0 — but 6,6 v 4 splits');
    });

    test('an index needs the move to be available', () {
      expect(_best(_h(6, 4), 10, 6, canDouble: false), StrategyMove.hit,
          reason: '10 v 10 doubles at +4, but not with three cards');
      final tens = HandModel(cards: [_c(10), _c(10, Suit.hearts)]);
      expect(_best(tens, 6, 6), StrategyMove.split);
      expect(_best(tens, 6, 6, canSplit: false), StrategyMove.stand);
    });

    test('with surrender on, the Fab 4 governs and the chart\'s surrenders hold',
        () {
      const rules = RuleSet.sixDeckS17Surrender;
      // 15 v 10: surrender at 0 or higher, hit below.
      expect(_best(_h(10, 5), 10, 0.2, rules: rules, canSurrender: true),
          StrategyMove.surrender);
      expect(_best(_h(10, 5), 10, 5, rules: rules, canSurrender: true),
          StrategyMove.surrender,
          reason: 'not the no-surrender "stand at +4"');
      expect(_best(_h(10, 5), 10, -0.5, rules: rules, canSurrender: true),
          StrategyMove.hit);
      // 14 v 10: surrender at +3.
      expect(_best(_h(10, 4), 10, 3, rules: rules, canSurrender: true),
          StrategyMove.surrender);
      expect(_best(_h(10, 4), 10, 2.9, rules: rules, canSurrender: true),
          StrategyMove.hit);
      // 16 v 10 is a basic surrender: the stand index stays out of it.
      expect(_best(_h(10, 6), 10, 6, rules: rules, canSurrender: true),
          StrategyMove.surrender);
      // Without surrender on the hand (third card), the I18 stand index is
      // back.
      expect(_best(_h(10, 5), 10, 4, rules: rules), StrategyMove.stand);
    });

    test('15 v A surrender: +1 under S17, −1 under H17', () {
      expect(
          _best(_h(10, 5), 11, 0.5,
              rules: RuleSet.sixDeckS17Surrender, canSurrender: true),
          StrategyMove.hit);
      expect(
          _best(_h(10, 5), 11, 1,
              rules: RuleSet.sixDeckS17Surrender, canSurrender: true),
          StrategyMove.surrender);
      expect(
          _best(_h(10, 5), 11, -1,
              rules: RuleSet.sixDeckH17Surrender, canSurrender: true),
          StrategyMove.surrender);
      expect(
          _best(_h(10, 5), 11, -1.5,
              rules: RuleSet.sixDeckH17Surrender, canSurrender: true),
          StrategyMove.hit);
    });

    test('two-deck shoes and soft hands are left to basic strategy', () {
      expect(_best(_h(10, 6), 10, 5, decks: 2), StrategyMove.hit);
      final soft16 = HandModel(cards: [_c(11), _c(5, Suit.hearts)]);
      expect(_best(soft16, 10, 5),
          BasicStrategy.best(hand: soft16, dealerUp: _c(10, Suit.clubs)));
    });

    test('insurance at +3 or higher', () {
      expect(Deviations.shouldInsure(2.9), isFalse);
      expect(Deviations.shouldInsure(3), isTrue);
    });
  });

  group('The index drill', () {
    test('every question is decided by the play it asks about', () {
      final rng = Random(21);
      var insurance = 0;
      for (var i = 0; i < 600; i++) {
        final rules = i.isEven ? RuleSet.sixDeckH17 : RuleSet.sixDeckS17;
        final q = IndexDrillQuestion.random(rules: rules, rng: rng);
        if (q.isInsurance) {
          insurance++;
          expect(q.insure, q.trueCount >= 3);
          continue;
        }
        final d = q.decision;
        expect(d, isNotNull, reason: q.play!.label);
        expect(d!.play.label, q.play!.label);
        expect(d.play.set, q.play!.set);
        expect(q.answer, q.play!.playAt(q.trueCount));
        expect((q.trueCount - q.play!.index).abs(), lessThanOrEqualTo(3.0));
      }
      expect(insurance, greaterThan(0));
    });

    testWidgets('the drill runs on a small phone', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: IndexDrillScreen())));
      await tester.pump();
      expect(find.byKey(const ValueKey('index-tc')), findsOneWidget);
      final button =
          find.text('STAND').evaluate().isNotEmpty ? 'STAND' : 'NO THANKS';
      await tester.tap(find.text(button));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('At the table', () {
    GameState seed({required double tc, InsuranceState? insurance}) =>
        GameState(
          phase: GamePhase.playerTurn,
          playerHands: [
            HandModel(cards: [_c(10), _c(6, Suit.hearts)], bet: 100),
          ],
          dealerHand: HandModel(cards: [
            _c(insurance == null ? 10 : 11, Suit.clubs),
            const CardModel(
                suit: Suit.hearts, rank: Rank.seven, faceUp: false),
          ]),
          bankroll: 900,
          currentBet: 100,
          spotBets: const [100],
          handResults: const [null],
          trueCount: tc,
          runningCount: (tc * 5).round(),
          insuranceState: insurance ?? InsuranceState.notOffered,
        );

    ProviderContainer container(GameState s,
        {bool indexPlays = true, bool showCount = true}) {
      final c = ProviderContainer(overrides: [
        tableProvider.overrideWith(() => _Seeded(s)),
        indexPlaysProvider.overrideWith((ref) => indexPlays),
        showCountProvider.overrideWith((ref) => showCount),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('the hint follows the count when index plays are on', () {
      expect(container(seed(tc: 1.2)).read(strategyHintProvider),
          StrategyMove.stand);
      expect(container(seed(tc: -0.4)).read(strategyHintProvider),
          StrategyMove.hit);
      expect(
          container(seed(tc: 1.2), indexPlays: false)
              .read(strategyHintProvider),
          StrategyMove.hit,
          reason: 'off: basic strategy only');
    });

    test('with the HUD hidden an index hand gets no hint — it would leak the '
        'count', () {
      expect(
          container(seed(tc: 1.2), showCount: false)
              .read(strategyHintProvider),
          isNull);
    });

    test('hitting 16 v 10 at +1.2 is corrected with the index, and kept off '
        'the chart record', () async {
      final c = container(seed(tc: 1.2));
      c.read(tableProvider.notifier).hit();
      final feedback = c.read(strategyFeedbackProvider);
      expect(feedback, isNotNull);
      expect(feedback!.message, contains('the count says Stand'));
      expect(feedback.message, contains('+1.2'));
      await Future<void>.delayed(Duration.zero);
      expect((await StrategyCoach.readIndex()).total, 1);
      expect((await StrategyCoach.readIndex()).correct, 0);
      expect((await StrategyCoach.read()).total, 0,
          reason: 'a count departure is not a chart decision');
    });

    test('standing 16 v 10 at +1.2 is right, and says nothing', () async {
      final c = container(seed(tc: 1.2));
      c.read(tableProvider.notifier).stand();
      expect(c.read(strategyFeedbackProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect((await StrategyCoach.readIndex()).correct, 1);
    });

    test('below the index the book play counts for both records', () async {
      final c = container(seed(tc: -0.5));
      c.read(tableProvider.notifier).hit();
      expect(c.read(strategyFeedbackProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect((await StrategyCoach.readIndex()).correct, 1);
      expect((await StrategyCoach.read()).correct, 1);
    });

    test('insurance is graded against +3 only with index plays on', () async {
      final low = container(seed(tc: 1, insurance: InsuranceState.offered));
      low.read(tableProvider.notifier).takeInsurance(true);
      expect(low.read(strategyFeedbackProvider)!.message,
          contains('decline it'));

      final high = container(seed(tc: 3.4, insurance: InsuranceState.offered));
      high.read(tableProvider.notifier).takeInsurance(true);
      expect(high.read(strategyFeedbackProvider), isNull);

      final off = container(seed(tc: 1, insurance: InsuranceState.offered),
          indexPlays: false);
      off.read(tableProvider.notifier).takeInsurance(true);
      expect(off.read(strategyFeedbackProvider), isNull,
          reason: 'insurance is not graded on basic strategy alone');
      await Future<void>.delayed(Duration.zero);
      expect((await StrategyCoach.readIndex()).total, 2);
    });

    testWidgets('the table renders an index correction without overflow',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          tableProvider.overrideWith(() => _Seeded(seed(tc: 1.2))),
          indexPlaysProvider.overrideWith((ref) => true),
        ],
        child: const MaterialApp(home: TableScreen()),
      ));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('Hit'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('the count says Stand'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    });
  });
}

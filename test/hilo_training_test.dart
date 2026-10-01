// Hi-Lo Training, the logic: the dealer (count, deal order, dealer rule,
// shoe), the question schedule, scoring, every game mode, the Daily
// Challenge, challenge codes, the profile and its achievements, and the words
// the feature says. Screens are in hilo_training_widget_test.dart.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game.dart';
import 'package:blackjack_app/features/hilo_training/hilo_scoring.dart';
import 'package:blackjack_app/features/hilo_training/hilo_text.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_progress.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_session.dart';
import 'package:blackjack_app/features/hilo_training/seeded_random.dart';
import 'package:blackjack_app/features/hilo_training/widgets/count_quiz_panel.dart';
import 'package:blackjack_app/features/training/drills.dart';

CardModel _c(Rank rank) => CardModel(suit: Suit.clubs, rank: rank);

/// The Hi-Lo total of every face-up card on the felt.
int _visibleOnTable(HiLoTrainingSession s) => [
      ...s.dealer.cards,
      for (final h in s.seats) ...h.cards,
    ].where((c) => c.faceUp).fold(0, (n, c) => n + hiLoTag(c));

/// Every table shape the practice screen offers.
Iterable<HiLoTrainingConfig> _allTables() sync* {
  for (final decks in HiLoTrainingConfig.deckOptions) {
    for (final players in HiLoTrainingConfig.playerOptions) {
      yield HiLoTrainingConfig(decks: decks, players: players, questions: 999);
    }
  }
}

/// Play [game] to the end. [answer] gives each player's answer to each
/// question (null to let the clock run out).
HiLoGame _playOut(
  HiLoGame game,
  int? Function(HiLoQuestion q, int player) answer, {
  Duration took = const Duration(milliseconds: 1500),
}) {
  for (var i = 0; i < 200000 && !game.isOver; i++) {
    if (game.quizDue) {
      final q = game.ask();
      for (var p = 0; p < game.players.length; p++) {
        game.submit(answer(q, game.turn), took: took);
      }
    } else {
      game.session.advance();
    }
  }
  expect(game.isOver, isTrue, reason: 'the game should have ended');
  return game;
}

int? _right(HiLoQuestion q, int _) => q.answer;
int? _wrong(HiLoQuestion q, int _) => q.answer + 50;

final _code = RegExp(r'[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{3}');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('The running count', () {
    test('is every face-up card since the shuffle, and nothing else', () {
      for (final config in _allTables()) {
        final s = HiLoTrainingSession(config,
            rng: Random(config.decks * 10 + config.players));
        var expected = 0;
        var swept = 0;
        var shuffles = 0;
        for (var i = 0; i < 6000; i++) {
          final onTableBefore = _visibleOnTable(s);
          final e = s.advance();
          switch (e.kind) {
            case HiLoEventKind.card:
              expect(e.card!.faceUp, isTrue);
              expected += hiLoTag(e.card!);
            case HiLoEventKind.holeCard:
              expect(e.card!.faceUp, isFalse, reason: 'dealt face down');
            case HiLoEventKind.reveal:
              expected += hiLoTag(e.card!);
            case HiLoEventKind.sweep:
              swept += onTableBefore;
            case HiLoEventKind.shuffle:
              expected = 0;
              swept = 0;
              shuffles++;
            case HiLoEventKind.roundOver:
              break;
          }
          expect(s.runningCount, expected);
          expect(s.runningCount, swept + _visibleOnTable(s),
              reason: 'table plus discard tray');
        }
        expect(shuffles, greaterThan(0), reason: 'sanity: reached a new shoe');
        expect(s.shoeNumber, shuffles + 1,
            reason: 'every new shoe was a between-rounds shuffle');
      }
    });

    test('leaves the hole card out until it is turned over', () {
      final s = HiLoTrainingSession(
          const HiLoTrainingConfig(players: 2, questions: 999),
          rng: Random(4));
      var checked = 0;
      for (var i = 0; i < 4000; i++) {
        final before = s.runningCount;
        final e = s.advance();
        if (e.kind == HiLoEventKind.holeCard) {
          expect(s.runningCount, before);
          expect(s.dealer.cards[1].faceUp, isFalse);
          final q = s.ask();
          expect(q.holeCardDown, isNotNull);
          expect(q.answer, before);
          s.answer(q.answer);
          if (hiLoTag(e.card!) != 0) checked++;
        }
        if (e.kind == HiLoEventKind.reveal) {
          expect(s.runningCount, before + hiLoTag(e.card!));
          expect(s.dealer.hasFaceDown, isFalse);
        }
      }
      expect(checked, greaterThan(20), reason: 'sanity: non-neutral holes');
    });
  });

  group('The deal', () {
    test('goes round from first base twice, the dealer\'s second card down',
        () {
      for (final players in HiLoTrainingConfig.playerOptions) {
        final s = HiLoTrainingSession(
            HiLoTrainingConfig(players: players, questions: 999),
            rng: Random(players));
        for (var round = 0; round < 40; round++) {
          var e = s.advance();
          while (e.kind == HiLoEventKind.shuffle) {
            e = s.advance();
          }
          final opening = [e];
          for (var i = 1; i < 2 * players + 2; i++) {
            opening.add(s.advance());
          }
          final seatsOrder = [for (var i = 0; i < players; i++) i];
          expect(opening.take(players).map((e) => e.seat), seatsOrder);
          expect(opening[players].seat, isNull, reason: 'dealer up card');
          expect(opening[players].kind, HiLoEventKind.card);
          expect(opening.skip(players + 1).take(players).map((e) => e.seat),
              seatsOrder);
          expect(opening.last.kind, HiLoEventKind.holeCard);
          while (s.advance().kind != HiLoEventKind.sweep) {}
        }
      }
    });

    test('seats play the chart and the dealer draws to 17, hitting soft 17',
        () {
      var dealerNaturals = 0;
      var noDraws = 0;
      var doubles = 0;
      for (final config in _allTables()) {
        final s = HiLoTrainingSession(config, rng: Random(config.players));
        for (var i = 0; i < 5000; i++) {
          final e = s.advance();
          if (e.kind != HiLoEventKind.roundOver) continue;
          final dealer = s.dealer;
          expect(dealer.hasFaceDown, isFalse, reason: 'hole card turned');
          expect(s.roundFinished, isTrue);

          final dealerNatural = dealer.cards.length == 2 && dealer.value == 21;
          final anyLive = s.seats.any((h) => !h.isBust && !h.isNatural);
          if (dealerNatural) {
            dealerNaturals++;
            for (final h in s.seats) {
              expect(h.cards, hasLength(2), reason: 'nobody plays a natural');
            }
          } else if (!anyLive) {
            noDraws++;
            expect(dealer.cards, hasLength(2),
                reason: 'no card drawn when nobody is waiting on the dealer');
          } else {
            expect(dealer.value, greaterThanOrEqualTo(17));
            expect(dealer.value == 17 && dealer.isSoft, isFalse,
                reason: 'hits soft 17');
            final before = HandModel(
                cards: dealer.cards.sublist(0, dealer.cards.length - 1));
            if (dealer.cards.length > 2) {
              expect(before.value < 17 || (before.value == 17 && before.isSoft),
                  isTrue,
                  reason: 'drew only while it had to');
            }
          }

          if (dealerNatural) continue;
          final up = dealer.cards.first;
          for (final h in s.seats) {
            if (h.isNatural || h.isBust) continue;
            if (h.isDoubled) {
              doubles++;
              expect(h.cards, hasLength(3), reason: 'one card on a double');
              continue;
            }
            if (h.value == 21) continue;
            expect(
              BasicStrategy.best(
                hand: h,
                dealerUp: up,
                canDouble: h.cards.length == 2,
                canSplit: false,
                rules: HiLoTrainingSession.rules,
                decks: config.decks,
              ),
              StrategyMove.stand,
              reason: 'a seat stops only where the chart stands: $h v $up',
            );
          }
        }
      }
      expect(dealerNaturals, greaterThan(0));
      expect(noDraws, greaterThan(0));
      expect(doubles, greaterThan(0));
    });

    test('the shoe is changed only between rounds, before it runs short', () {
      for (final config in _allTables()) {
        final s = HiLoTrainingSession(config, rng: Random(99 + config.decks));
        var previous = HiLoEventKind.sweep;
        for (var i = 0; i < 6000; i++) {
          final leftBefore = s.cardsLeft;
          final e = s.advance();
          if (e.kind == HiLoEventKind.shuffle) {
            expect(previous, HiLoEventKind.sweep);
            expect(leftBefore, lessThan(s.reshuffleAt));
            expect(s.cardsLeft, s.totalCards);
            expect(s.runningCount, 0);
            expect(s.discardFill, 0);
          }
          previous = e.kind;
        }
      }
    });

    test('a new player count waits for the next round', () {
      final s = HiLoTrainingSession(
          const HiLoTrainingConfig(players: 2, questions: 999),
          rng: Random(3));
      s.advance(); // the first card of round 1
      s.setPlayers(5);
      expect(s.seats, hasLength(2),
          reason: 'a round in progress keeps its seats');
      expect(s.reshuffleAt, max(6 * 52 ~/ 4, 8 * 6),
          reason: 'the shoe plans for the full table');
      while (s.advance().kind != HiLoEventKind.sweep) {}
      final first = s.advance();
      expect(s.players, 5);
      expect(s.seats, hasLength(5));
      expect(first.seat, 0);
      s.setPlayers(99);
      while (s.advance().kind != HiLoEventKind.sweep) {}
      s.advance();
      expect(s.players, HiLoTrainingConfig.playerOptions.last,
          reason: 'never more seats than the table has');
    });

    test('the same seed deals the same shoe', () {
      List<String> run() {
        final s = HiLoTrainingSession(const HiLoTrainingConfig(),
            rng: SeededRandom(12));
        return [for (var i = 0; i < 300; i++) '${s.advance().card}'];
      }

      expect(run(), run());
    });
  });

  group('The seeded shuffle', () {
    test('is mulberry32, value for value', () {
      // Checked against the reference JavaScript implementation.
      final r = SeededRandom(12345);
      expect([for (var i = 0; i < 5; i++) r.nextUint32()],
          [4207900869, 1317490944, 2079646450, 3513001552, 2187978186]);
      final z = SeededRandom(0);
      expect([for (var i = 0; i < 3; i++) z.nextUint32()],
          [1144304738, 1416247, 958946056]);
    });

    test('draws evenly and within range', () {
      final r = SeededRandom(7);
      final counts = List.filled(13, 0);
      for (var i = 0; i < 13000; i++) {
        counts[r.nextInt(13)]++;
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(850, 1150));
      }
      for (var i = 0; i < 1000; i++) {
        expect(r.nextDouble(), inInclusiveRange(0.0, 1.0));
      }
      expect(() => r.nextInt(0), throwsRangeError);
    });
  });

  group('Questions', () {
    test('come at a random card inside the chosen range', () {
      for (final f in HiLoQuizFrequency.values) {
        final s = HiLoTrainingSession(
            HiLoTrainingConfig(frequency: f, questions: 60),
            rng: Random(f.index));
        final gaps = <int>[];
        var lastAt = 0;
        while (!s.isFinished) {
          if (s.quizDue) {
            gaps.add(s.cardsSeen - lastAt);
            lastAt = s.cardsSeen;
            s.answer(s.ask().answer);
          } else {
            s.advance();
          }
        }
        expect(gaps, hasLength(60));
        for (final g in gaps) {
          expect(g, inInclusiveRange(f.minCards, f.maxCards));
        }
        expect(gaps.toSet().length, greaterThan(3),
            reason: 'not the same card every time');
        expect(s.quizDue, isFalse, reason: 'no questions after the last');
      }
    });

    test('keep score and streaks', () {
      final s = HiLoTrainingSession(
          const HiLoTrainingConfig(
              questions: 5, frequency: HiLoQuizFrequency.often),
          rng: Random(2));
      expect(() => s.answer(0), throwsStateError);
      expect(s.close, throwsStateError);
      for (final r in [true, true, false, true, true]) {
        while (!s.quizDue) {
          s.advance();
        }
        final q = s.ask();
        expect(s.answer(r ? q.answer : q.answer + 50).correct, r);
      }
      expect(s.correct, 4);
      expect(s.bestStreak, 2);
      expect(s.streak, 2);
      expect(s.isFinished, isTrue);
      expect(s.questionsClosed, 5);
      expect(s.answers.last.slip, HiLoSlip.none);
      expect(s.answers[2].slip, HiLoSlip.drift);
    });

    test('name the slip behind a wrong answer', () {
      final five = _c(Rank.five);
      final king = _c(Rank.king);
      final eight = _c(Rank.eight);
      HiLoSlip d(int answer, int given, {CardModel? hole, CardModel? last}) =>
          HiLoTrainingSession.diagnose(
              answer: answer, given: given, holeCardDown: hole, lastCard: last);

      expect(d(3, 3, hole: five), HiLoSlip.none);
      expect(d(3, 4, hole: five), HiLoSlip.countedHoleCard);
      expect(d(3, 2, hole: king), HiLoSlip.countedHoleCard);
      expect(d(3, 4, hole: eight), HiLoSlip.drift, reason: 'a 7–9 is 0');
      expect(d(3, 2, last: five), HiLoSlip.missedLastCard);
      expect(d(3, 4, last: king), HiLoSlip.missedLastCard);
      expect(d(4, -4), HiLoSlip.flippedSign);
      expect(d(0, 0), HiLoSlip.none);
      expect(d(4, 9), HiLoSlip.drift);
      expect(d(3, 4, hole: five, last: king), HiLoSlip.countedHoleCard);
      const q = HiLoQuestion(answer: 2, round: 1);
      expect(const HiLoAnswer(question: q, given: null).slip, HiLoSlip.timeUp);
      expect(const HiLoAnswer(question: q, given: null).correct, isFalse);
    });
  });

  group('Scoring', () {
    test('the combo climbs at 3, 6 and 10 in a row', () {
      expect([for (var s = 0; s <= 11; s++) HiLoScoring.comboFor(s)],
          [1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4]);
      expect(HiLoScoring.toNextCombo(0), 3);
      expect(HiLoScoring.toNextCombo(4), 2);
      expect(HiLoScoring.toNextCombo(9), 1);
      expect(HiLoScoring.toNextCombo(10), isNull);
    });

    test('speed pays in full inside 2 s and nothing after 10 s', () {
      expect(HiLoScoring.speedBonus(Duration.zero), 100);
      expect(HiLoScoring.speedBonus(const Duration(seconds: 2)), 100);
      expect(HiLoScoring.speedBonus(const Duration(seconds: 6)), 50);
      expect(HiLoScoring.speedBonus(const Duration(seconds: 10)), 0);
      expect(HiLoScoring.speedBonus(const Duration(seconds: 30)), 0);
      var last = 101;
      for (var ms = 0; ms <= 12000; ms += 250) {
        final b = HiLoScoring.speedBonus(Duration(milliseconds: ms));
        expect(b, lessThanOrEqualTo(last), reason: 'never more for slower');
        last = b;
      }
    });

    test('a wrong answer scores nothing', () {
      expect(
          HiLoScoring.score(correct: false, took: Duration.zero, streak: 0)
              .total,
          0);
      expect(
          HiLoScoring.score(
                  correct: true, took: const Duration(seconds: 6), streak: 6)
              .total,
          (100 + 50) * 3);
    });

    test('Survival speeds up and fills the table', () {
      expect(SurvivalLevel.levelFor(0), 1);
      expect(SurvivalLevel.levelFor(4), 1);
      expect(SurvivalLevel.levelFor(5), 2);
      expect(SurvivalLevel.levelFor(30), 7);
      expect([for (var l = 1; l <= 8; l++) SurvivalLevel.playersFor(l)],
          [2, 2, 3, 3, 4, 4, 5, 5]);
      var last = SurvivalLevel.paceFor(1);
      expect(last, const Duration(milliseconds: 1200));
      for (var l = 2; l <= 30; l++) {
        final pace = SurvivalLevel.paceFor(l);
        expect(pace, lessThanOrEqualTo(last));
        expect(pace.inMilliseconds, greaterThanOrEqualTo(420));
        last = pace;
      }
    });
  });

  group('Games', () {
    test('practice: points add up, combos included', () {
      final game = _playOut(
        HiLoGame(HiLoGameSpec.practice(const HiLoTrainingConfig(questions: 10),
            seed: 5)),
        _right,
        took: const Duration(seconds: 1),
      );
      final p = game.players.first;
      expect(p.correct, 10);
      expect(p.bestStreak, 10);
      expect(p.score, p.answers.fold(0, (s, a) => s + a.points.total));
      // 200 a count at x1, x1, x2, x2, x2, x3, x3, x3, x3, x4.
      expect(p.score, 200 * (1 + 1 + 2 + 2 + 2 + 3 + 3 + 3 + 3 + 4));
      expect(game.questionNumber, 10);
    });

    test('a clock that runs out is a miss with no points', () {
      final game = _playOut(HiLoGame(HiLoGameSpec.daily(3)), (q, _) => null);
      final p = game.players.first;
      expect(p.answered, HiLoDaily.questions);
      expect(p.score, 0);
      expect(p.answers.every((a) => a.slip == HiLoSlip.timeUp), isTrue);
    });

    test('survival ends on the third miss, and levels up every 5', () {
      var calls = 0;
      final game = _playOut(
        HiLoGame(HiLoGameSpec.survival(seed: 9)),
        (q, _) => calls++ < 12 ? q.answer : q.answer + 50,
      );
      expect(game.lives, 0);
      expect(game.players.first.correct, 12);
      expect(game.players.first.answered, 15);
      expect(game.level, 3);
      expect(game.pace, SurvivalLevel.paceFor(3));
      expect(game.session.players, SurvivalLevel.playersFor(3));
      expect(game.questionCount, isNull);
    });

    test('survival reports each level and each lost life', () {
      final game = HiLoGame(HiLoGameSpec.survival(seed: 2));
      final levels = <int>[];
      var lost = 0;
      var n = 0;
      while (!game.isOver) {
        if (game.quizDue) {
          final q = game.ask();
          game.submit(n++ < 10 ? q.answer : null);
          final r = game.lastResolution!;
          if (r.newLevel != null) levels.add(r.newLevel!);
          if (r.lifeLost) lost++;
        } else {
          game.session.advance();
        }
      }
      expect(levels, [2, 3]);
      expect(lost, SurvivalLevel.lives);
    });

    test('duel: both answer, the first answer alternates, a winner', () {
      final game = HiLoGame(HiLoGameSpec.duel(
        names: ['Ann', 'Bo'],
        questions: 6,
        pace: HiLoPace.steady,
        seed: 4,
      ));
      final firsts = <int>[];
      while (!game.isOver) {
        if (!game.quizDue) {
          game.session.advance();
          continue;
        }
        final q = game.ask();
        firsts.add(game.turn);
        game.submit(game.turn == 0 ? q.answer : q.answer + 1);
        expect(game.midQuestion, isTrue, reason: 'waiting on the other');
        expect(game.question, isNotNull);
        game.submit(game.turn == 0 ? q.answer : q.answer + 1);
        expect(game.midQuestion, isFalse);
        expect(game.lastResolution!.answers, hasLength(2));
      }
      expect(firsts, [0, 1, 0, 1, 0, 1]);
      expect(game.players[0].correct, 6);
      expect(game.players[1].correct, 0);
      expect(game.winner, 0);
    });

    test('duel: equal scores are a draw', () {
      final game = _playOut(
        HiLoGame(HiLoGameSpec.duel(
            names: ['A', 'B'], questions: 5, pace: HiLoPace.brisk, seed: 1)),
        _right,
      );
      expect(game.players[0].score, game.players[1].score);
      expect(game.winner, isNull);
    });

    test('quitting ends the game where it stands', () {
      final game = HiLoGame(HiLoGameSpec.survival(seed: 3));
      expect(game.isOver, isFalse);
      game.quit();
      expect(game.isOver, isTrue);
      expect(game.quizDue, isFalse);
    });

    test('play again: a fresh shoe, or the same one where it must be', () {
      final daily = HiLoGameSpec.daily(8);
      expect(daily.again().seed, daily.seed);
      expect(daily.again().ranked, isFalse);
      final challenge = HiLoGameSpec.fromChallenge(const HiLoChallenge(
        seed: 77,
        config: HiLoTrainingConfig(),
        survival: false,
        score: 900,
      ));
      final replay = challenge.again();
      expect(replay.seed, challenge.seed, reason: 'the same shoe');
      expect(replay.targetScore, 900);
      expect(replay.mode, HiLoMode.challenge);
      expect(challenge.ranked, isTrue, reason: 'the first try counts');
      expect(replay.ranked, isFalse, reason: 'a replay is of a seen shoe');
      final duel = HiLoGameSpec.duel(
          names: ['A', 'B'], questions: 10, pace: HiLoPace.casino, seed: 1);
      final rematch = duel.again();
      expect(rematch.playerNames, ['A', 'B']);
      expect(rematch.config.questions, 10);
      expect(rematch.config.pace, HiLoPace.casino);
      final practice =
          HiLoGameSpec.practice(const HiLoTrainingConfig(players: 5), seed: 1);
      expect(practice.again().config.players, 5);
      final survivalChallenge = HiLoGameSpec.survival(seed: 5, targetScore: 10);
      expect(survivalChallenge.again().seed, 5);
      expect(survivalChallenge.again().ranked, isFalse);
      expect(HiLoGameSpec.survival().again().ranked, isTrue,
          reason: 'a fresh survival shoe is a fresh game');
    });
  });

  group('The Daily Challenge', () {
    test('is numbered from 2026-09-29 and rolls over at local midnight', () {
      expect(HiLoDaily.numberFor(DateTime(2026, 9, 29, 0, 1)), 1);
      expect(HiLoDaily.numberFor(DateTime(2026, 9, 29, 23, 59)), 1);
      expect(HiLoDaily.numberFor(DateTime(2026, 9, 30)), 2);
      expect(HiLoDaily.numberFor(DateTime(2027, 3, 29, 12)), 182,
          reason: 'across a daylight-saving change');
      expect(HiLoDaily.untilNext(DateTime(2026, 9, 29, 22, 30)),
          const Duration(hours: 1, minutes: 30));
    });

    test('deals everyone the same shoe, a different one each day', () {
      final seeds = {for (var d = 1; d <= 60; d++) HiLoDaily.seedFor(d)};
      expect(seeds.length, 60);
      for (final s in seeds) {
        expect(s, inInclusiveRange(0, (1 << HiLoGameSpec.seedBits) - 1));
      }
      List<int> questions(int day) {
        final g = _playOut(HiLoGame(HiLoGameSpec.daily(day)), _right);
        return [for (final a in g.players.first.answers) a.question.answer];
      }

      expect(questions(5), questions(5));
      expect(HiLoDaily.configFor(5).players, HiLoDaily.configFor(12).players,
          reason: 'the table repeats weekly');
      final week = [for (var d = 0; d < 7; d++) HiLoDaily.configFor(d)];
      expect(week.map((c) => c.pace).toSet(), hasLength(3),
          reason: 'steady, brisk and casino days');
    });
  });

  group('Challenge codes', () {
    test('carry the shoe, the table and the score', () {
      final r = Random(1);
      for (var i = 0; i < 500; i++) {
        final c = HiLoChallenge(
          seed: r.nextInt(1 << HiLoGameSpec.seedBits),
          config: HiLoTrainingConfig(
            players: 1 + r.nextInt(5),
            decks: HiLoTrainingConfig.deckOptions[r.nextInt(3)],
            pace: HiLoPace.values[r.nextInt(4)],
            frequency: HiLoQuizFrequency.values[r.nextInt(3)],
            questions: HiLoTrainingConfig.questionOptions[r.nextInt(3)],
          ),
          survival: r.nextBool(),
          score: r.nextInt(HiLoChallenge.maxScore + 1),
        );
        final code = c.encode();
        expect(code, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{3}$')));
        expect(code, isNot(matches(RegExp('[ILOU]'))),
            reason: 'no letters that read as digits');
        final back = HiLoChallenge.decode(code)!;
        expect(back.seed, c.seed);
        expect(back.score, c.score);
        expect(back.survival, c.survival);
        expect(back.config.players, c.config.players);
        expect(back.config.decks, c.config.decks);
        expect(back.config.pace, c.config.pace);
        expect(back.config.frequency, c.config.frequency);
        expect(back.config.questions, c.config.questions);
      }
    });

    test('forgive case, dashes, spaces and look-alike letters', () {
      final code = const HiLoChallenge(
        seed: 123456,
        config: HiLoTrainingConfig(players: 4),
        survival: false,
        score: 2450,
      ).encode();
      expect(HiLoChallenge.decode(code.toLowerCase())?.score, 2450);
      expect(
          HiLoChallenge.decode(' ${code.replaceAll('-', ' ')} ')?.score, 2450);
      expect(HiLoChallenge.decode(code.replaceAll('-', ''))?.score, 2450);
      final lookAlikes = code.replaceAll('0', 'O').replaceAll('1', 'I');
      expect(HiLoChallenge.decode(lookAlikes)?.score, 2450);
    });

    test('refuse every single mistyped character, and nonsense', () {
      const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
      final r = Random(5);
      var typos = 0;
      var swaps = 0;
      var swapsAccepted = 0;
      for (var i = 0; i < 80; i++) {
        final code = HiLoChallenge(
          seed: r.nextInt(1 << 20),
          config: const HiLoTrainingConfig(),
          survival: false,
          score: r.nextInt(9000),
        ).encode().replaceAll('-', '');
        for (var pos = 0; pos < code.length; pos++) {
          for (final ch in alphabet.split('')) {
            if (ch == code[pos]) continue;
            typos++;
            expect(HiLoChallenge.decode(code.replaceRange(pos, pos + 1, ch)),
                isNull,
                reason: '$code with $ch at $pos');
          }
          if (pos + 1 < code.length && code[pos] != code[pos + 1]) {
            swaps++;
            final swapped = code.substring(0, pos) +
                code[pos + 1] +
                code[pos] +
                code.substring(pos + 2);
            if (HiLoChallenge.decode(swapped) != null) swapsAccepted++;
          }
        }
      }
      expect(typos, greaterThan(20000));
      expect(swapsAccepted / swaps, lessThan(0.03),
          reason: 'swapped neighbours are caught almost always');
      expect(HiLoChallenge.decode(''), isNull);
      expect(HiLoChallenge.decode('HELLO-WORLD'), isNull);
      expect(HiLoChallenge.decode('ZZZZ-ZZZZ-ZZZ'), isNull);
      expect(HiLoChallenge.decode('0000-0000-0000'), isNull);
    });

    test('clamp a score too big to carry', () {
      const c = HiLoChallenge(
        seed: 1,
        config: HiLoTrainingConfig(),
        survival: true,
        score: 999999,
      );
      expect(HiLoChallenge.decode(c.encode())!.score, HiLoChallenge.maxScore);
    });

    test('deal the friend the very shoe the challenger played', () {
      final original = _playOut(
        HiLoGame(HiLoGameSpec.practice(
            const HiLoTrainingConfig(players: 4, pace: HiLoPace.brisk),
            seed: 4242)),
        _right,
      );
      final code = original.toChallenge().encode();
      final spec = HiLoGameSpec.fromChallenge(HiLoChallenge.decode(code)!);
      expect(spec.mode, HiLoMode.challenge);
      expect(spec.targetScore, original.players.first.score);
      expect(spec.answerLimit, HiLoGameSpec.rankedAnswerLimit);
      final friend = _playOut(HiLoGame(spec), _right);
      expect(
        [for (final a in friend.players.first.answers) a.question.answer],
        [for (final a in original.players.first.answers) a.question.answer],
      );
      expect(friend.challengeWon, isFalse, reason: 'a tie does not beat it');

      final survival = HiLoGameSpec.fromChallenge(HiLoChallenge.decode(
          HiLoGame(HiLoGameSpec.survival(seed: 8)).toChallenge().encode())!);
      expect(survival.isSurvival, isTrue);
      expect(survival.seed, 8);
      expect(survival.targetScore, 0);
    });
  });

  group('The profile', () {
    HiLoGame practice({
      int questions = 10,
      int? Function(HiLoQuestion, int)? f,
      HiLoPace pace = HiLoPace.steady,
      int players = 3,
    }) =>
        _playOut(
          HiLoGame(HiLoGameSpec.practice(
              HiLoTrainingConfig(
                  questions: questions, pace: pace, players: players),
              seed: 11)),
          f ?? _right,
        );

    test('adds up practice games, bests and XP', () {
      final first = applyGame(const HiLoProfile(), practice(f: _wrong));
      expect(first.after.games, 1);
      expect(first.after.questions, 10);
      expect(first.after.correct, 0);
      expect(first.newBest, isFalse, reason: 'zero is not a best');
      expect(first.xpGained, 0);

      final game = practice();
      final second = applyGame(first.after, game);
      expect(second.after.correct, 10);
      expect(second.after.practiceBest, game.players.first.score);
      expect(second.newBest, isTrue);
      expect(second.xpGained, game.players.first.score ~/ 10);
      expect(second.after.xp, second.xpGained);
      expect(second.after.accuracy, 50);

      final third = applyGame(second.after, practice(f: _wrong));
      expect(third.newBest, isFalse);
      expect(third.after.practiceBest, game.players.first.score);
    });

    test('keeps the five best survival runs', () {
      var p = const HiLoProfile();
      final scores = <int>[];
      for (var seed = 0; seed < 8; seed++) {
        var n = 0;
        final g = _playOut(HiLoGame(HiLoGameSpec.survival(seed: seed)),
            (q, _) => n++ < seed * 2 ? q.answer : null);
        scores.add(g.players.first.score);
        p = applyGame(p, g).after;
      }
      final best = [...scores]..sort((a, b) => b.compareTo(a));
      expect(p.survivalTop, best.take(5).toList());
      expect(p.survivalBest, best.first);
      expect(p.survivalBestLevel, 3);
    });

    test('the Daily: one ranked try, a streak for consecutive days', () {
      var p = startDaily(const HiLoProfile(), 10);
      expect(p.dailyScores[10], 0, reason: 'counts from the first card');
      expect(p.dailyStreak, 1);
      expect(startDaily(p, 10).dailyStreak, 1, reason: 'idempotent');
      final day10 =
          applyGame(p, _playOut(HiLoGame(HiLoGameSpec.daily(10)), _right));
      p = day10.after;
      expect(day10.ranked, isTrue);
      expect(p.dailyScores[10], greaterThan(0));
      expect(day10.xpGained, p.dailyScores[10]! ~/ 10 + 50);
      expect(day10.newBest, isTrue);
      expect(p.dailyStreak, 1, reason: 'starting and finishing is one day');

      final replay = applyGame(
          p, _playOut(HiLoGame(HiLoGameSpec.daily(10, ranked: false)), _wrong));
      expect(replay.ranked, isFalse);
      expect(replay.xpGained, 0);
      expect(replay.after.dailyScores[10], p.dailyScores[10]);

      for (final day in [11, 12]) {
        p = applyGame(p, _playOut(HiLoGame(HiLoGameSpec.daily(day)), _wrong))
            .after;
      }
      expect(p.dailyStreak, 3);
      expect(p.achievements, contains(HiLoAchievement.regular));
      expect(p.dailyStreakOn(13), 3, reason: 'still alive the next day');
      expect(p.dailyStreakOn(14), 0, reason: 'lapsed after a missed day');
      p = applyGame(p, _playOut(HiLoGame(HiLoGameSpec.daily(14)), _right))
          .after;
      expect(p.dailyStreak, 1);
      expect(p.dailyLastPlayed, 14);
    });

    test('duels count as duels, not toward accuracy', () {
      final duel = _playOut(
        HiLoGame(HiLoGameSpec.duel(
            names: ['A', 'B'], questions: 5, pace: HiLoPace.steady, seed: 2)),
        _right,
      );
      final r = applyGame(const HiLoProfile(), duel);
      expect(r.after.duels, 1);
      expect(r.after.questions, 0);
      expect(r.xpGained, 30);
      expect(r.unlocked, [HiLoAchievement.duelist]);

      final quitter = HiLoGame(HiLoGameSpec.duel(
          names: ['A', 'B'], questions: 5, pace: HiLoPace.steady, seed: 2));
      quitter.quit();
      expect(applyGame(const HiLoProfile(), quitter).unlocked, isEmpty,
          reason: 'a duel has to be finished');
    });

    test('a beaten challenge is a win and an achievement', () {
      final spec = HiLoGameSpec.fromChallenge(const HiLoChallenge(
        seed: 99,
        config: HiLoTrainingConfig(questions: 5),
        survival: false,
        score: 100,
      ));
      final r =
          applyGame(const HiLoProfile(), _playOut(HiLoGame(spec), _right));
      expect(r.after.challengesWon, 1);
      expect(r.unlocked, contains(HiLoAchievement.challengeAccepted));
    });

    test('achievements unlock once, when earned', () {
      final perfect = applyGame(
          const HiLoProfile(), practice(pace: HiLoPace.casino, players: 5));
      expect(
          perfect.unlocked,
          containsAll([
            HiLoAchievement.firstCount,
            HiLoAchievement.quickDraw,
            HiLoAchievement.perfectTen,
            HiLoAchievement.casinoSpeed,
            HiLoAchievement.fullHouse,
          ]));
      expect(perfect.unlocked, isNot(contains(HiLoAchievement.centurion)));
      expect(perfect.unlocked, isNot(contains(HiLoAchievement.unshakeable)));
      final again = applyGame(perfect.after, practice(pace: HiLoPace.casino));
      expect(again.unlocked, isEmpty, reason: 'each unlocks only once');

      var p = perfect.after;
      for (var i = 0; i < 9; i++) {
        p = applyGame(p, practice()).after;
      }
      expect(p.correct, 100);
      expect(p.achievements, contains(HiLoAchievement.centurion));
      expect(p.achievements, isNot(contains(HiLoAchievement.unshakeable)),
          reason: 'a streak lives within one game');
    });

    test('a slow right answer is not a Quick Draw', () {
      final slow = _playOut(
        HiLoGame(HiLoGameSpec.practice(const HiLoTrainingConfig(questions: 5),
            seed: 3)),
        _right,
        took: const Duration(seconds: 3),
      );
      expect(applyGame(const HiLoProfile(), slow).unlocked,
          isNot(contains(HiLoAchievement.quickDraw)));
    });

    test('a long survival run earns Survivor and Pit Boss', () {
      var n = 0;
      final g = _playOut(HiLoGame(HiLoGameSpec.survival(seed: 1)),
          (q, _) => n++ < 32 ? q.answer : null);
      final r = applyGame(const HiLoProfile(), g);
      expect(g.level, 7);
      expect(
          r.unlocked,
          containsAll([
            HiLoAchievement.survivor,
            HiLoAchievement.pitBoss,
            HiLoAchievement.unshakeable,
          ]));
      expect(r.newBest, isTrue);
    });

    test('Poker Face counts right answers while the hole card is down', () {
      var p = const HiLoProfile();
      var reads = 0;
      for (var seed = 0; seed < 40 && reads < 10; seed++) {
        final g = _playOut(
            HiLoGame(HiLoGameSpec.practice(
                const HiLoTrainingConfig(questions: 20),
                seed: seed)),
            _right);
        reads += g.players.first.answers.where((a) {
          final h = a.question.holeCardDown;
          return h != null && hiLoTag(h) != 0;
        }).length;
        p = applyGame(p, g).after;
      }
      expect(reads, greaterThanOrEqualTo(10), reason: 'sanity');
      expect(p.holeCardReads, reads);
      expect(p.achievements, contains(HiLoAchievement.pokerFace));
    });

    test('ranks follow XP', () {
      expect(HiLoRank.forXp(0), HiLoRank.rookie);
      expect(HiLoRank.forXp(299), HiLoRank.rookie);
      expect(HiLoRank.forXp(300), HiLoRank.cardWatcher);
      expect(HiLoRank.forXp(25000), HiLoRank.legend);
      expect(HiLoRank.legend.next, isNull);
      expect(HiLoRank.rookie.progress(150), 0.5);
      expect(HiLoRank.legend.progress(99999), 1);
      final r = applyGame(const HiLoProfile(xp: 290), practice());
      expect(r.rankUp, HiLoRank.cardWatcher);
      expect(applyGame(r.after, practice(f: _wrong)).rankUp, isNull);
    });

    test('survives a save and a bad save', () async {
      final r = applyGame(
          const HiLoProfile(), practice(pace: HiLoPace.casino, players: 5));
      await HiLoTrainingProgress.saveProfile(r.after);
      final back = await HiLoTrainingProgress.loadProfile();
      expect(back.toJson(), r.after.toJson());

      SharedPreferences.setMockInitialValues(
          {'hilo_training_profile': '{not json'});
      expect((await HiLoTrainingProgress.loadProfile()).xp, 0);

      final partial = HiLoProfile.fromJson({
        'xp': 'lots',
        'correct': 7,
        'dailyScores': {'3': 900, 'x': 1, '4': 'no'},
        'achievements': ['perfectTen', 'retired'],
        'survivalTop': [500, 'x', 300],
      });
      expect(partial.xp, 0);
      expect(partial.correct, 7);
      expect(partial.dailyScores, {3: 900});
      expect(partial.achievements, {HiLoAchievement.perfectTen});
      expect(partial.survivalTop, [500, 300]);
    });

    test('recordGame saves what it reports', () async {
      final reward = await HiLoTrainingProgress.recordGame(practice());
      expect((await HiLoTrainingProgress.loadProfile()).xp, reward.after.xp);
      await HiLoTrainingProgress.startDailyAttempt(20);
      expect(
          (await HiLoTrainingProgress.loadProfile()).playedDaily(20), isTrue);
    });

    test('settings and duel names come back as they were left', () async {
      const chosen = HiLoTrainingConfig(
        decks: 2,
        players: 5,
        pace: HiLoPace.casino,
        frequency: HiLoQuizFrequency.rarely,
        questions: 20,
      );
      await HiLoTrainingProgress.saveConfig(chosen);
      final back = await HiLoTrainingProgress.loadConfig();
      expect(back.decks, 2);
      expect(back.players, 5);
      expect(back.pace, HiLoPace.casino);
      expect(back.frequency, HiLoQuizFrequency.rarely);
      expect(back.questions, 20);
      await HiLoTrainingProgress.saveDuelNames(['Ann', 'Bo']);
      expect(await HiLoTrainingProgress.loadDuelNames(), ['Ann', 'Bo']);

      SharedPreferences.setMockInitialValues({
        'hilo_training_decks': 1,
        'hilo_training_players': 9,
        'hilo_training_pace': 'warp',
      });
      final fallback = await HiLoTrainingProgress.loadConfig();
      const d = HiLoTrainingConfig();
      expect(fallback.decks, d.decks);
      expect(fallback.players, d.players);
      expect(fallback.pace, d.pace);
      expect(await HiLoTrainingProgress.loadDuelNames(), ['', '']);
    });
  });

  group('What it says', () {
    test('numbers', () {
      expect(signedCount(4), '+4');
      expect(signedCount(-4), '−4');
      expect(signedCount(0), '0');
      expect(points(0), '0');
      expect(points(999), '999');
      expect(points(1000), '1,000');
      expect(points(1234567), '1,234,567');
      expect(countdown(const Duration(hours: 5, minutes: 12)), '5h 12m');
      expect(countdown(const Duration(seconds: 20)), '1m');
      expect(tableLabel(const HiLoTrainingConfig(players: 1)),
          '1 player · 6 decks · Steady');
    });

    test('advice fits the slip', () {
      HiLoAnswer a(int? given, {CardModel? hole, CardModel? last}) =>
          HiLoAnswer(
            question: HiLoQuestion(
                answer: 3, round: 1, holeCardDown: hole, lastCard: last),
            given: given,
          );
      expect(slipAdvice(a(4, hole: _c(Rank.two))), contains('face-down'));
      expect(slipAdvice(a(3, hole: _c(Rank.two))), contains('face-down'));
      expect(
          slipAdvice(a(3, hole: _c(Rank.eight))), isNot(contains('face-down')),
          reason: 'a neutral hole card proves nothing');
      expect(slipAdvice(a(2, last: _c(Rank.four))), contains('4'));
      expect(slipAdvice(a(-3)), contains('wrong sign'));
      expect(slipAdvice(a(9)), contains('Off by 6'));
      expect(slipAdvice(a(null)), contains('Time'));
      expect(comboNote(1), '2 more in a row for x2.');
      expect(comboNote(10), contains('top multiplier'));
    });

    test('the coaching tip follows the game', () {
      List<HiLoAnswer> play(int? Function(int) f) => _playOut(
          HiLoGame(HiLoGameSpec.practice(const HiLoTrainingConfig(questions: 5),
              seed: 8)),
          (q, _) => f(q.answer)).players.first.answers;

      const c = HiLoTrainingConfig();
      expect(coachingTip(play((x) => x), c), contains('Brisk'));
      expect(coachingTip(play((x) => x), c.copyWith(pace: HiLoPace.casino)),
          contains('Add players'));
      expect(
          coachingTip(
              play((x) => x), c.copyWith(pace: HiLoPace.casino, players: 5)),
          contains('game speed'));
      expect(coachingTip(play((x) => x + 40), c), contains('slower'));
      expect(coachingTip(play((x) => null), c), contains('clock'));
      expect(coachingTip(const [], c), contains('Deal again'));
      expect(coachingTip(play((x) => x), c, survival: true),
          contains('Run it to the end'),
          reason: 'Survival has no faster pace to suggest');
      final drift = coachingTip(play((x) => x + 40), c, survival: true);
      expect(drift, contains('Practice'));
      expect(drift, isNot(contains('fewer players')));
    });

    test('the share text carries a code for the same shoe', () {
      final g = _playOut(HiLoGame(HiLoGameSpec.daily(4)), _right);
      final text = shareText(g);
      expect(text, startsWith('Hi-Lo Daily #4 — '));
      expect(text, contains('🟩🟩🟩🟩🟩🟩🟩🟩🟩🟩'));
      expect(text, contains('10/10'));
      final c = HiLoChallenge.decode(_code.firstMatch(text)![0]!)!;
      expect(c.seed, HiLoDaily.seedFor(4));
      expect(c.score, g.players.first.score);
      expect(text, contains('play.google.com'));

      final daily = dailyShareText(4, 2450);
      expect(daily, contains('2,450'));
      final dc = HiLoChallenge.decode(_code.firstMatch(daily)![0]!)!;
      expect(dc.config.players, HiLoDaily.configFor(4).players);
      expect(dc.seed, HiLoDaily.seedFor(4));

      final grid = answerGrid([
        for (var i = 0; i < 25; i++)
          const HiLoAnswer(
              question: HiLoQuestion(answer: 0, round: 1), given: null),
      ]);
      expect(grid, endsWith('…'));
      expect(grid.runes.where((r) => r == 0x2B1B).length, 20);
    });
  });

  group('The number pad', () {
    test('builds a signed count of up to two digits', () {
      var e = const CountEntry();
      expect(e.value, 0);
      expect(e.display, '0');
      e = e.type(0).type(0);
      expect(e.display, '0', reason: 'no leading zeros');
      e = e.type(7);
      expect(e.display, '+7');
      e = e.toggleSign();
      expect(e.value, -7);
      expect(e.display, '−7');
      e = e.type(1).type(9);
      expect(e.value, -71, reason: 'a third digit is ignored');
      e = e.backspace().backspace();
      expect(e.display, '−0');
      expect(e.value, 0);
      e = e.backspace();
      expect(e.negative, isFalse, reason: 'clearing an empty pad resets it');
      expect(const CountEntry().toggleSign().type(4).value, -4,
          reason: 'minus first, then the number');
    });
  });
  group('True count questions', () {
    HiLoQuestion q(int rc, double decks) =>
        HiLoQuestion(answer: rc, round: 1, decksLeft: decks);

    test('accept the division rounded down or up', () {
      expect(q(6, 2.5).acceptedTrueCounts(6), {2, 3}); // 2.4
      expect(q(6, 3).acceptedTrueCounts(6), {2}); // exactly 2
      expect(q(-5, 2).acceptedTrueCounts(-5), {-3, -2}); // −2.5
      expect(q(1, 4).acceptedTrueCounts(1), {0, 1}); // 0.25
      expect(q(0, 6).acceptedTrueCounts(0), {0});
    });

    test('are judged on the player\'s own running count', () {
      // True RC +6 with 3 decks left; the player said +3, then TC +1.
      const a = HiLoAnswer(
        question: HiLoQuestion(answer: 6, round: 1, decksLeft: 3),
        given: 3,
        trueCountAsked: true,
        trueCountGiven: 1,
      );
      expect(a.correct, isFalse, reason: 'the running count was wrong');
      expect(a.trueCountCorrect, isTrue,
          reason: '+3 ÷ 3 is +1 — the conversion itself was right');
      expect(
          const HiLoAnswer(
            question: HiLoQuestion(answer: 6, round: 1, decksLeft: 3),
            given: 6,
          ).trueCountCorrect,
          isNull,
          reason: 'not asked');
    });

    test('read the decks left off the shoe, to the half deck', () {
      final s = HiLoTrainingSession(
          const HiLoTrainingConfig(decks: 6, questions: 99),
          rng: Random(1));
      for (var i = 0; i < 400; i++) {
        s.advance();
        if (i % 37 == 0) {
          final q = s.ask();
          expect(q.decksLeft * 2, (q.decksLeft * 2).roundToDouble());
          expect((q.decksLeft - s.cardsLeft / 52).abs(),
              lessThanOrEqualTo(0.25 + 1e-9));
          s.answer(q.answer);
        }
      }
    });

    test('come after the running count and earn a bonus', () {
      final game = HiLoGame(HiLoGameSpec.practice(
          const HiLoTrainingConfig(questions: 3, trueCount: true),
          seed: 6));
      var asked = 0;
      while (!game.isOver) {
        if (!game.quizDue) {
          game.session.advance();
          continue;
        }
        final q = game.ask();
        expect(game.submit(q.answer, took: const Duration(seconds: 1)), isNull,
            reason: 'held for the true count');
        expect(game.awaitingTrueCount, isTrue);
        expect(game.pendingRunningCount, q.answer);
        expect(() => game.submit(1), throwsStateError);
        final tc = q.acceptedTrueCounts(q.answer).first;
        final a = game.submitTrueCount(asked == 1 ? tc + 5 : tc);
        expect(game.awaitingTrueCount, isFalse);
        expect(a.trueCountAsked, isTrue);
        expect(a.trueCountCorrect, asked != 1);
        expect(a.points.trueCount, asked != 1 ? HiLoScoring.trueCountBonus : 0);
        asked++;
      }
      final p = game.players.first;
      expect(p.correct, 3);
      expect(p.score, p.answers.fold(0, (n, a) => n + a.points.total));
    });

    test('a running count out of time skips the true count', () {
      final game = HiLoGame(HiLoGameSpec.fromChallenge(const HiLoChallenge(
        seed: 3,
        config: HiLoTrainingConfig(questions: 5, trueCount: true),
        survival: false,
        score: 1,
      )));
      while (!game.quizDue) {
        game.session.advance();
      }
      game.ask();
      final a = game.submit(null)!;
      expect(a.trueCountAsked, isFalse);
      expect(game.awaitingTrueCount, isFalse);
      // And a true count out of time is a miss.
      while (!game.quizDue) {
        game.session.advance();
      }
      final q = game.ask();
      game.submit(q.answer);
      final b = game.submitTrueCount(null);
      expect(b.trueCountCorrect, isFalse);
      expect(b.correct, isTrue);
    });

    test('are never asked in a duel', () {
      final spec = HiLoGameSpec.duel(
          names: ['A', 'B'], questions: 5, pace: HiLoPace.steady, seed: 1);
      expect(spec.asksTrueCount, isFalse);
    });

    test('travel in challenge codes, with bigger scores', () {
      const c = HiLoChallenge(
        seed: 99,
        config: HiLoTrainingConfig(trueCount: true, players: 2),
        survival: false,
        score: 120000,
      );
      final back = HiLoChallenge.decode(c.encode())!;
      expect(back.config.trueCount, isTrue);
      expect(back.score, 120000);
      expect(
          HiLoChallenge.decode(const HiLoChallenge(
            seed: 99,
            config: HiLoTrainingConfig(),
            survival: false,
            score: 5,
          ).encode())!
              .config
              .trueCount,
          isFalse);
    });

    test('are counted, and earn True Believer', () {
      var tc = const HiLoProfile();
      for (var seed = 0; seed < 3; seed++) {
        final g = HiLoGame(HiLoGameSpec.practice(
            const HiLoTrainingConfig(questions: 5, trueCount: true),
            seed: seed));
        while (!g.isOver) {
          if (!g.quizDue) {
            g.session.advance();
            continue;
          }
          final q = g.ask();
          g.submit(q.answer);
          g.submitTrueCount(q.acceptedTrueCounts(q.answer).first);
        }
        tc = applyGame(tc, g).after;
      }
      expect(tc.trueCountsAsked, 15);
      expect(tc.trueCountsRight, 15);
      expect(tc.achievements, contains(HiLoAchievement.trueBeliever));
      final back = HiLoProfile.fromJson(tc.toJson());
      expect(back.trueCountsRight, 15);
    });
  });

  group('Fixes', () {
    test('a replayed shoe earns no XP, records or wins', () {
      final first = HiLoGameSpec.fromChallenge(const HiLoChallenge(
        seed: 21,
        config: HiLoTrainingConfig(questions: 5),
        survival: false,
        score: 100,
      ));
      final won =
          applyGame(const HiLoProfile(), _playOut(HiLoGame(first), _right));
      expect(won.after.challengesWon, 1);
      expect(won.xpGained, greaterThan(0));

      final replay =
          applyGame(won.after, _playOut(HiLoGame(first.again()), _right));
      expect(replay.ranked, isFalse);
      expect(replay.xpGained, 0);
      expect(replay.after.challengesWon, 1, reason: 'no second win');
      expect(replay.after.correct, 10, reason: 'still practice for counts');

      var n = 0;
      final survival = HiLoGameSpec.survival(seed: 4, targetScore: 50);
      final run = _playOut(
          HiLoGame(survival.again()), (q, _) => n++ < 6 ? q.answer : null);
      final r = applyGame(const HiLoProfile(), run);
      expect(r.after.survivalTop, isEmpty);
      expect(r.newBest, isFalse);
      expect(r.unlocked, isNot(contains(HiLoAchievement.quickDraw)),
          reason: 'game achievements need a ranked game');
      expect(r.unlocked, contains(HiLoAchievement.firstCount),
          reason: 'lifetime counts still count');
    });

    test('a duel quit part-way earns nothing', () {
      final game = HiLoGame(HiLoGameSpec.duel(
          names: ['A', 'B'], questions: 5, pace: HiLoPace.steady, seed: 3));
      while (!game.quizDue) {
        game.session.advance();
      }
      final q = game.ask();
      game.submit(q.answer);
      game.submit(q.answer);
      game.quit();
      final r = applyGame(const HiLoProfile(), game);
      expect(r.xpGained, 0);
      expect(r.after.duels, 0);
      expect(game.completed, isFalse);
    });

    test('a duel ended mid-question takes the half-answer back', () {
      final game = HiLoGame(HiLoGameSpec.duel(
          names: ['A', 'B'], questions: 5, pace: HiLoPace.steady, seed: 8));
      for (var round = 0; round < 2; round++) {
        while (!game.quizDue) {
          game.session.advance();
        }
        final q = game.ask();
        game.submit(q.answer);
        if (round == 0) game.submit(q.answer);
      }
      final a = game.players[game.turn == 0 ? 1 : 0];
      expect(game.midQuestion, isTrue);
      expect(a.answered, 2, reason: 'one player is a question ahead');
      game.quit();
      expect(game.players.map((p) => p.answered), [1, 1]);
      expect(game.players[0].score, game.players[1].score);
      expect(game.winner, isNull, reason: 'level after the rollback');
      expect(game.players.map((p) => p.streak), [1, 1]);
    });

    test('Casino Speed needs a finished game', () {
      final game = HiLoGame(HiLoGameSpec.practice(
          const HiLoTrainingConfig(pace: HiLoPace.casino, questions: 10),
          seed: 2));
      var answered = 0;
      while (answered < 6) {
        if (game.quizDue) {
          final q = game.ask();
          game.submit(q.answer);
          answered++;
        } else {
          game.session.advance();
        }
      }
      game.quit();
      expect(applyGame(const HiLoProfile(), game).unlocked,
          isNot(contains(HiLoAchievement.casinoSpeed)));
    });

    test('mistakes are tallied by habit', () {
      final g = _playOut(
        HiLoGame(HiLoGameSpec.practice(const HiLoTrainingConfig(questions: 10),
            seed: 7)),
        (q, _) => -q.answer == q.answer ? q.answer + 40 : -q.answer,
      );
      final p = applyGame(const HiLoProfile(), g).after;
      final wrong = g.players.first.answers.where((a) => !a.correct).length;
      expect(p.slips.values.fold(0, (n, v) => n + v), wrong);
      expect(p.commonSlip, HiLoSlip.flippedSign);
      expect(HiLoProfile.fromJson(p.toJson()).slips, p.slips);
      expect(const HiLoProfile(slips: {HiLoSlip.drift: 2}).commonSlip, isNull,
          reason: 'two misses are not a pattern yet');
    });

    test('a clock set before launch day still gets Daily #1', () {
      expect(HiLoDaily.numberFor(DateTime(2026, 1, 1)), 1);
    });

    test('the text for true counts and misses', () {
      expect(decksText(2.5), '2.5');
      expect(decksText(3), '3');
      expect(signedDecimal(1.6), '+1.6');
      expect(signedDecimal(-0.4), '−0.4');
      expect(signedDecimal(0.01), '0');
      const a = HiLoAnswer(
        question: HiLoQuestion(answer: 4, round: 1, decksLeft: 2.5),
        given: 4,
        trueCountAsked: true,
        trueCountGiven: 2,
      );
      expect(trueCountWorking(a), '+4 ÷ 2.5 decks = +1.6, so +1 or +2');
      expect(slipName(HiLoSlip.countedHoleCard), contains('face-down'));
      expect(tableLabel(const HiLoTrainingConfig(trueCount: true)),
          endsWith('· true count'));

      // Running counts right, true counts wrong: the tip is about the
      // conversion.
      final answers = [
        for (var i = 0; i < 4; i++)
          const HiLoAnswer(
            question: HiLoQuestion(answer: 6, round: 1, decksLeft: 3),
            given: 6,
            trueCountAsked: true,
            trueCountGiven: 9,
          ),
      ];
      expect(coachingTip(answers, const HiLoTrainingConfig(trueCount: true)),
          contains('true counts were not'));
    });

    test('the true count setting is saved with the others', () async {
      await HiLoTrainingProgress.saveConfig(
          const HiLoTrainingConfig(trueCount: true));
      expect((await HiLoTrainingProgress.loadConfig()).trueCount, isTrue);
    });
  });
}

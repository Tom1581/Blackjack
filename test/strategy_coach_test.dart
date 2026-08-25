import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StrategyCoach.resetForTest();
    await StrategyCoach.reset();
  });

  group('Decision accuracy', () {
    test('a fresh player has no record and no false perfection', () async {
      final record = await StrategyCoach.read();
      expect(record.total, 0);
      expect(record.accuracy, 0, reason: 'zero decisions is not 100%');
      expect(record.isMeaningful, isFalse);
    });

    test('it counts right and wrong decisions', () async {
      await StrategyCoach.record(correct: true);
      await StrategyCoach.record(correct: true);
      await StrategyCoach.record(correct: false);

      final record = await StrategyCoach.read();
      expect(record.total, 3);
      expect(record.correct, 2);
      expect(record.mistakes, 1);
      expect(record.accuracyPercent, 67);
    });

    test('accuracy is only called meaningful after enough hands', () async {
      for (var i = 0; i < 19; i++) {
        await StrategyCoach.record(correct: true);
      }
      expect((await StrategyCoach.read()).isMeaningful, isFalse);
      await StrategyCoach.record(correct: true);
      expect((await StrategyCoach.read()).isMeaningful, isTrue);
    });

    test('the record survives a restart, and can be cleared', () async {
      await StrategyCoach.record(correct: true);
      await StrategyCoach.record(correct: false);
      expect((await StrategyCoach.read()).total, 2);

      await StrategyCoach.reset();
      expect((await StrategyCoach.read()).total, 0);
    });
  });

  group('Hints preference', () {
    test('hints are on by default — this is a trainer', () async {
      await StrategyCoach.load();
      expect(StrategyCoach.hintsEnabled, isTrue);
    });

    test('turning them off sticks across a restart', () async {
      await StrategyCoach.setHintsEnabled(false);
      StrategyCoach.resetForTest();
      await StrategyCoach.load();
      expect(StrategyCoach.hintsEnabled, isFalse);
    });
  });

  group('Feedback wording', () {
    test('it names the hand and the better play', () {
      const feedback = StrategyFeedback(
        played: StrategyMove.hit,
        best: StrategyMove.stand,
        handValue: 16,
        handWasSoft: false,
        dealerUp: '5',
      );
      expect(feedback.message, '16 vs 5 — basic strategy says Stand');
    });

    test('a soft hand is described as soft, because the play differs', () {
      const feedback = StrategyFeedback(
        played: StrategyMove.stand,
        best: StrategyMove.double,
        handValue: 18,
        handWasSoft: true,
        dealerUp: '5',
      );
      expect(feedback.message, 'Soft 18 vs 5 — basic strategy says Double');
    });
  });
}

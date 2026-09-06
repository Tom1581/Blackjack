import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/growth/share_messages.dart';
import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/features/drill/daily_count_drill.dart';
import 'package:blackjack_app/features/drill/daily_count_drill_progress.dart';

void main() {
  group('Daily Count Drill', () {
    test('uses a repeatable, non-repeating slice of a shuffled deck', () {
      final first = DailyCountDrill.forDay(20260905);
      final second = DailyCountDrill.forDay(20260905);

      expect(first.cards, hasLength(dailyCountDrillCardCount));
      expect(first.cards.map((card) => card.toString()),
          orderedEquals(second.cards.map((card) => card.toString())));
      expect(first.cards.map((card) => card.toString()).toSet(),
          hasLength(dailyCountDrillCardCount));
    });

    test('uses Hi-Lo values for every rank', () {
      CardModel card(Rank rank) => CardModel(suit: Suit.spades, rank: rank);

      for (final rank in const [
        Rank.two,
        Rank.three,
        Rank.four,
        Rank.five,
        Rank.six,
      ]) {
        expect(DailyCountDrill.contributionFor(card(rank)), 1);
      }
      for (final rank in const [Rank.seven, Rank.eight, Rank.nine]) {
        expect(DailyCountDrill.contributionFor(card(rank)), 0);
      }
      for (final rank in const [
        Rank.ten,
        Rank.jack,
        Rank.queen,
        Rank.king,
        Rank.ace,
      ]) {
        expect(DailyCountDrill.contributionFor(card(rank)), -1);
      }
    });

    test('keeps the best score and streak for the same day', () async {
      SharedPreferences.setMockInitialValues({});
      const dayKey = 20260905;

      await DailyCountDrillProgress.record(const DailyCountDrillResult(
        dayKey: dayKey,
        correct: 13,
        answered: 20,
        bestStreak: 5,
      ));
      final best = await DailyCountDrillProgress.record(
        const DailyCountDrillResult(
          dayKey: dayKey,
          correct: 11,
          answered: 20,
          bestStreak: 7,
        ),
      );

      expect(best.correct, 13);
      expect(best.bestStreak, 7);
    });
  });

  group('Growth share messages', () {
    test('includes the score and store listing', () {
      final message = GrowthShareMessages.dailyDrill(
        correct: 18,
        total: 20,
        bestStreak: 9,
      );

      expect(message, contains('18/20'));
      expect(message, contains('9-card streak'));
      expect(message, contains(hiLoBlackjackPlayStoreUrl));
    });

    test('normalizes a room code before sharing it', () {
      final message = GrowthShareMessages.roomInvite(' ab12c ');

      expect(message, contains('AB12C'));
      expect(message, contains(hiLoBlackjackPlayStoreUrl));
    });
  });
}

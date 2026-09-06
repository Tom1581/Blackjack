import '../../core/models/card_model.dart';

const int dailyCountDrillCardCount = 20;
const int dailyCountDrillDurationSeconds = 60;

/// A deterministic, daily set of cards for short Hi-Lo practice.
///
/// The drill uses an actual shuffled deck rather than a stream of random
/// ranks, so a rank cannot appear more than its four real copies. Keeping the
/// sequence local also makes this practice feature independent of table play
/// and the online service.
class DailyCountDrill {
  final int dayKey;
  final List<CardModel> cards;

  const DailyCountDrill._({required this.dayKey, required this.cards});

  factory DailyCountDrill.forDay(int dayKey) {
    final deck = _shuffledDeck(dayKey);
    return DailyCountDrill._(
      dayKey: dayKey,
      cards: List.unmodifiable(deck.take(dailyCountDrillCardCount)),
    );
  }

  factory DailyCountDrill.today({DateTime? now}) =>
      DailyCountDrill.forDay(dayKeyFor(now ?? DateTime.now()));

  /// A stable key for a local calendar day. It intentionally does not depend
  /// on a timezone difference in hours, which would be wrong around DST.
  static int dayKeyFor(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static int contributionFor(CardModel card) {
    switch (card.rank) {
      case Rank.two:
      case Rank.three:
      case Rank.four:
      case Rank.five:
      case Rank.six:
        return 1;
      case Rank.seven:
      case Rank.eight:
      case Rank.nine:
        return 0;
      case Rank.ten:
      case Rank.jack:
      case Rank.queen:
      case Rank.king:
      case Rank.ace:
        return -1;
    }
  }

  static List<CardModel> _shuffledDeck(int dayKey) {
    final deck = <CardModel>[
      for (final suit in Suit.values)
        for (final rank in Rank.values) CardModel(suit: suit, rank: rank),
    ];

    // A tiny deterministic generator keeps the same challenge stable across
    // app launches and platforms. Its multiplication stays exact on Dart web.
    var state = dayKey % 2147483647;
    if (state == 0) state = 1;
    for (var index = deck.length - 1; index > 0; index--) {
      state = (state * 48271) % 2147483647;
      final replacement = state % (index + 1);
      final card = deck[index];
      deck[index] = deck[replacement];
      deck[replacement] = card;
    }
    return deck;
  }
}

class DailyCountDrillResult {
  final int dayKey;
  final int correct;
  final int answered;
  final int bestStreak;

  const DailyCountDrillResult({
    required this.dayKey,
    required this.correct,
    required this.answered,
    required this.bestStreak,
  });

  int get total => dailyCountDrillCardCount;

  int get accuracy => answered == 0 ? 0 : (correct * 100 / answered).round();
}

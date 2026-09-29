import '../models/card_model.dart';

enum CountSignal { favorable, neutral, unfavorable }

/// Hi-Lo card counting system, ported from blackjack.py update_count().
/// Low cards (2–6) → +1, High cards (10/J/Q/K/A) → −1, Neutral (7–9) → 0.
/// Adds true count (running ÷ decks remaining) for better bet-sizing signal.
class HiLoCounter {
  int _runningCount = 0;
  double _decksRemaining;
  final int totalDecks;

  HiLoCounter({required this.totalDecks})
      : _decksRemaining = totalDecks.toDouble();

  int get runningCount => _runningCount;

  /// Decks left in the shoe, to the nearest half deck — the resolution a
  /// player can actually read off a discard tray.
  double get decksRemaining => _decksRemaining;

  double get trueCount => _runningCount / _decksRemaining;

  CountSignal get signal {
    final tc = trueCount;
    if (tc >= 2) return CountSignal.favorable;
    if (tc <= -1) return CountSignal.unfavorable;
    return CountSignal.neutral;
  }

  /// Call after each card is revealed (face-up).
  void update(CardModel card) {
    switch (card.rank) {
      case Rank.two:
      case Rank.three:
      case Rank.four:
      case Rank.five:
      case Rank.six:
        _runningCount++;
      case Rank.ten:
      case Rank.jack:
      case Rank.queen:
      case Rank.king:
      case Rank.ace:
        _runningCount--;
      default:
        // 7, 8, 9 — neutral
        break;
    }
  }

  /// Estimate decks remaining to the nearest half deck, never below half.
  ///
  /// This used to round *up* to a whole deck, which overstated the decks left
  /// and so understated the true count exactly when it matters most: with 75
  /// cards left (about 1.5 decks) a running count of +6 read as TC +3 instead
  /// of +4, a whole betting unit too timid late in the shoe.
  void updateDecksRemaining(int cardsLeft) {
    _decksRemaining = estimateDecks(cardsLeft, maxDecks: totalDecks);
  }

  /// [cardsLeft] as decks, rounded to the nearest half deck and kept within
  /// half a deck and [maxDecks].
  static double estimateDecks(int cardsLeft, {required int maxDecks}) {
    final halves = (cardsLeft / 26).round();
    return (halves / 2).clamp(0.5, maxDecks.toDouble());
  }

  void reset() {
    _runningCount = 0;
    _decksRemaining = totalDecks.toDouble();
  }
}

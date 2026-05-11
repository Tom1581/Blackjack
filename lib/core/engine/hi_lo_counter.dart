import '../models/card_model.dart';

enum CountSignal { favorable, neutral, unfavorable }

/// Hi-Lo card counting system, ported from blackjack.py update_count().
/// Low cards (2–6) → +1, High cards (10/J/Q/K/A) → −1, Neutral (7–9) → 0.
/// Adds true count (running ÷ decks remaining) for better bet-sizing signal.
class HiLoCounter {
  int _runningCount = 0;
  int _decksRemaining;
  final int totalDecks;

  HiLoCounter({required this.totalDecks}) : _decksRemaining = totalDecks;

  int get runningCount => _runningCount;

  double get trueCount =>
      _decksRemaining > 0 ? _runningCount / _decksRemaining : _runningCount.toDouble();

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

  void updateDecksRemaining(int cardsLeft) {
    _decksRemaining = (cardsLeft / 52).ceil().clamp(1, totalDecks);
  }

  void reset() {
    _runningCount = 0;
    _decksRemaining = totalDecks;
  }
}

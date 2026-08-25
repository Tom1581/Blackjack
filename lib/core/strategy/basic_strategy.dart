import '../models/card_model.dart';
import '../models/hand_model.dart';

/// A decision the player can make on a hand.
enum StrategyMove {
  hit('Hit'),
  stand('Stand'),
  double('Double'),
  split('Split');

  const StrategyMove(this.label);

  /// Human label, used in coaching messages.
  final String label;
}

/// Basic strategy for **this game's** rules, which is the only chart worth
/// showing a player: six decks, **dealer hits soft 17**, double on any two,
/// double after split allowed, no surrender.
///
/// Those rules matter. The H17 chart differs from the far more commonly
/// published S17 one in exactly three places — 11 vs ace, soft 18 vs 2, and
/// soft 19 vs 6 — and each is called out below. Teaching an S17 chart at an
/// H17 table is the classic way a trainer quietly makes someone worse.
class BasicStrategy {
  const BasicStrategy._();

  /// The correct play for [hand] against the dealer's [dealerUp].
  ///
  /// [canDouble] and [canSplit] describe what the table will actually allow
  /// right now — chips in hand, two cards, hand limits. When the chart wants a
  /// move that is unavailable it falls back the way a real chart's footnotes
  /// say to, never to something arbitrary.
  static StrategyMove best({
    required HandModel hand,
    required CardModel dealerUp,
    bool canDouble = true,
    bool canSplit = true,
  }) {
    final up = upCardValue(dealerUp);

    if (canSplit && hand.isPair) {
      final pairValue = hand.cards.first.rank.value;
      if (_shouldSplit(pairValue, up)) return StrategyMove.split;
      // A pair we do not split is played on its total — five-five is a ten,
      // not a pair of fives.
    }

    final ideal =
        hand.isSoft ? _soft(hand.value, up) : _hard(hand.value, up);
    if (ideal == StrategyMove.double && !canDouble) {
      return _withoutDouble(hand);
    }
    return ideal;
  }

  /// Dealer up-card as the chart indexes it: ace is 11, faces are 10.
  static int upCardValue(CardModel card) => card.rank.value;

  // ─── Hard totals ─────────────────────────────────────────────────────────

  static StrategyMove _hard(int total, int up) {
    if (total >= 17) return StrategyMove.stand;
    if (total >= 13) {
      // 13–16: stand against a dealer likely to bust, otherwise take the card.
      return up <= 6 ? StrategyMove.stand : StrategyMove.hit;
    }
    if (total == 12) {
      // Twelve is the exception: only 4, 5 and 6 are worth standing on.
      return (up >= 4 && up <= 6) ? StrategyMove.stand : StrategyMove.hit;
    }
    if (total == 11) {
      // H17 difference: eleven doubles against everything, ace included.
      return StrategyMove.double;
    }
    if (total == 10) {
      return up <= 9 ? StrategyMove.double : StrategyMove.hit;
    }
    if (total == 9) {
      return (up >= 3 && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    return StrategyMove.hit; // eight or less
  }

  // ─── Soft totals (an ace still counting as eleven) ───────────────────────

  static StrategyMove _soft(int total, int up) {
    if (total >= 20) return StrategyMove.stand; // A,9 and A,10
    if (total == 19) {
      // H17 difference: A,8 doubles against a six.
      return up == 6 ? StrategyMove.double : StrategyMove.stand;
    }
    if (total == 18) {
      // H17 difference: A,7 doubles against a two as well as 3–6.
      if (up >= 2 && up <= 6) return StrategyMove.double;
      if (up == 7 || up == 8) return StrategyMove.stand;
      return StrategyMove.hit; // 9, 10, ace — eighteen is not good enough
    }
    if (total == 17) {
      return (up >= 3 && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    if (total == 16 || total == 15) {
      return (up >= 4 && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    if (total == 14 || total == 13) {
      return (up >= 5 && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    return StrategyMove.hit;
  }

  // ─── Pairs (double after split is allowed here) ──────────────────────────

  static bool _shouldSplit(int cardValue, int up) {
    switch (cardValue) {
      case 11: // A,A — always. Two chances at twenty-one beats a soft twelve.
        return true;
      case 10: // Twenty is already a winning hand. Never break it.
        return false;
      case 9: // Split except against 7, 10 and ace.
        return up <= 6 || up == 8 || up == 9;
      case 8: // Always. Sixteen is the worst hand in the game.
        return true;
      case 7:
        return up <= 7;
      case 6:
        return up <= 6; // 2 included because double-after-split is allowed
      case 5: // Never. A pair of fives is a ten and wants doubling.
        return false;
      case 4:
        return up == 5 || up == 6; // only with double-after-split
      case 3:
      case 2:
        return up <= 7;
      default:
        return false;
    }
  }

  /// What to do when the chart says double but the table will not allow it.
  ///
  /// Soft eighteen and nineteen are the "Ds" cells — double if you can,
  /// otherwise **stand**. Everywhere else a blocked double becomes a hit.
  static StrategyMove _withoutDouble(HandModel hand) {
    if (hand.isSoft && hand.value >= 18) return StrategyMove.stand;
    return StrategyMove.hit;
  }
}

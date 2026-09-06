import '../models/card_model.dart';
import '../models/hand_model.dart';
import '../rules/rule_set.dart';

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

/// Basic strategy, calculated against a specific [RuleSet].
///
/// Strategy is not universal, which is the whole reason this takes rules at
/// all. The H17 chart differs from the far more commonly published S17 one in
/// exactly three places — 11 vs ace, soft 18 vs 2, and soft 19 vs 6 — and
/// double-after-split changes four pair rows. Teaching the wrong one is how a
/// trainer quietly makes someone worse.
///
/// **Deck count:** these are the multi-deck tables, correct for four decks and
/// up. Single and double deck have materially different charts and are not
/// offered as presets until those charts exist and are tested.
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
    RuleSet rules = RuleSet.sixDeckH17,
  }) {
    final up = upCardValue(dealerUp);

    if (canSplit && hand.isPair) {
      final pairValue = hand.cards.first.rank.value;
      if (_shouldSplit(pairValue, up, rules)) return StrategyMove.split;
      // A pair we do not split is played on its total — five-five is a ten,
      // not a pair of fives.
    }

    final ideal = hand.isSoft
        ? _soft(hand.value, up, rules)
        : _hard(hand.value, up, rules);

    if (ideal == StrategyMove.double) {
      final permitted = canDouble &&
          rules.allowsDoubleOn(hand.value, isSoft: hand.isSoft);
      if (!permitted) return _withoutDouble(hand);
    }
    return ideal;
  }

  /// Dealer up-card as the chart indexes it: ace is 11, faces are 10.
  static int upCardValue(CardModel card) => card.rank.value;

  // ─── Hard totals ─────────────────────────────────────────────────────────

  static StrategyMove _hard(int total, int up, RuleSet rules) {
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
      // Rule difference: against an ace, eleven doubles when the dealer hits
      // soft 17 and hits when they stand.
      if (up == 11) {
        return rules.dealerHitsSoft17 ? StrategyMove.double : StrategyMove.hit;
      }
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

  static StrategyMove _soft(int total, int up, RuleSet rules) {
    if (total >= 20) return StrategyMove.stand; // A,9 and A,10
    if (total == 19) {
      // Rule difference: A,8 doubles against a six only when the dealer hits
      // soft 17. Otherwise nineteen simply stands.
      if (up == 6 && rules.dealerHitsSoft17) return StrategyMove.double;
      return StrategyMove.stand;
    }
    if (total == 18) {
      // Rule difference: A,7 doubles against a two under H17, and stands
      // against it under S17.
      if (up == 2) {
        return rules.dealerHitsSoft17
            ? StrategyMove.double
            : StrategyMove.stand;
      }
      if (up >= 3 && up <= 6) return StrategyMove.double;
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

  static bool _shouldSplit(int cardValue, int up, RuleSet rules) {
    final das = rules.doubleAfterSplit;
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
        // Against a two only when doubling after the split is allowed.
        return das ? up <= 6 : (up >= 3 && up <= 6);
      case 5: // Never. A pair of fives is a ten and wants doubling.
        return false;
      case 4:
        // Only worth splitting when the follow-up double is available.
        return das && (up == 5 || up == 6);
      case 3:
      case 2:
        return das ? up <= 7 : (up >= 4 && up <= 7);
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

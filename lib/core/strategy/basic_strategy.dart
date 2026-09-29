import '../models/card_model.dart';
import '../models/hand_model.dart';
import '../rules/rule_set.dart';

/// A decision the player can make on a hand.
enum StrategyMove {
  hit('Hit'),
  stand('Stand'),
  double('Double'),
  split('Split'),

  /// Late surrender: give up half the bet before playing the hand.
  surrender('Surrender');

  const StrategyMove(this.label);

  /// Human label, used in coaching messages.
  final String label;
}

/// Basic strategy, calculated against a specific [RuleSet] and shoe size.
///
/// Strategy is not universal, which is the whole reason this takes rules at
/// all. The H17 chart differs from the far more commonly published S17 one in
/// exactly three places — 11 vs ace, soft 18 vs 2, and soft 19 vs 6 — and
/// double-after-split changes four pair rows. Teaching the wrong one is how a
/// trainer quietly makes someone worse.
///
/// **Deck count:** four decks and up share one chart. A two-deck shoe differs
/// in a handful of cells (9 v 2, 11 v A under S17, A,3 v 4 under H17 and the
/// 6,6 / 7,7 splits), and late surrender drops 16 v 9.
/// Single deck is not offered at all.
///
/// Every cell — for 2, 6 and 8 decks, H17 and S17, with and without DAS, each
/// doubling rule, with and without late surrender — is checked against a
/// published strategy engine in `test/strategy_reference_test.dart`, and the
/// cells that differ between shoes were re-derived independently with an
/// expected-value calculation (`tool/strategy_check/`).
class BasicStrategy {
  const BasicStrategy._();

  /// The correct play for [hand] against the dealer's [dealerUp].
  ///
  /// [canDouble], [canSplit] and [canSurrender] describe what the table will
  /// actually allow right now — chips in hand, two cards, hand limits, the
  /// surrender rule. When the chart wants a move that is unavailable it falls
  /// back the way a real chart's footnotes say to, never to something
  /// arbitrary.
  ///
  /// [decks] is the number of decks in the shoe.
  static StrategyMove best({
    required HandModel hand,
    required CardModel dealerUp,
    bool canDouble = true,
    bool canSplit = true,
    bool canSurrender = false,
    RuleSet rules = RuleSet.sixDeckH17,
    int decks = 6,
  }) {
    final up = upCardValue(dealerUp);
    final twoDeck = decks <= 2;
    final splittable = canSplit && hand.isPair;

    // Late surrender comes first: it is only offered on the first two cards,
    // and where the chart says surrender it beats every other option.
    if (canSurrender && rules.lateSurrender && hand.cards.length == 2) {
      if (_shouldSurrender(hand, up, rules, twoDeck, splittable)) {
        return StrategyMove.surrender;
      }
    }

    if (splittable) {
      final pairValue = hand.cards.first.rank.value;
      if (_shouldSplit(pairValue, up, rules, twoDeck)) {
        return StrategyMove.split;
      }
      // A pair we do not split is played on its total — five-five is a ten,
      // not a pair of fives.
    }

    final ideal = hand.isSoft
        ? _soft(hand.value, up, rules, twoDeck)
        : _hard(hand.value, up, rules, twoDeck);

    if (ideal == StrategyMove.double) {
      final permitted =
          canDouble && rules.allowsDoubleOn(hand.value, isSoft: hand.isSoft);
      if (!permitted) return _withoutDouble(hand);
    }
    return ideal;
  }

  /// Dealer up-card as the chart indexes it: ace is 11, faces are 10.
  static int upCardValue(CardModel card) => card.rank.value;

  // ─── Late surrender ──────────────────────────────────────────────────────

  static bool _shouldSurrender(
    HandModel hand,
    int up,
    RuleSet rules,
    bool twoDeck,
    bool splittable,
  ) {
    final h17 = rules.dealerHitsSoft17;
    if (splittable) {
      // Eights against an ace: under H17 surrender beats splitting — except
      // in a two-deck game with double after split, where the split is worth
      // enough to keep.
      return hand.cards.first.rank.value == 8 &&
          up == 11 &&
          h17 &&
          (!twoDeck || !rules.doubleAfterSplit);
    }
    if (hand.isSoft) return false;
    switch (hand.value) {
      case 17:
        return h17 && up == 11;
      case 16:
        return up == 10 || up == 11 || (up == 9 && !twoDeck);
      case 15:
        return up == 10 || (up == 11 && h17);
      default:
        return false;
    }
  }

  // ─── Hard totals ─────────────────────────────────────────────────────────

  static StrategyMove _hard(int total, int up, RuleSet rules, bool twoDeck) {
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
      // soft 17 and hits when they stand — except from two decks, where the
      // ace is weak enough to double either way.
      if (up == 11) {
        return rules.dealerHitsSoft17 || twoDeck
            ? StrategyMove.double
            : StrategyMove.hit;
      }
      return StrategyMove.double;
    }
    if (total == 10) {
      return up <= 9 ? StrategyMove.double : StrategyMove.hit;
    }
    if (total == 9) {
      // Two decks: nine doubles against a two as well.
      final low = twoDeck ? 2 : 3;
      return (up >= low && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    return StrategyMove.hit; // eight or less
  }

  // ─── Soft totals (an ace still counting as eleven) ───────────────────────

  static StrategyMove _soft(int total, int up, RuleSet rules, bool twoDeck) {
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
    if (total == 14) {
      // A,3. Two decks with a dealer who hits soft 17: double against a four
      // as well.
      final low = twoDeck && rules.dealerHitsSoft17 ? 4 : 5;
      return (up >= low && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    if (total == 13) {
      return (up >= 5 && up <= 6) ? StrategyMove.double : StrategyMove.hit;
    }
    return StrategyMove.hit;
  }

  // ─── Pairs ───────────────────────────────────────────────────────────────

  static bool _shouldSplit(int cardValue, int up, RuleSet rules, bool twoDeck) {
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
        // Two decks with DAS: sevens split against an eight too.
        return up <= (twoDeck && das ? 8 : 7);
      case 6:
        if (twoDeck) {
          // Two decks: against a seven with DAS; from a two up without it.
          return das ? up <= 7 : up <= 6;
        }
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

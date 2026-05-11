import 'card_model.dart';

class HandModel {
  final List<CardModel> cards;
  final bool isDoubled;

  const HandModel({this.cards = const [], this.isDoubled = false});

  HandModel addCard(CardModel card) =>
      HandModel(cards: [...cards, card], isDoubled: isDoubled);

  HandModel markDoubled() =>
      HandModel(cards: cards, isDoubled: true);

  // Flexible Ace calculation — same logic as hand_value() in blackjack.py
  int get value {
    int total = 0;
    int aces = 0;
    for (final card in cards) {
      total += card.rank.value;
      if (card.rank == Rank.ace) aces++;
    }
    // Reduce each ace from 11→1 as needed to avoid bust
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return total;
  }

  /// A hand is "soft" when at least one ace is currently being counted as 11
  /// in the played value. The previous implementation only checked the
  /// undemoted total, which incorrectly classified hands like A+A+5 (soft 17,
  /// played as 1+11+5) as hard — causing the dealer to stand on what should
  /// be a soft 17.
  bool get isSoft {
    int total = 0;
    int aces = 0;
    for (final card in cards) {
      total += card.rank.value;
      if (card.rank == Rank.ace) aces++;
    }
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return aces > 0 && total <= 21;
  }

  bool get isBust => value > 21;

  bool get isBlackjack => cards.length == 2 && value == 21;

  bool get isPair =>
      cards.length == 2 && cards[0].rank == cards[1].rank;

  // House rule: double allowed on any two-card hand (DOA — Double On Any).
  bool get canDouble => cards.length == 2;

  HandModel revealAll() => HandModel(
        cards: cards.map((c) => c.copyWith(faceUp: true)).toList(),
        isDoubled: isDoubled,
      );
}

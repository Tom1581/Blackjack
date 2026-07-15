import 'card_model.dart';

class HandModel {
  final List<CardModel> cards;
  final bool isDoubled;

  /// The base wager staked on this hand/betting-spot. In a multi-spot round
  /// each hand carries its own bet, so payouts are computed per hand rather
  /// than by dividing a single shared total. Split hands inherit the source
  /// hand's [bet].
  final int bet;

  /// True when this hand was produced by splitting a pair. A split hand can
  /// never be a "natural" blackjack (a two-card 21 from a split pays 1:1, not
  /// 3:2), so payout resolution needs to know a hand's origin.
  final bool fromSplit;

  const HandModel({
    this.cards = const [],
    this.isDoubled = false,
    this.bet = 0,
    this.fromSplit = false,
  });

  HandModel copyWith({
    List<CardModel>? cards,
    bool? isDoubled,
    int? bet,
    bool? fromSplit,
  }) =>
      HandModel(
        cards: cards ?? this.cards,
        isDoubled: isDoubled ?? this.isDoubled,
        bet: bet ?? this.bet,
        fromSplit: fromSplit ?? this.fromSplit,
      );

  // Wire format for online play.
  Map<String, dynamic> toJson() => {
        'c': cards.map((c) => c.toJson()).toList(),
        'd': isDoubled,
        'b': bet,
        'fs': fromSplit,
      };

  factory HandModel.fromJson(Map<String, dynamic> json) => HandModel(
        cards: [
          for (final c in (json['c'] as List? ?? const []))
            CardModel.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        isDoubled: json['d'] as bool? ?? false,
        bet: json['b'] as int? ?? 0,
        fromSplit: json['fs'] as bool? ?? false,
      );

  HandModel addCard(CardModel card) => copyWith(cards: [...cards, card]);

  HandModel markDoubled() => copyWith(isDoubled: true);

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

  HandModel revealAll() => copyWith(
        cards: cards.map((c) => c.copyWith(faceUp: true)).toList(),
      );
}

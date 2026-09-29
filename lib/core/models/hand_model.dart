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

  /// The player gave this hand up (late surrender): half the bet comes back
  /// and the hand takes no further part in the round.
  final bool surrendered;

  const HandModel({
    this.cards = const [],
    this.isDoubled = false,
    this.bet = 0,
    this.fromSplit = false,
    this.surrendered = false,
  });

  HandModel copyWith({
    List<CardModel>? cards,
    bool? isDoubled,
    int? bet,
    bool? fromSplit,
    bool? surrendered,
  }) =>
      HandModel(
        cards: cards ?? this.cards,
        isDoubled: isDoubled ?? this.isDoubled,
        bet: bet ?? this.bet,
        fromSplit: fromSplit ?? this.fromSplit,
        surrendered: surrendered ?? this.surrendered,
      );

  // Wire format for online play.
  Map<String, dynamic> toJson() => {
        'c': cards.map((c) => c.toJson()).toList(),
        'd': isDoubled,
        'b': bet,
        'fs': fromSplit,
        if (surrendered) 'sr': true,
      };

  factory HandModel.fromJson(Map<String, dynamic> json) => HandModel(
        cards: [
          for (final c in (json['c'] as List? ?? const []))
            CardModel.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        isDoubled: json['d'] as bool? ?? false,
        bet: json['b'] as int? ?? 0,
        fromSplit: json['fs'] as bool? ?? false,
        surrendered: json['sr'] as bool? ?? false,
      );

  HandModel addCard(CardModel card) => copyWith(cards: [...cards, card]);

  HandModel markDoubled() => copyWith(isDoubled: true);

  HandModel markSurrendered() => copyWith(surrendered: true);

  /// True when any card in this hand was redacted in transit — i.e. we are a
  /// guest looking at the dealer's unturned hole card. Value-derived getters
  /// below skip those cards, so they report the *visible* total rather than
  /// silently folding in a placeholder rank.
  bool get hasHidden {
    for (final card in cards) {
      if (card.hidden) return true;
    }
    return false;
  }

  // Flexible Ace calculation — same logic as hand_value() in blackjack.py
  int get value {
    int total = 0;
    int aces = 0;
    for (final card in cards) {
      if (card.hidden) continue;
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
      if (card.hidden) continue;
      total += card.rank.value;
      if (card.rank == Rank.ace) aces++;
    }
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return aces > 0 && total <= 21;
  }

  /// True while any card is still face down — the dealer's unturned hole card,
  /// whether it was dealt locally or redacted in transit.
  bool get hasFaceDown {
    for (final card in cards) {
      if (card.hidden || !card.faceUp) return true;
    }
    return false;
  }

  /// The total a player at the table can actually see: face-down cards are
  /// left out. [value] deliberately includes a locally dealt hole card (the
  /// engine needs it to peek for blackjack), so anything *shown* to the player
  /// must use this instead or it gives the hole card away.
  int get visibleValue {
    int total = 0;
    int aces = 0;
    for (final card in cards) {
      if (card.hidden || !card.faceUp) continue;
      total += card.rank.value;
      if (card.rank == Rank.ace) aces++;
    }
    while (total > 21 && aces > 0) {
      total -= 10;
      aces--;
    }
    return total;
  }

  /// A two-card 21 that was dealt, not made by splitting — the only hand that
  /// pays the blackjack bonus and needs nothing from the dealer's draw.
  bool get isNatural => !fromSplit && isBlackjack;

  bool get isBust => !hasHidden && value > 21;

  bool get isBlackjack => cards.length == 2 && !hasHidden && value == 21;

  bool get isPair =>
      cards.length == 2 && !hasHidden && cards[0].rank == cards[1].rank;

  // House rule: double allowed on any two-card hand (DOA — Double On Any).
  bool get canDouble => cards.length == 2;

  HandModel revealAll() => copyWith(
        cards: cards.map((c) => c.copyWith(faceUp: true)).toList(),
      );
}

enum Suit { hearts, diamonds, clubs, spades }

enum Rank {
  ace,
  two,
  three,
  four,
  five,
  six,
  seven,
  eight,
  nine,
  ten,
  jack,
  queen,
  king,
}

extension SuitDisplay on Suit {
  String get symbol {
    switch (this) {
      case Suit.hearts:
        return '♥';
      case Suit.diamonds:
        return '♦';
      case Suit.clubs:
        return '♣';
      case Suit.spades:
        return '♠';
    }
  }

  String get name {
    switch (this) {
      case Suit.hearts:
        return 'Hearts';
      case Suit.diamonds:
        return 'Diamonds';
      case Suit.clubs:
        return 'Clubs';
      case Suit.spades:
        return 'Spades';
    }
  }

  bool get isRed => this == Suit.hearts || this == Suit.diamonds;
}

extension RankDisplay on Rank {
  String get display {
    switch (this) {
      case Rank.ace:
        return 'A';
      case Rank.two:
        return '2';
      case Rank.three:
        return '3';
      case Rank.four:
        return '4';
      case Rank.five:
        return '5';
      case Rank.six:
        return '6';
      case Rank.seven:
        return '7';
      case Rank.eight:
        return '8';
      case Rank.nine:
        return '9';
      case Rank.ten:
        return '10';
      case Rank.jack:
        return 'J';
      case Rank.queen:
        return 'Q';
      case Rank.king:
        return 'K';
    }
  }

  // Base value used in Hi-Lo counting
  String get hiLoName {
    switch (this) {
      case Rank.ace:
        return 'Ace';
      case Rank.ten:
        return '10';
      case Rank.jack:
        return 'Jack';
      case Rank.queen:
        return 'Queen';
      case Rank.king:
        return 'King';
      default:
        return display;
    }
  }

  // Card point value (Ace = 11, face = 10, others = face)
  int get value {
    switch (this) {
      case Rank.ace:
        return 11;
      case Rank.jack:
      case Rank.queen:
      case Rank.king:
        return 10;
      default:
        return int.parse(display);
    }
  }
}

class CardModel {
  final Suit suit;
  final Rank rank;
  final bool faceUp;

  /// True when this card reached us over the wire with its identity withheld.
  /// Face-down cards are redacted by the sender, so [suit] and [rank] are
  /// meaningless placeholders — never read them, and never count such a card
  /// toward a hand value. Always false for locally dealt cards.
  final bool hidden;

  const CardModel({
    required this.suit,
    required this.rank,
    this.faceUp = true,
    this.hidden = false,
  });

  CardModel copyWith({bool? faceUp, bool? hidden}) => CardModel(
        suit: suit,
        rank: rank,
        faceUp: faceUp ?? this.faceUp,
        hidden: hidden ?? this.hidden,
      );

  /// Compact wire format for online play. Suit/rank are sent as enum indices.
  ///
  /// A face-down card is sent WITHOUT its rank and suit. Previously the hole
  /// card shipped in the clear with only a "draw a card back" flag, so every
  /// guest already held the dealer's answer. Redacting here means the identity
  /// physically never leaves the host until the card is turned over.
  Map<String, dynamic> toJson() => faceUp
      ? {'s': suit.index, 'r': rank.index, 'u': true}
      : const {'u': false, 'h': true};

  factory CardModel.fromJson(Map<String, dynamic> json) {
    if (json['h'] == true || json['s'] == null || json['r'] == null) {
      // Redacted by the sender — a placeholder that renders as a card back.
      return const CardModel(
        suit: Suit.spades,
        rank: Rank.two,
        faceUp: false,
        hidden: true,
      );
    }
    return CardModel(
      suit: Suit.values[json['s'] as int],
      rank: Rank.values[json['r'] as int],
      faceUp: json['u'] as bool? ?? true,
    );
  }

  @override
  String toString() => hidden ? '??' : '${rank.display}${suit.symbol}';
}

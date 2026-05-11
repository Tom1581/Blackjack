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

  const CardModel({required this.suit, required this.rank, this.faceUp = true});

  CardModel copyWith({bool? faceUp}) =>
      CardModel(suit: suit, rank: rank, faceUp: faceUp ?? this.faceUp);

  @override
  String toString() => '${rank.display}${suit.symbol}';
}

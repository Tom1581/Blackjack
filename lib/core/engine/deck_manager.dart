import 'dart:math';
import '../models/card_model.dart';

/// Manages the multi-deck shoe — mirrors create_deck() and cut_deck() in blackjack.py.
class DeckManager {
  final int numDecks;
  final _rng = Random();
  late List<CardModel> _shoe;

  DeckManager({this.numDecks = 6}) {
    _shoe = _buildShoe();
    shuffle();
    cut();
  }

  int get remaining => _shoe.length;
  bool get isEmpty => _shoe.isEmpty;
  int get totalCards => numDecks * 52;
  double get penetration => 1 - (_shoe.length / totalCards);

  /// Draw from the top of the shoe.
  ///
  /// An empty shoe is rebuilt rather than allowed to throw. The cut card sits
  /// at 25% so this needs an extreme round — three spots all splitting to four
  /// hands from a two-deck shoe — but a crash mid-hand is never acceptable.
  /// Callers that keep a count should check [isEmpty] first and reset it.
  CardModel draw({bool faceUp = true}) {
    if (_shoe.isEmpty) reset();
    final card = _shoe.removeLast();
    return card.copyWith(faceUp: faceUp);
  }

  bool get needsReshuffle => _shoe.length < totalCards * 0.25;

  void reset() {
    _shoe = _buildShoe();
    shuffle();
    cut();
  }

  void shuffle() => _shoe.shuffle(_rng);

  /// Pseudo-cut: remove a random 25–75% slice and place it at the back.
  void cut() {
    final lo = (totalCards * 0.25).toInt();
    final hi = (totalCards * 0.75).toInt();
    final cutPoint = lo + _rng.nextInt(hi - lo);
    final top = _shoe.sublist(cutPoint);
    final bottom = _shoe.sublist(0, cutPoint);
    _shoe = [...top, ...bottom];
  }

  List<CardModel> _buildShoe() {
    final deck = <CardModel>[];
    for (final suit in Suit.values) {
      for (final rank in Rank.values) {
        deck.add(CardModel(suit: suit, rank: rank));
      }
    }
    final shoe = <CardModel>[];
    for (int i = 0; i < numDecks; i++) {
      shoe.addAll(deck);
    }
    return shoe;
  }
}

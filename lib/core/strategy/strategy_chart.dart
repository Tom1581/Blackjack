import '../models/card_model.dart';
import '../models/hand_model.dart';
import '../rules/rule_set.dart';
import 'basic_strategy.dart';

/// One cell of a printed strategy card.
enum ChartPlay {
  hit('H'),
  stand('S'),
  double('D'),

  /// Double if allowed, otherwise stand — soft 18 and 19.
  doubleOrStand('Ds'),
  split('P'),

  /// Surrender if allowed, otherwise hit.
  surrenderOrHit('Rh'),

  /// Surrender if allowed, otherwise stand — 17 against an ace under H17.
  surrenderOrStand('Rs'),

  /// Surrender if allowed, otherwise split — eights against an ace, H17.
  surrenderOrSplit('Rp');

  const ChartPlay(this.code);
  final String code;

  bool get isSurrender =>
      this == surrenderOrHit ||
      this == surrenderOrStand ||
      this == surrenderOrSplit;

  bool get isDouble => this == double || this == doubleOrStand;
}

/// The chart the coach is scoring against, laid out as a strategy card.
///
/// Every cell is computed by [BasicStrategy.best] — the same function that
/// grades each decision at the table — so the card can never disagree with
/// the coach.
class StrategyChart {
  const StrategyChart._();

  /// Dealer up-cards in chart order: 2–10, then ace.
  static const dealerUps = <Rank>[
    Rank.two,
    Rank.three,
    Rank.four,
    Rank.five,
    Rank.six,
    Rank.seven,
    Rank.eight,
    Rank.nine,
    Rank.ten,
    Rank.ace,
  ];

  /// Hard rows as printed: 8 stands for "8 or less" and 18 for "18 or more"
  /// — every total in each band plays the same.
  static const hardRows = <int>[8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18];
  static const softRows = <Rank>[
    Rank.two,
    Rank.three,
    Rank.four,
    Rank.five,
    Rank.six,
    Rank.seven,
    Rank.eight,
    Rank.nine,
  ];
  static const pairRows = <Rank>[
    Rank.two,
    Rank.three,
    Rank.four,
    Rank.five,
    Rank.six,
    Rank.seven,
    Rank.eight,
    Rank.nine,
    Rank.ten,
    Rank.ace,
  ];

  static CardModel _c(Rank r, [Suit s = Suit.spades]) =>
      CardModel(suit: s, rank: r);

  static Rank _rankOf(int v) => Rank.values[v - 1];

  /// Two unpaired, ace-free cards totalling [total] (5–19).
  static HandModel hardHand(int total) {
    assert(total >= 5 && total <= 19);
    final int high;
    if (total >= 12) {
      high = 10;
    } else if (total <= 7) {
      high = total - 2;
    } else {
      high = total - (total ~/ 2 - 1);
    }
    final low = total - high;
    return HandModel(
        cards: [_c(_rankOf(high)), _c(_rankOf(low), Suit.hearts)]);
  }

  static HandModel softHand(Rank kicker) =>
      HandModel(cards: [_c(Rank.ace), _c(kicker, Suit.hearts)]);

  static HandModel pairHand(Rank rank) =>
      HandModel(cards: [_c(rank), _c(rank, Suit.hearts)]);

  /// The printed cell for a two-card [hand] against [dealerUp].
  static ChartPlay cell(
    HandModel hand,
    Rank dealerUp,
    RuleSet rules, {
    bool pairs = false,
    int decks = 6,
  }) {
    final up = _c(dealerUp, Suit.clubs);
    StrategyMove play({required bool dbl, required bool surrender}) =>
        BasicStrategy.best(
          hand: hand,
          dealerUp: up,
          canDouble: dbl,
          canSplit: pairs,
          canSurrender: surrender,
          rules: rules,
          decks: decks,
        );

    final best = play(dbl: true, surrender: rules.lateSurrender);
    switch (best) {
      case StrategyMove.split:
        return ChartPlay.split;
      case StrategyMove.hit:
        return ChartPlay.hit;
      case StrategyMove.stand:
        return ChartPlay.stand;
      case StrategyMove.double:
        return play(dbl: false, surrender: rules.lateSurrender) ==
                StrategyMove.stand
            ? ChartPlay.doubleOrStand
            : ChartPlay.double;
      case StrategyMove.surrender:
        switch (play(dbl: true, surrender: false)) {
          case StrategyMove.stand:
            return ChartPlay.surrenderOrStand;
          case StrategyMove.split:
            return ChartPlay.surrenderOrSplit;
          default:
            return ChartPlay.surrenderOrHit;
        }
    }
  }
}

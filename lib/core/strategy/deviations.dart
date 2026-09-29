import '../models/card_model.dart';
import '../models/hand_model.dart';
import '../rules/rule_set.dart';
import 'basic_strategy.dart';

/// Which published list an index play belongs to.
enum IndexSet {
  /// Don Schlesinger's Illustrious 18 — the eighteen count-based departures
  /// from basic strategy worth the most to a Hi-Lo counter.
  illustrious18('Illustrious 18'),

  /// The four late-surrender departures that go with them.
  fab4('Fab 4');

  const IndexSet(this.label);
  final String label;
}

/// One Hi-Lo index play: at a true count of [index] or higher the player
/// makes [atOrAbove]; below it, [below].
///
/// Both halves are written out, so a play that basic strategy already makes
/// (12 v 4 stands) and one it does not (16 v 10 hits) read the same way.
class IndexPlay {
  final IndexSet set;

  /// "16 v 10", "10,10 v 6".
  final String label;

  /// Hard total the play is for; for a pair, the pair card's value.
  final int total;
  final bool pair;

  /// Dealer up-card value: 2–10, or 11 for an ace.
  final int up;
  final int index;
  final StrategyMove atOrAbove;
  final StrategyMove below;

  const IndexPlay({
    required this.set,
    required this.label,
    required this.total,
    required this.up,
    required this.index,
    required this.atOrAbove,
    required this.below,
    this.pair = false,
  });

  /// The play at true count [trueCount].
  StrategyMove playAt(double trueCount) =>
      trueCount >= index ? atOrAbove : below;

  /// "Stand at +4 or more", "Hit below −1".
  String get rule {
    final sign = index > 0 ? '+$index' : (index < 0 ? '−${-index}' : '0');
    return '${atOrAbove.label} at $sign or higher, otherwise ${below.label}';
  }
}

/// A decision graded against the count rather than the basic chart.
class IndexDecision {
  final IndexPlay play;
  final StrategyMove move;

  const IndexDecision(this.play, this.move);

  /// True when the count moved the answer off the basic-strategy play.
  bool departsFrom(StrategyMove basic) => move != basic;
}

/// The Hi-Lo index plays the coach knows: the Illustrious 18 and the Fab 4.
///
/// **Sources.** The S17 numbers are Schlesinger's, as published by the Wizard
/// of Odds for six decks, S17, DAS, late surrender. A dealer who hits soft 17
/// shifts four of them — 11 v A (−1), 10 v A (+3), 12 v 6 (−3) and the 15 v A
/// surrender (−1) — and the H17 set uses those, as published for six decks,
/// H17, DAS, late surrender.
///
/// **Scope.** These are multi-deck numbers. A two-deck game has its own
/// indices, so [lookup] returns nothing there rather than teach the wrong
/// ones.
///
/// **True count.** Compared as `trueCount >= index` on the unrounded true
/// count, which is the same as flooring it: +2.9 is still "+2" and does not
/// reach an index of +3.
class Deviations {
  const Deviations._();

  /// Index plays only apply to shoes this big or bigger.
  static const minDecks = 4;

  /// Take insurance at this true count or higher.
  static const insuranceIndex = 3;

  static bool shouldInsure(double trueCount) => trueCount >= insuranceIndex;

  static const _h = StrategyMove.hit;
  static const _s = StrategyMove.stand;
  static const _d = StrategyMove.double;
  static const _p = StrategyMove.split;
  static const _r = StrategyMove.surrender;
  static const _i18 = IndexSet.illustrious18;

  /// The Illustrious 18 without insurance (see [insuranceIndex]), for a
  /// dealer who stands (S17) or hits (H17) soft 17.
  static List<IndexPlay> illustrious18({required bool h17}) => [
        const IndexPlay(set: _i18, label: '16 v 10', total: 16, up: 10,
            index: 0, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '15 v 10', total: 15, up: 10,
            index: 4, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '10,10 v 5', total: 10, pair: true,
            up: 5, index: 5, atOrAbove: _p, below: _s),
        const IndexPlay(set: _i18, label: '10,10 v 6', total: 10, pair: true,
            up: 6, index: 4, atOrAbove: _p, below: _s),
        const IndexPlay(set: _i18, label: '10 v 10', total: 10, up: 10,
            index: 4, atOrAbove: _d, below: _h),
        const IndexPlay(set: _i18, label: '12 v 3', total: 12, up: 3,
            index: 2, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '12 v 2', total: 12, up: 2,
            index: 3, atOrAbove: _s, below: _h),
        IndexPlay(set: _i18, label: '11 v A', total: 11, up: 11,
            index: h17 ? -1 : 1, atOrAbove: _d, below: _h),
        const IndexPlay(set: _i18, label: '9 v 2', total: 9, up: 2,
            index: 1, atOrAbove: _d, below: _h),
        IndexPlay(set: _i18, label: '10 v A', total: 10, up: 11,
            index: h17 ? 3 : 4, atOrAbove: _d, below: _h),
        const IndexPlay(set: _i18, label: '9 v 7', total: 9, up: 7,
            index: 3, atOrAbove: _d, below: _h),
        const IndexPlay(set: _i18, label: '16 v 9', total: 16, up: 9,
            index: 5, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '13 v 2', total: 13, up: 2,
            index: -1, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '12 v 4', total: 12, up: 4,
            index: 0, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '12 v 5', total: 12, up: 5,
            index: -2, atOrAbove: _s, below: _h),
        IndexPlay(set: _i18, label: '12 v 6', total: 12, up: 6,
            index: h17 ? -3 : -1, atOrAbove: _s, below: _h),
        const IndexPlay(set: _i18, label: '13 v 3', total: 13, up: 3,
            index: -2, atOrAbove: _s, below: _h),
      ];

  /// The Fab 4 late-surrender plays.
  static List<IndexPlay> fab4({required bool h17}) => [
        const IndexPlay(set: IndexSet.fab4, label: '14 v 10', total: 14,
            up: 10, index: 3, atOrAbove: _r, below: _h),
        const IndexPlay(set: IndexSet.fab4, label: '15 v 10', total: 15,
            up: 10, index: 0, atOrAbove: _r, below: _h),
        const IndexPlay(set: IndexSet.fab4, label: '15 v 9', total: 15,
            up: 9, index: 2, atOrAbove: _r, below: _h),
        IndexPlay(set: IndexSet.fab4, label: '15 v A', total: 15, up: 11,
            index: h17 ? -1 : 1, atOrAbove: _r, below: _h),
      ];

  /// The index play that governs [hand] against [dealerUp], if any.
  ///
  /// An entry only applies when it is choosing between the two plays it
  /// names *and* basic strategy is already making one of them. That rule is
  /// what keeps the lists from fighting each other and the chart:
  /// - 8,8 v 10 is a split, so the 16 v 10 stand index never touches it;
  /// - with surrender on, 16 v 10 is a surrender, so again the stand index
  ///   stays out, while 15 v 10 is governed by its Fab 4 surrender index;
  /// - a double index needs a hand that may be doubled, a split index a pair
  ///   that may be split, a surrender index a hand that may be surrendered.
  static IndexDecision? lookup({
    required HandModel hand,
    required CardModel dealerUp,
    required double trueCount,
    required RuleSet rules,
    required int decks,
    required bool canDouble,
    required bool canSplit,
    required bool canSurrender,
  }) {
    if (decks < minDecks) return null;
    if (hand.isSoft) return null;
    final up = BasicStrategy.upCardValue(dealerUp);
    final h17 = rules.dealerHitsSoft17;
    final surrenderOffered = canSurrender && rules.lateSurrender;

    final basic = BasicStrategy.best(
      hand: hand,
      dealerUp: dealerUp,
      canDouble: canDouble,
      canSplit: canSplit,
      canSurrender: surrenderOffered,
      rules: rules,
      decks: decks,
    );

    final splittable = canSplit && hand.isPair;
    final candidates = [
      if (surrenderOffered) ...fab4(h17: h17),
      ...illustrious18(h17: h17),
    ];
    for (final play in candidates) {
      if (play.up != up) continue;
      if (play.pair) {
        if (!splittable || hand.cards.first.rank.value != play.total) continue;
      } else {
        if (hand.value != play.total) continue;
      }
      if (basic != play.atOrAbove && basic != play.below) continue;

      final wants = play.playAt(trueCount);
      if (wants == StrategyMove.double && !canDouble) continue;
      if (wants == StrategyMove.split && !splittable) continue;
      if (wants == StrategyMove.surrender && !surrenderOffered) continue;
      return IndexDecision(play, wants);
    }
    return null;
  }

  /// The correct play counting the cards: the index play where one applies,
  /// basic strategy everywhere else.
  static StrategyMove best({
    required HandModel hand,
    required CardModel dealerUp,
    required double trueCount,
    required RuleSet rules,
    required int decks,
    required bool canDouble,
    required bool canSplit,
    required bool canSurrender,
  }) {
    final decision = lookup(
      hand: hand,
      dealerUp: dealerUp,
      trueCount: trueCount,
      rules: rules,
      decks: decks,
      canDouble: canDouble,
      canSplit: canSplit,
      canSurrender: canSurrender,
    );
    return decision?.move ??
        BasicStrategy.best(
          hand: hand,
          dealerUp: dealerUp,
          canDouble: canDouble,
          canSplit: canSplit,
          canSurrender: canSurrender,
          rules: rules,
          decks: decks,
        );
  }
}

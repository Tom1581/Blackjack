import 'package:flutter/foundation.dart';

/// Which totals a table lets you double.
enum DoubleRule {
  /// Double on any two cards — the player-friendly standard.
  anyTwo('Any two cards'),

  /// Hard 9, 10 and 11 only. No soft doubles.
  nineToEleven('9–11 only'),

  /// Hard 10 and 11 only — the most restrictive common rule.
  tenAndEleven('10–11 only');

  const DoubleRule(this.label);
  final String label;
}

/// The rules of a particular blackjack table.
///
/// Strategy is not universal: the correct play changes with the house rules,
/// which is exactly why a trainer has to know which table it is teaching. The
/// chart used to be hard-coded to one rule set, so a player practising against
/// any other table was being taught the wrong answer.
@immutable
class RuleSet {
  /// Stable key used for persistence.
  final String id;

  final String name;

  /// One line for the picker, saying what actually differs.
  final String blurb;

  /// Dealer draws to soft 17 rather than standing on it. Worse for the player,
  /// and changes three cells of the chart.
  final bool dealerHitsSoft17;

  /// Doubling is allowed on a hand produced by a split. Changes which pairs
  /// are worth splitting.
  final bool doubleAfterSplit;

  final DoubleRule doubleRule;

  /// Profit multiplier on a natural. 1.5 is 3:2; 1.2 is the 6:5 that quietly
  /// costs the player about 1.4% of every bankroll.
  final double blackjackPayout;

  /// Total hands one seat may end up with after splitting.
  final int maxSplitHands;

  /// Split aces may be split again.
  final bool resplitAces;

  /// Late surrender is offered: on the first two cards of a dealt hand, after
  /// the dealer has checked for blackjack, the player may give the hand up
  /// for half the bet back.
  final bool lateSurrender;

  const RuleSet({
    required this.id,
    required this.name,
    required this.blurb,
    this.dealerHitsSoft17 = true,
    this.doubleAfterSplit = true,
    this.doubleRule = DoubleRule.anyTwo,
    this.blackjackPayout = 1.5,
    this.maxSplitHands = 4,
    this.resplitAces = false,
    this.lateSurrender = false,
  });

  /// Whether this table allows doubling a hand of [total].
  ///
  /// A restricted table does not merely make doubling rarer — it removes every
  /// soft double, because a soft total is never 9, 10 or 11.
  bool allowsDoubleOn(int total, {required bool isSoft}) {
    switch (doubleRule) {
      case DoubleRule.anyTwo:
        return true;
      case DoubleRule.nineToEleven:
        return !isSoft && total >= 9 && total <= 11;
      case DoubleRule.tenAndEleven:
        return !isSoft && total >= 10 && total <= 11;
    }
  }

  /// Blackjack payout written the way a table felt writes it.
  String get payoutLabel {
    if ((blackjackPayout - 1.5).abs() < 0.001) return '3:2';
    if ((blackjackPayout - 1.2).abs() < 0.001) return '6:5';
    return '${blackjackPayout.toStringAsFixed(2)}×';
  }

  String get dealerLabel => dealerHitsSoft17 ? 'H17' : 'S17';

  /// Short summary for the settings row: "H17 · DAS · 3:2".
  String get summary => [
        dealerLabel,
        if (doubleAfterSplit) 'DAS' else 'no DAS',
        if (lateSurrender) 'LS',
        payoutLabel,
        if (doubleRule != DoubleRule.anyTwo) doubleRule.label,
      ].join(' · ');

  /// True when this table is materially worse than the standard game, so the
  /// UI can say so rather than letting someone practise on it unaware.
  bool get isUnfavourable => blackjackPayout < 1.5;

  RuleSet copyWith({
    String? id,
    String? name,
    String? blurb,
    bool? dealerHitsSoft17,
    bool? doubleAfterSplit,
    DoubleRule? doubleRule,
    double? blackjackPayout,
    int? maxSplitHands,
    bool? resplitAces,
    bool? lateSurrender,
  }) =>
      RuleSet(
        id: id ?? this.id,
        name: name ?? this.name,
        blurb: blurb ?? this.blurb,
        dealerHitsSoft17: dealerHitsSoft17 ?? this.dealerHitsSoft17,
        doubleAfterSplit: doubleAfterSplit ?? this.doubleAfterSplit,
        doubleRule: doubleRule ?? this.doubleRule,
        blackjackPayout: blackjackPayout ?? this.blackjackPayout,
        maxSplitHands: maxSplitHands ?? this.maxSplitHands,
        resplitAces: resplitAces ?? this.resplitAces,
        lateSurrender: lateSurrender ?? this.lateSurrender,
      );

  // ─── Presets ─────────────────────────────────────────────────────────────

  /// What the app has always played, and still the default: nothing changes
  /// for anyone who never opens the rules picker.
  static const sixDeckH17 = RuleSet(
    id: 'six_deck_h17',
    name: '6-Deck H17',
    blurb: 'The common modern shoe game. Dealer draws to soft 17.',
  );

  static const sixDeckS17 = RuleSet(
    id: 'six_deck_s17',
    name: '6-Deck S17',
    blurb: 'Dealer stands on soft 17 — better for you, and three chart cells '
        'change.',
    dealerHitsSoft17: false,
  );

  static const eightDeckS17 = RuleSet(
    id: 'eight_deck_s17',
    name: 'Atlantic City',
    blurb: 'Dealer stands on soft 17, double after split. Usually dealt '
        'from eight decks — pick the 8 D shoe to match.',
    dealerHitsSoft17: false,
  );

  static const sixDeckNoDas = RuleSet(
    id: 'six_deck_no_das',
    name: 'No Double After Split',
    blurb: 'Splitting gets stingier when you cannot double afterwards.',
    doubleAfterSplit: false,
  );

  static const restrictedDouble = RuleSet(
    id: 'restricted_double',
    name: 'Hard 9–11 Doubles',
    blurb: 'Doubling is limited to hard 9, 10 and 11. No soft doubles at all.',
    doubleRule: DoubleRule.nineToEleven,
  );

  static const sixDeckH17Surrender = RuleSet(
    id: 'six_deck_h17_ls',
    name: 'H17 + Surrender',
    blurb: 'Late surrender: give up half your bet on the worst hands, after '
        'the dealer checks for blackjack.',
    lateSurrender: true,
  );

  static const sixDeckS17Surrender = RuleSet(
    id: 'six_deck_s17_ls',
    name: 'S17 + Surrender',
    blurb: 'The best common shoe game: dealer stands on soft 17, and late '
        'surrender is allowed.',
    dealerHitsSoft17: false,
    lateSurrender: true,
  );

  static const sixFive = RuleSet(
    id: 'six_five',
    name: '6:5 Blackjack',
    blurb: 'The same game paying 6:5 on a natural. Strategy is unchanged; the '
        'table just takes far more of your money.',
    blackjackPayout: 1.2,
  );

  /// Presets offered in the picker.
  ///
  /// House rules only — the number of decks is the shoe setting, and the
  /// coach reads both (two decks has its own chart). Single deck is not
  /// offered: its chart is different again and not verified here.
  static const presets = <RuleSet>[
    sixDeckH17,
    sixDeckS17,
    sixDeckH17Surrender,
    sixDeckS17Surrender,
    eightDeckS17,
    sixDeckNoDas,
    restrictedDouble,
    sixFive,
  ];

  static const fallback = sixDeckH17;

  static RuleSet byId(String? id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      other is RuleSet &&
      other.id == id &&
      other.dealerHitsSoft17 == dealerHitsSoft17 &&
      other.doubleAfterSplit == doubleAfterSplit &&
      other.doubleRule == doubleRule &&
      other.blackjackPayout == blackjackPayout &&
      other.maxSplitHands == maxSplitHands &&
      other.resplitAces == resplitAces &&
      other.lateSurrender == lateSurrender;

  @override
  int get hashCode => Object.hash(id, dealerHitsSoft17, doubleAfterSplit,
      doubleRule, blackjackPayout, maxSplitHands, resplitAces, lateSurrender);

  @override
  String toString() => '$name ($summary)';
}

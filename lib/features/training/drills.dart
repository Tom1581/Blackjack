import 'dart:math';

import '../../core/models/card_model.dart';
import '../../core/models/hand_model.dart';
import '../../core/rules/rule_set.dart';
import '../../core/strategy/basic_strategy.dart';
import '../../core/strategy/deviations.dart';
import '../../core/strategy/strategy_coach.dart';

/// The Hi-Lo tag of one card: +1 for 2–6, 0 for 7–9, −1 for tens and aces.
int hiLoTag(CardModel card) {
  final v = card.rank.value;
  if (v <= 6) return 1;
  if (v <= 9) return 0;
  return -1;
}

int runningCountOf(Iterable<CardModel> cards) =>
    cards.fold(0, (sum, c) => sum + hiLoTag(c));

List<CardModel> _shuffledDeck(Random rng) => [
      for (final suit in Suit.values)
        for (final rank in Rank.values) CardModel(suit: suit, rank: rank),
    ]..shuffle(rng);

// ─── Speed count ───────────────────────────────────────────────────────────

enum SpeedCountLength {
  /// Twenty cards — a warm-up.
  short('20 cards', 'A quick run to warm up'),

  /// A full deck with one to three cards secretly held back. A complete deck
  /// always counts to zero, so the count at the end is exactly what the
  /// missing cards were worth — the classic deck-countdown drill.
  deck('Deck countdown', 'A full deck with 1–3 cards held back');

  const SpeedCountLength(this.label, this.blurb);
  final String label;
  final String blurb;
}

enum SpeedCountPace {
  steady('Steady', Duration(milliseconds: 1100)),
  brisk('Brisk', Duration(milliseconds: 750)),
  casino('Casino', Duration(milliseconds: 480));

  const SpeedCountPace(this.label, this.perCard);
  final String label;
  final Duration perCard;
}

class SpeedCountRound {
  final List<CardModel> cards;

  /// Cards dealt out of sight in a deck countdown. Empty for a short run.
  final List<CardModel> heldBack;

  const SpeedCountRound({required this.cards, this.heldBack = const []});

  /// The running count after every card shown.
  int get answer => runningCountOf(cards);

  factory SpeedCountRound.generate(SpeedCountLength length, {Random? rng}) {
    final r = rng ?? Random();
    final deck = _shuffledDeck(r);
    switch (length) {
      case SpeedCountLength.short:
        return SpeedCountRound(cards: deck.take(20).toList());
      case SpeedCountLength.deck:
        final hidden = 1 + r.nextInt(3);
        return SpeedCountRound(
          cards: deck.sublist(hidden),
          heldBack: deck.sublist(0, hidden),
        );
    }
  }
}

// ─── True count conversion ─────────────────────────────────────────────────

class TrueCountQuestion {
  final int runningCount;

  /// Decks still in the shoe, in half decks.
  final double decksLeft;

  /// Total decks in the shoe, for drawing the discard tray.
  final int shoeDecks;

  /// Four choices, one of which is [answer].
  final List<int> options;

  const TrueCountQuestion({
    required this.runningCount,
    required this.decksLeft,
    required this.shoeDecks,
    required this.options,
  });

  /// Running count divided by decks left, to the nearest whole number.
  int get answer => (runningCount / decksLeft).round();

  double get penetration => 1 - decksLeft / shoeDecks;

  /// A question with an unambiguous answer: the division never lands exactly
  /// on a half, where "nearest" would be a coin toss.
  factory TrueCountQuestion.generate({Random? rng, int shoeDecks = 6}) {
    final r = rng ?? Random();
    while (true) {
      final halves = 1 + r.nextInt(shoeDecks * 2 - 1); // 0.5 … shoeDecks-0.5
      final decks = halves / 2;
      final rc = r.nextInt(29) - 12; // −12 … +16, skewed up like real shoes
      final exact = rc / decks;
      final frac = (exact - exact.truncate()).abs();
      if ((frac - 0.5).abs() < 1e-9) continue;
      if (exact.abs() > 12) continue;
      final answer = exact.round();
      final options = <int>{answer};
      final offsets = [-2, -1, 1, 2]..shuffle(r);
      for (final o in offsets) {
        if (options.length == 4) break;
        options.add(answer + o);
      }
      final list = options.toList()..shuffle(r);
      return TrueCountQuestion(
        runningCount: rc,
        decksLeft: decks,
        shoeDecks: shoeDecks,
        options: list,
      );
    }
  }
}

// ─── Basic strategy flash drill ────────────────────────────────────────────

enum StrategyDrillFocus {
  all('All hands'),
  hard('Hard totals'),
  soft('Soft totals'),
  pairs('Pairs'),
  mistakes('My mistakes');

  const StrategyDrillFocus(this.label);
  final String label;
}

class StrategyDrillHand {
  final HandModel hand;
  final CardModel dealerUp;

  const StrategyDrillHand(this.hand, this.dealerUp);

  bool get isPair => hand.isPair;

  /// The right play at a table with [rules] and a [decks]-deck shoe: a fresh
  /// two-card hand, so doubling is on the table, a pair may be split, and
  /// surrender is offered wherever the table allows it.
  StrategyMove answer(RuleSet rules, {int decks = 6}) => BasicStrategy.best(
        hand: hand,
        dealerUp: dealerUp,
        canDouble: true,
        canSplit: true,
        canSurrender: rules.lateSurrender,
        rules: rules,
        decks: decks,
      );

  static const _suits = Suit.values;

  static CardModel _card(Random r, int value) {
    final Rank rank;
    if (value == 11) {
      rank = Rank.ace;
    } else if (value == 10) {
      rank = const [Rank.ten, Rank.jack, Rank.queen, Rank.king][r.nextInt(4)];
    } else {
      rank = Rank.values[value - 1];
    }
    return CardModel(suit: _suits[r.nextInt(4)], rank: rank);
  }

  /// Two cards of the same rank — a king and a queen are both ten, but only
  /// a matching pair may be split.
  static HandModel _pair(Random r, int value) {
    final first = _card(r, value);
    final second = CardModel(
      suit: _suits[(first.suit.index + 1 + r.nextInt(3)) % 4],
      rank: first.rank,
    );
    return HandModel(cards: [first, second]);
  }

  static int _randomUp(Random r) {
    // Tens are four times as common as any other up-card, as in a real shoe.
    final roll = r.nextInt(13);
    if (roll >= 9) return 10;
    return roll == 8 ? 11 : roll + 2;
  }

  /// A random hand. [StrategyDrillFocus.all] weights the three kinds so the
  /// drill spends most of its time where players actually go wrong.
  factory StrategyDrillHand.random(StrategyDrillFocus focus, {Random? rng}) {
    final r = rng ?? Random();
    var kind = focus;
    if (focus == StrategyDrillFocus.all ||
        focus == StrategyDrillFocus.mistakes) {
      final roll = r.nextInt(10);
      kind = roll < 5
          ? StrategyDrillFocus.hard
          : roll < 8
              ? StrategyDrillFocus.soft
              : StrategyDrillFocus.pairs;
    }
    final up = _card(r, _randomUp(r));
    switch (kind) {
      case StrategyDrillFocus.soft:
        final kicker = 2 + r.nextInt(8); // A,2 … A,9
        return StrategyDrillHand(
          HandModel(cards: [_card(r, 11), _card(r, kicker)]),
          up,
        );
      case StrategyDrillFocus.pairs:
        return StrategyDrillHand(_pair(r, 2 + r.nextInt(10)), up); // 2 … A
      default:
        // Hard 8–17 from two unpaired, ace-free cards.
        while (true) {
          final a = 2 + r.nextInt(9);
          final b = 2 + r.nextInt(9);
          final total = a + b;
          if (a == b || total < 8 || total > 17) continue;
          return StrategyDrillHand(
            HandModel(cards: [_card(r, a), _card(r, b)]),
            up,
          );
        }
    }
  }

  /// Rebuild a hand from a most-missed label such as "Hard 16 vs 10",
  /// "Soft 18 vs A" or "8,8 vs 6". Null for anything it cannot read.
  static StrategyDrillHand? fromSpot(String spot, {Random? rng}) {
    final r = rng ?? Random();
    final parts = spot.split(' vs ');
    if (parts.length != 2) return null;
    final upValue = parts[1] == 'A' ? 11 : int.tryParse(parts[1]);
    if (upValue == null || upValue < 2 || upValue > 11) return null;
    final up = _card(r, upValue);
    final left = parts[0];

    if (left.contains(',')) {
      final raw = left.split(',').first;
      final v = raw == 'A' ? 11 : int.tryParse(raw);
      if (v == null || v < 2 || v > 11) return null;
      return StrategyDrillHand(_pair(r, v), up);
    }
    final words = left.split(' ');
    if (words.length != 2) return null;
    final total = int.tryParse(words[1]);
    if (total == null) return null;
    if (words[0] == 'Soft') {
      final kicker = total - 11;
      if (kicker < 2 || kicker > 9) return null;
      return StrategyDrillHand(
        HandModel(cards: [_card(r, 11), _card(r, kicker)]),
        up,
      );
    }
    if (words[0] == 'Hard') {
      // Two unpaired, ace-free cards — a hard total the chart treats the same
      // however it was made.
      for (var a = 10; a >= 2; a--) {
        final b = total - a;
        if (b >= 2 && b <= 10 && b != a) {
          return StrategyDrillHand(
            HandModel(cards: [_card(r, a), _card(r, b)]),
            up,
          );
        }
      }
      // Totals only reachable with three cards: fall back to a pair-free
      // three-card hand.
      if (total >= 18 && total <= 21) {
        return StrategyDrillHand(
          HandModel(cards: [_card(r, 10), _card(r, 5), _card(r, total - 15)]),
          up,
        );
      }
    }
    return null;
  }

  /// The chart category this hand is scored under.
  StrategyCategory get category => hand.isPair
      ? StrategyCategory.pair
      : hand.isSoft
          ? StrategyCategory.soft
          : StrategyCategory.hard;
}

// ─── Index plays (Illustrious 18 / Fab 4) ──────────────────────────────────

/// One index-play question: a hand, the dealer's card and a true count.
/// [play] is null for an insurance question.
class IndexDrillQuestion {
  final IndexPlay? play;
  final HandModel hand;
  final CardModel dealerUp;
  final double trueCount;

  /// The rules the question is asked under: the player's own soft-17 rule,
  /// with late surrender switched on for a Fab 4 question.
  final RuleSet rules;

  const IndexDrillQuestion({
    required this.play,
    required this.hand,
    required this.dealerUp,
    required this.trueCount,
    required this.rules,
  });

  bool get isInsurance => play == null;
  bool get surrenderOffered => rules.lateSurrender;

  /// The right play for a hand question.
  StrategyMove get answer => Deviations.best(
        hand: hand,
        dealerUp: dealerUp,
        trueCount: trueCount,
        rules: rules,
        decks: 6,
        canDouble: true,
        canSplit: true,
        canSurrender: surrenderOffered,
      );

  /// The right insurance decision.
  bool get insure => Deviations.shouldInsure(trueCount);

  /// The index play that decides this hand, for the explanation.
  IndexDecision? get decision => Deviations.lookup(
        hand: hand,
        dealerUp: dealerUp,
        trueCount: trueCount,
        rules: rules,
        decks: 6,
        canDouble: true,
        canSplit: true,
        canSurrender: surrenderOffered,
      );

  /// A question on a random index play, at a true count within three of its
  /// index — the only counts where the answer is in doubt — to one decimal,
  /// so the floor rule gets tested too (+2.9 does not reach +3).
  factory IndexDrillQuestion.random({required RuleSet rules, Random? rng}) {
    final r = rng ?? Random();
    final h17 = rules.dealerHitsSoft17;
    final plays = [
      ...Deviations.illustrious18(h17: h17),
      ...Deviations.fab4(h17: h17),
    ];
    // One slot in nineteen is insurance, the most valuable index of all.
    final pick = r.nextInt(plays.length + 1);
    final offset = r.nextInt(61) / 10 - 3.0; // −3.0 … +3.0
    if (pick == plays.length) {
      return IndexDrillQuestion(
        play: null,
        hand: HandModel(cards: [
          StrategyDrillHand._card(r, 10),
          StrategyDrillHand._card(r, 7),
        ]),
        dealerUp: const CardModel(suit: Suit.spades, rank: Rank.ace),
        trueCount: Deviations.insuranceIndex + offset,
        rules: rules,
      );
    }
    final play = plays[pick];
    final fab4 = play.set == IndexSet.fab4;
    final HandModel hand;
    if (play.pair) {
      hand = StrategyDrillHand._pair(r, play.total);
    } else {
      // Two unpaired cards, a ten where possible — the composition the index
      // was built for.
      final high = play.total >= 12 ? 10 : play.total - (play.total ~/ 2 - 1);
      hand = HandModel(cards: [
        StrategyDrillHand._card(r, high),
        StrategyDrillHand._card(r, play.total - high),
      ]);
    }
    return IndexDrillQuestion(
      play: play,
      hand: hand,
      dealerUp: StrategyDrillHand._card(r, play.up),
      trueCount: play.index + offset,
      // A Fab 4 question is asked at a surrender table and an Illustrious 18
      // one at a table without, so the play being tested is the one that
      // governs the hand (15 v 10 is a surrender index with surrender on).
      rules: rules.copyWith(lateSurrender: fab4),
    );
  }
}

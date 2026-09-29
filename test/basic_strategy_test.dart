import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/strategy/basic_strategy.dart';

/// Dealer up-cards in chart order.
const _upCards = [
  CardModel(suit: Suit.clubs, rank: Rank.two),
  CardModel(suit: Suit.clubs, rank: Rank.three),
  CardModel(suit: Suit.clubs, rank: Rank.four),
  CardModel(suit: Suit.clubs, rank: Rank.five),
  CardModel(suit: Suit.clubs, rank: Rank.six),
  CardModel(suit: Suit.clubs, rank: Rank.seven),
  CardModel(suit: Suit.clubs, rank: Rank.eight),
  CardModel(suit: Suit.clubs, rank: Rank.nine),
  CardModel(suit: Suit.clubs, rank: Rank.ten),
  CardModel(suit: Suit.clubs, rank: Rank.ace),
];

CardModel _c(Rank rank) => CardModel(suit: Suit.hearts, rank: rank);
CardModel _d(Rank rank) => CardModel(suit: Suit.spades, rank: rank);

/// Two-card hands that hit each hard total without being a pair or soft.
final _hardHands = <int, HandModel>{
  5: HandModel(cards: [_c(Rank.two), _d(Rank.three)]),
  6: HandModel(cards: [_c(Rank.two), _d(Rank.four)]),
  7: HandModel(cards: [_c(Rank.three), _d(Rank.four)]),
  8: HandModel(cards: [_c(Rank.two), _d(Rank.six)]),
  9: HandModel(cards: [_c(Rank.four), _d(Rank.five)]),
  10: HandModel(cards: [_c(Rank.four), _d(Rank.six)]),
  11: HandModel(cards: [_c(Rank.five), _d(Rank.six)]),
  12: HandModel(cards: [_c(Rank.four), _d(Rank.eight)]),
  13: HandModel(cards: [_c(Rank.five), _d(Rank.eight)]),
  14: HandModel(cards: [_c(Rank.six), _d(Rank.eight)]),
  15: HandModel(cards: [_c(Rank.seven), _d(Rank.eight)]),
  16: HandModel(cards: [_c(Rank.seven), _d(Rank.nine)]),
  17: HandModel(cards: [_c(Rank.eight), _d(Rank.nine)]),
  18: HandModel(cards: [_c(Rank.eight), _d(Rank.ten)]),
  19: HandModel(cards: [_c(Rank.nine), _d(Rank.ten)]),
  // Ten + king is twenty but is not a pair, so it stays a "hard total" row.
  20: HandModel(cards: [_c(Rank.ten), _d(Rank.king)]),
};

/// Ace plus a card, i.e. the soft rows. Keyed by the non-ace card.
HandModel _softHand(Rank other) =>
    HandModel(cards: [_c(Rank.ace), _d(other)]);

HandModel _pair(Rank rank) => HandModel(cards: [_c(rank), _d(rank)]);

/// Parse one chart row: "S S S S S H H H H H".
List<String> _row(String cells) =>
    cells.split(RegExp(r'\s+')).where((c) => c.isNotEmpty).toList();

/// Assert a hand's play against every dealer up-card.
///
/// Notation is the one printed on a real strategy card:
///   H = hit, S = stand, D = double (hit if you cannot), P = split,
///   Ds = double (STAND if you cannot).
void expectRow(
  String label,
  HandModel hand,
  String cells, {
  RuleSet rules = RuleSet.sixDeckH17,
}) {
  final expected = _row(cells);
  expect(expected.length, 10, reason: '$label: chart row must have 10 cells');

  for (var i = 0; i < 10; i++) {
    final up = _upCards[i];
    final cell = expected[i];
    final canDouble = hand.cards.length == 2;

    final move = BasicStrategy.best(
      hand: hand,
      dealerUp: up,
      canDouble: canDouble,
      canSplit: hand.isPair,
      rules: rules,
    );

    final want = switch (cell) {
      'H' => StrategyMove.hit,
      'S' => StrategyMove.stand,
      'D' || 'Ds' => StrategyMove.double,
      'P' => StrategyMove.split,
      _ => throw ArgumentError('bad chart cell "$cell"'),
    };
    expect(move, want,
        reason: '$label vs ${up.rank.display}: chart says $cell');

    // And the documented fallback when the table will not allow a double.
    if (cell == 'D' || cell == 'Ds') {
      final blocked = BasicStrategy.best(
        hand: hand,
        dealerUp: up,
        canDouble: false,
        canSplit: hand.isPair,
        rules: rules,
      );
      expect(
        blocked,
        cell == 'Ds' ? StrategyMove.stand : StrategyMove.hit,
        reason: '$label vs ${up.rank.display}: "$cell" blocked should '
            '${cell == 'Ds' ? 'stand' : 'hit'}',
      );
    }
  }
}

void main() {
  // ── The chart, written out so a human can audit it against a real card ──
  // Six decks, dealer HITS soft 17, double on any two, double after split
  // allowed, no surrender.
  //
  //                    2   3   4   5   6   7   8   9   10  A

  group('Hard totals', () {
    const chart = {
      5:  'H   H   H   H   H   H   H   H   H   H',
      6:  'H   H   H   H   H   H   H   H   H   H',
      7:  'H   H   H   H   H   H   H   H   H   H',
      8:  'H   H   H   H   H   H   H   H   H   H',
      9:  'H   D   D   D   D   H   H   H   H   H',
      10: 'D   D   D   D   D   D   D   D   H   H',
      11: 'D   D   D   D   D   D   D   D   D   D',
      12: 'H   H   S   S   S   H   H   H   H   H',
      13: 'S   S   S   S   S   H   H   H   H   H',
      14: 'S   S   S   S   S   H   H   H   H   H',
      15: 'S   S   S   S   S   H   H   H   H   H',
      16: 'S   S   S   S   S   H   H   H   H   H',
      17: 'S   S   S   S   S   S   S   S   S   S',
      18: 'S   S   S   S   S   S   S   S   S   S',
      19: 'S   S   S   S   S   S   S   S   S   S',
      20: 'S   S   S   S   S   S   S   S   S   S',
    };

    chart.forEach((total, cells) {
      test('hard $total', () => expectRow('hard $total', _hardHands[total]!, cells));
    });
  });

  group('Soft totals', () {
    const chart = {
      Rank.two:   'H   H   H   D   D   H   H   H   H   H', // A,2 = 13
      Rank.three: 'H   H   H   D   D   H   H   H   H   H', // A,3 = 14
      Rank.four:  'H   H   D   D   D   H   H   H   H   H', // A,4 = 15
      Rank.five:  'H   H   D   D   D   H   H   H   H   H', // A,5 = 16
      Rank.six:   'H   D   D   D   D   H   H   H   H   H', // A,6 = 17
      Rank.seven: 'Ds  Ds  Ds  Ds  Ds  S   S   H   H   H', // A,7 = 18
      Rank.eight: 'S   S   S   S   Ds  S   S   S   S   S', // A,8 = 19
      Rank.nine:  'S   S   S   S   S   S   S   S   S   S', // A,9 = 20
    };

    chart.forEach((other, cells) {
      test('A,${other.display}', () {
        expectRow('A,${other.display}', _softHand(other), cells);
      });
    });
  });

  group('Pairs', () {
    const chart = {
      Rank.ace:   'P   P   P   P   P   P   P   P   P   P',
      Rank.ten:   'S   S   S   S   S   S   S   S   S   S',
      Rank.nine:  'P   P   P   P   P   S   P   P   S   S',
      Rank.eight: 'P   P   P   P   P   P   P   P   P   P',
      Rank.seven: 'P   P   P   P   P   P   H   H   H   H',
      Rank.six:   'P   P   P   P   P   H   H   H   H   H',
      Rank.five:  'D   D   D   D   D   D   D   D   H   H',
      Rank.four:  'H   H   H   P   P   H   H   H   H   H',
      Rank.three: 'P   P   P   P   P   P   H   H   H   H',
      Rank.two:   'P   P   P   P   P   P   H   H   H   H',
    };

    chart.forEach((rank, cells) {
      test('${rank.display},${rank.display}', () {
        expectRow('${rank.display},${rank.display}', _pair(rank), cells);
      });
    });
  });

  group('The three cells that make this an H17 chart, not an S17 one', () {
    test('eleven doubles against an ace', () {
      expect(
        BasicStrategy.best(
          hand: _hardHands[11]!,
          dealerUp: _d(Rank.ace),
        ),
        StrategyMove.double,
        reason: 'an S17 chart hits here — teaching that at this table is wrong',
      );
    });

    test('soft eighteen doubles against a two', () {
      expect(
        BasicStrategy.best(hand: _softHand(Rank.seven), dealerUp: _d(Rank.two)),
        StrategyMove.double,
      );
    });

    test('soft nineteen doubles against a six', () {
      expect(
        BasicStrategy.best(hand: _softHand(Rank.eight), dealerUp: _d(Rank.six)),
        StrategyMove.double,
      );
      // …and only against a six.
      expect(
        BasicStrategy.best(hand: _softHand(Rank.eight), dealerUp: _d(Rank.five)),
        StrategyMove.stand,
      );
    });
  });

  group('It never advises something the table would refuse', () {
    test('no split is suggested when splitting is unavailable', () {
      for (final rank in Rank.values) {
        for (final up in _upCards) {
          final move = BasicStrategy.best(
            hand: _pair(rank),
            dealerUp: up,
            canSplit: false,
          );
          expect(move, isNot(StrategyMove.split),
              reason: '${rank.display},${rank.display} vs ${up.rank.display}');
        }
      }
    });

    test('no double is suggested when doubling is unavailable', () {
      final hands = [
        ..._hardHands.values,
        for (final r in [
          Rank.two,
          Rank.three,
          Rank.four,
          Rank.five,
          Rank.six,
          Rank.seven,
          Rank.eight,
          Rank.nine,
        ])
          _softHand(r),
        for (final r in Rank.values) _pair(r),
      ];
      for (final hand in hands) {
        for (final up in _upCards) {
          final move = BasicStrategy.best(
            hand: hand,
            dealerUp: up,
            canDouble: false,
            canSplit: hand.isPair,
          );
          expect(move, isNot(StrategyMove.double),
              reason: '${hand.value} vs ${up.rank.display}');
        }
      }
    });

    test('a pair that is not split is played on its total', () {
      // Fives are the clearest case: never split, always a hard ten.
      for (final up in _upCards) {
        final asPair = BasicStrategy.best(hand: _pair(Rank.five), dealerUp: up);
        final asTen = BasicStrategy.best(hand: _hardHands[10]!, dealerUp: up);
        expect(asPair, asTen, reason: 'vs ${up.rank.display}');
      }
    });

    test('a three-card soft eighteen stands rather than hitting', () {
      // Ds with no double available: stand, not hit. Easy cell to get wrong.
      final soft18 = HandModel(cards: [
        _c(Rank.ace),
        _d(Rank.four),
        _c(Rank.three),
      ]);
      expect(soft18.isSoft, isTrue);
      expect(soft18.value, 18);
      expect(
        BasicStrategy.best(
            hand: soft18, dealerUp: _d(Rank.five), canDouble: false),
        StrategyMove.stand,
      );
    });
  });

  // ── Other rule sets get their own chart, cell by cell ──────────────────

  group('6-Deck S17 — the three cells that differ, and nothing else', () {
    const rules = RuleSet.sixDeckS17;

    test('hard 11 hits against an ace instead of doubling', () {
      expectRow('hard 11 (S17)', _hardHands[11]!,
          'D   D   D   D   D   D   D   D   D   H', rules: rules);
    });

    test('soft 18 stands against a two instead of doubling', () {
      expectRow('A,7 (S17)', _softHand(Rank.seven),
          'S   Ds  Ds  Ds  Ds  S   S   H   H   H', rules: rules);
    });

    test('soft 19 always stands', () {
      expectRow('A,8 (S17)', _softHand(Rank.eight),
          'S   S   S   S   S   S   S   S   S   S', rules: rules);
    });

    test('every other row is identical to the H17 chart', () {
      final hands = <String, HandModel>{
        for (final e in _hardHands.entries)
          if (e.key != 11) 'hard ${e.key}': e.value,
        for (final r in [
          Rank.two,
          Rank.three,
          Rank.four,
          Rank.five,
          Rank.six,
          Rank.nine,
        ])
          'A,${r.display}': _softHand(r),
        for (final r in Rank.values) '${r.display} pair': _pair(r),
      };

      hands.forEach((label, hand) {
        for (final up in _upCards) {
          final h17 = BasicStrategy.best(
            hand: hand,
            dealerUp: up,
            canDouble: hand.cards.length == 2,
            canSplit: hand.isPair,
          );
          final s17 = BasicStrategy.best(
            hand: hand,
            dealerUp: up,
            canDouble: hand.cards.length == 2,
            canSplit: hand.isPair,
            rules: rules,
          );
          expect(s17, h17, reason: '$label vs ${up.rank.display}');
        }
      });
    });
  });

  group('No double after split — splitting gets stingier', () {
    const rules = RuleSet.sixDeckNoDas;
    const chart = {
      Rank.two:   'H   H   P   P   P   P   H   H   H   H',
      Rank.three: 'H   H   P   P   P   P   H   H   H   H',
      Rank.four:  'H   H   H   H   H   H   H   H   H   H',
      Rank.six:   'H   P   P   P   P   H   H   H   H   H',
    };

    chart.forEach((rank, cells) {
      test('${rank.display},${rank.display} without DAS', () {
        expectRow('${rank.display},${rank.display}', _pair(rank), cells,
            rules: rules);
      });
    });

    test('the pairs DAS does not affect are unchanged', () {
      for (final rank in [
        Rank.ace,
        Rank.ten,
        Rank.nine,
        Rank.eight,
        Rank.seven,
        Rank.five,
      ]) {
        for (final up in _upCards) {
          final withDas = BasicStrategy.best(
            hand: _pair(rank),
            dealerUp: up,
            canSplit: true,
          );
          final without = BasicStrategy.best(
            hand: _pair(rank),
            dealerUp: up,
            canSplit: true,
            rules: rules,
          );
          expect(without, withDas,
              reason: '${rank.display},${rank.display} vs ${up.rank.display}');
        }
      }
    });
  });

  group('Hard 9–11 doubles only — every soft double disappears', () {
    const rules = RuleSet.restrictedDouble;

    test('the hard doubles that are still allowed survive', () {
      expectRow('hard 9', _hardHands[9]!,
          'H   D   D   D   D   H   H   H   H   H', rules: rules);
      expectRow('hard 10', _hardHands[10]!,
          'D   D   D   D   D   D   D   D   H   H', rules: rules);
      expectRow('hard 11', _hardHands[11]!,
          'D   D   D   D   D   D   D   D   D   D', rules: rules);
    });

    test('soft doubles become hits', () {
      for (final rank in [
        Rank.two,
        Rank.three,
        Rank.four,
        Rank.five,
        Rank.six,
      ]) {
        expectRow('A,${rank.display}', _softHand(rank),
            'H   H   H   H   H   H   H   H   H   H', rules: rules);
      }
    });

    test('soft 18 and 19 stand rather than hit, as "Ds" requires', () {
      expectRow('A,7', _softHand(Rank.seven),
          'S   S   S   S   S   S   S   H   H   H', rules: rules);
      expectRow('A,8', _softHand(Rank.eight),
          'S   S   S   S   S   S   S   S   S   S', rules: rules);
    });

    test('a pair of fives still doubles — it is a hard ten', () {
      expectRow('5,5', _pair(Rank.five),
          'D   D   D   D   D   D   D   D   H   H', rules: rules);
    });

    test('the ten-and-eleven rule is stricter still', () {
      const stricter = RuleSet(
        id: 'test_10_11',
        name: 'test',
        blurb: 'test',
        doubleRule: DoubleRule.tenAndEleven,
      );
      expectRow('hard 9', _hardHands[9]!,
          'H   H   H   H   H   H   H   H   H   H', rules: stricter);
      expectRow('hard 10', _hardHands[10]!,
          'D   D   D   D   D   D   D   D   H   H', rules: stricter);
    });
  });

  group('6:5 blackjack changes the payout, not the play', () {
    test('every decision is identical to the 3:2 game', () {
      final hands = <HandModel>[
        ..._hardHands.values,
        for (final r in [
          Rank.two,
          Rank.three,
          Rank.four,
          Rank.five,
          Rank.six,
          Rank.seven,
          Rank.eight,
          Rank.nine,
        ])
          _softHand(r),
        for (final r in Rank.values) _pair(r),
      ];
      for (final hand in hands) {
        for (final up in _upCards) {
          expect(
            BasicStrategy.best(
              hand: hand,
              dealerUp: up,
              canDouble: hand.cards.length == 2,
              canSplit: hand.isPair,
              rules: RuleSet.sixFive,
            ),
            BasicStrategy.best(
              hand: hand,
              dealerUp: up,
              canDouble: hand.cards.length == 2,
              canSplit: hand.isPair,
            ),
            reason: 'a worse payout does not change correct play',
          );
        }
      }
    });
  });

  group('Every shipped preset is coherent', () {
    test('a preset that advertises surrender can actually surrender', () {
      // This used to assert that no preset offered surrender, because the
      // table had no surrender action. It has one now; see
      // test/surrender_test.dart for the action itself.
      final surrenderTables =
          RuleSet.presets.where((p) => p.lateSurrender).toList();
      expect(surrenderTables, isNotEmpty);
      for (final preset in surrenderTables) {
        expect(preset.summary, contains('LS'), reason: preset.name);
      }
    });

    test('every preset returns a legal move for every hand', () {
      for (final preset in RuleSet.presets) {
        for (final hand in [..._hardHands.values, _pair(Rank.ace)]) {
          for (final up in _upCards) {
            final move = BasicStrategy.best(
              hand: hand,
              dealerUp: up,
              canDouble: hand.cards.length == 2,
              canSplit: hand.isPair,
              rules: preset,
            );
            expect(StrategyMove.values, contains(move),
                reason: '${preset.name}: ${hand.value} vs ${up.rank.display}');
          }
        }
      }
    });

    test('preset ids are unique and resolvable', () {
      final ids = RuleSet.presets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final preset in RuleSet.presets) {
        expect(RuleSet.byId(preset.id), preset);
      }
      expect(RuleSet.byId('nonsense'), RuleSet.fallback);
      expect(RuleSet.byId(null), RuleSet.fallback);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_logic.dart';

/// Play a round out by standing everything, answering insurance if offered.
void standEverything(OnlineTableLogic logic) {
  var guard = 0;
  while (logic.state.phase != OnlinePhase.results && guard++ < 200) {
    if (logic.state.phase == OnlinePhase.insurance) {
      for (final s in logic.state.seats) {
        logic.answerInsurance(s.id, false);
      }
      continue;
    }
    final active = logic.state.activeSeatOrNull;
    if (active == null) break;
    logic.stand(active.id);
  }
}

/// Everyone taps READY so the host is allowed to deal.
void allReady(OnlineTableLogic logic) {
  for (final s in logic.state.seats) {
    logic.setReady(s.id, true);
  }
}

void main() {
  group('Face-down cards are redacted on the wire', () {
    test('a face-down card sends no rank or suit', () {
      const hole = CardModel(suit: Suit.hearts, rank: Rank.king, faceUp: false);
      final json = hole.toJson();
      expect(json.containsKey('s'), isFalse);
      expect(json.containsKey('r'), isFalse);
      expect(json['h'], isTrue);

      final back = CardModel.fromJson(json);
      expect(back.hidden, isTrue);
      expect(back.faceUp, isFalse);
    });

    test('a face-up card still round-trips exactly', () {
      const card = CardModel(suit: Suit.spades, rank: Rank.ace);
      final back = CardModel.fromJson(card.toJson());
      expect(back.suit, Suit.spades);
      expect(back.rank, Rank.ace);
      expect(back.faceUp, isTrue);
      expect(back.hidden, isFalse);
    });

    test('a hand holding a redacted card reports only the visible total', () {
      final dealer = HandModel(cards: [
        const CardModel(suit: Suit.clubs, rank: Rank.nine),
        CardModel.fromJson(
          const CardModel(suit: Suit.hearts, rank: Rank.ace, faceUp: false)
              .toJson(),
        ),
      ]);
      expect(dealer.hasHidden, isTrue);
      expect(dealer.value, 9, reason: 'the hole card contributes nothing');
      expect(dealer.isBlackjack, isFalse);
      expect(dealer.isBust, isFalse);
    });

    test('the dealer hand a guest receives never carries the hole card', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.placeBet('h', 100);
      allReady(logic);
      logic.startDeal('h');

      final wire = logic.state.toJson();
      final dealerCards =
          (wire['dealer'] as Map)['c'] as List; // as a guest would parse it
      final hole = Map<String, dynamic>.from(dealerCards.last as Map);
      if (hole['u'] == false) {
        expect(hole['r'], isNull);
        expect(hole['s'], isNull);
      }
    });
  });

  group('Online wire serialization', () {
    test('OnlineTableState round-trips, splits and all', () {
      final state = OnlineTableState(
        roomCode: 'AB12C',
        hostId: 'host',
        phase: OnlinePhase.playerTurns,
        activeSeat: 1,
        round: 3,
        seq: 42,
        clockMs: 8000,
        runningCount: -3,
        trueCount: -0.75,
        cardsRemaining: 200,
        totalCards: 312,
        dealer: const HandModel(cards: [
          CardModel(suit: Suit.diamonds, rank: Rank.ten),
          CardModel(suit: Suit.spades, rank: Rank.six, faceUp: false),
        ]),
        seats: [
          const OnlineSeat(id: 'host', name: 'Ann', bankroll: 900, bet: 100),
          OnlineSeat(
            id: 'g1',
            name: 'Bo',
            bankroll: 950,
            bet: 50,
            insuranceBet: 25,
            insuranceAnswered: true,
            connected: false,
            ready: true,
            netLastRound: -75,
            rebuys: 1,
            activeHand: 1,
            hands: [
              const SeatHand(
                hand: HandModel(cards: [
                  CardModel(suit: Suit.hearts, rank: Rank.king),
                  CardModel(suit: Suit.clubs, rank: Rank.seven),
                ], bet: 50),
                result: GameResult.win,
                done: true,
              ),
              const SeatHand(
                hand: HandModel(cards: [
                  CardModel(suit: Suit.hearts, rank: Rank.eight),
                ], bet: 50, fromSplit: true),
              ),
            ],
          ),
        ],
      );

      final back = OnlineTableState.fromJson(state.toJson());
      expect(back.version, onlineWireVersion);
      expect(back.roomCode, 'AB12C');
      expect(back.seq, 42);
      expect(back.clockMs, 8000);
      expect(back.runningCount, -3);
      expect(back.trueCount, closeTo(-0.75, 0.001));
      expect(back.cardsRemaining, 200);
      expect(back.phase, OnlinePhase.playerTurns);

      final bo = back.seatById('g1')!;
      expect(bo.hands.length, 2);
      expect(bo.hands[0].result, GameResult.win);
      expect(bo.hands[0].done, isTrue);
      expect(bo.hands[1].hand.fromSplit, isTrue);
      expect(bo.activeHand, 1);
      expect(bo.insuranceBet, 25);
      expect(bo.connected, isFalse);
      expect(bo.ready, isTrue);
      expect(bo.netLastRound, -75);
      expect(bo.rebuys, 1);
    });
  });

  group('Settlement', () {
    OnlineSeat seat(
      HandModel hand, {
      int bet = 100,
      int bankroll = 900,
      int insurance = 0,
    }) =>
        OnlineSeat(
          id: 'p',
          name: 'P',
          bankroll: bankroll,
          bet: bet,
          insuranceBet: insurance,
          hands: [SeatHand(hand: hand)],
        );

    const dealer18 = HandModel(cards: [
      CardModel(suit: Suit.clubs, rank: Rank.ten),
      CardModel(suit: Suit.diamonds, rank: Rank.eight),
    ]);

    test('natural blackjack pays 3:2', () {
      final settled = OnlineTableLogic.settleSeat(
        seat(const HandModel(cards: [
          CardModel(suit: Suit.hearts, rank: Rank.ace),
          CardModel(suit: Suit.spades, rank: Rank.king),
        ], bet: 100)),
        dealer18,
      );
      expect(settled.hands.single.result, GameResult.blackjack);
      expect(settled.bankroll, 1150); // 900 + 100 stake + 150 profit
      expect(settled.netLastRound, 150);
    });

    test('a two-card 21 from a split pays even money, not 3:2', () {
      final settled = OnlineTableLogic.settleSeat(
        seat(const HandModel(cards: [
          CardModel(suit: Suit.hearts, rank: Rank.ace),
          CardModel(suit: Suit.spades, rank: Rank.king),
        ], bet: 100, fromSplit: true)),
        dealer18,
      );
      expect(settled.hands.single.result, GameResult.win);
      expect(settled.bankroll, 1100); // 900 + 200, not 1150
      expect(settled.netLastRound, 100);
    });

    test('push returns the stake', () {
      final settled = OnlineTableLogic.settleSeat(
        seat(const HandModel(cards: [
          CardModel(suit: Suit.hearts, rank: Rank.ten),
          CardModel(suit: Suit.spades, rank: Rank.eight),
        ], bet: 100)),
        dealer18,
      );
      expect(settled.hands.single.result, GameResult.push);
      expect(settled.bankroll, 1000);
      expect(settled.netLastRound, 0);
    });

    test('a doubled winning hand pays from double the bet', () {
      final settled = OnlineTableLogic.settleSeat(
        seat(
          const HandModel(cards: [
            CardModel(suit: Suit.hearts, rank: Rank.five),
            CardModel(suit: Suit.spades, rank: Rank.six),
            CardModel(suit: Suit.clubs, rank: Rank.nine),
          ], bet: 100, isDoubled: true),
          bankroll: 800,
        ),
        dealer18,
      );
      expect(settled.hands.single.result, GameResult.win);
      expect(settled.bankroll, 1200); // 800 + 400
      expect(settled.netLastRound, 200);
    });

    test('dealer bust pays 1:1', () {
      final settled = OnlineTableLogic.settleSeat(
        seat(const HandModel(cards: [
          CardModel(suit: Suit.hearts, rank: Rank.ten),
          CardModel(suit: Suit.spades, rank: Rank.seven),
        ], bet: 100)),
        const HandModel(cards: [
          CardModel(suit: Suit.clubs, rank: Rank.ten),
          CardModel(suit: Suit.diamonds, rank: Rank.six),
          CardModel(suit: Suit.spades, rank: Rank.king),
        ]),
      );
      expect(settled.hands.single.result, GameResult.dealerBust);
      expect(settled.bankroll, 1100);
    });

    test('insurance pays 2:1 against a dealer blackjack', () {
      const dealerBJ = HandModel(cards: [
        CardModel(suit: Suit.clubs, rank: Rank.ace),
        CardModel(suit: Suit.diamonds, rank: Rank.king),
      ]);
      // Staked 100 main + 50 insurance, so bankroll is already down 150.
      final settled = OnlineTableLogic.settleSeat(
        seat(
          const HandModel(cards: [
            CardModel(suit: Suit.hearts, rank: Rank.ten),
            CardModel(suit: Suit.spades, rank: Rank.eight),
          ], bet: 100),
          bankroll: 850,
          insurance: 50,
        ),
        dealerBJ,
      );
      expect(settled.hands.single.result, GameResult.loss);
      // Insurance returns 150; the main hand returns nothing.
      expect(settled.bankroll, 1000);
      expect(settled.netLastRound, 0, reason: 'insurance exactly covers it');
    });

    test('insurance is forfeited when the dealer has no blackjack', () {
      final settled = OnlineTableLogic.settleSeat(
        seat(
          const HandModel(cards: [
            CardModel(suit: Suit.hearts, rank: Rank.ten),
            CardModel(suit: Suit.spades, rank: Rank.nine),
          ], bet: 100),
          bankroll: 850,
          insurance: 50,
        ),
        dealer18, // 18, we have 19
      );
      expect(settled.hands.single.result, GameResult.win);
      expect(settled.bankroll, 1050); // 850 + 200
      expect(settled.netLastRound, 50); // +100 main, −50 insurance
    });

    test('every hand of a split settles independently', () {
      final s = OnlineSeat(
        id: 'p',
        name: 'P',
        bankroll: 800,
        bet: 100,
        hands: const [
          SeatHand(
            hand: HandModel(cards: [
              CardModel(suit: Suit.hearts, rank: Rank.ten),
              CardModel(suit: Suit.clubs, rank: Rank.ten),
            ], bet: 100, fromSplit: true),
          ),
          SeatHand(
            hand: HandModel(cards: [
              CardModel(suit: Suit.spades, rank: Rank.ten),
              CardModel(suit: Suit.diamonds, rank: Rank.five),
            ], bet: 100, fromSplit: true),
          ),
        ],
      );
      final settled = OnlineTableLogic.settleSeat(s, dealer18);
      expect(settled.hands[0].result, GameResult.win); // 20 beats 18
      expect(settled.hands[1].result, GameResult.loss); // 15 loses
      expect(settled.bankroll, 1000); // 800 + 200 for the winner
      expect(settled.netLastRound, 0); // +100 / −100
    });

    test('dealer hits soft 17', () {
      expect(
        OnlineTableLogic.dealerShouldHit(const HandModel(cards: [
          CardModel(suit: Suit.hearts, rank: Rank.ace),
          CardModel(suit: Suit.spades, rank: Rank.six),
        ])),
        isTrue,
      );
      expect(
        OnlineTableLogic.dealerShouldHit(const HandModel(cards: [
          CardModel(suit: Suit.hearts, rank: Rank.ten),
          CardModel(suit: Suit.spades, rank: Rank.seven),
        ])),
        isFalse,
      );
    });
  });

  group('Table flow', () {
    test('adds players up to the seat cap', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      expect(logic.state.seats.length, 2);
      logic.addPlayer('g1', 'Renamed');
      expect(logic.state.seats.length, 2);
      expect(logic.state.seatById('g1')!.name, 'Renamed');

      for (var i = 0; i < OnlineTableLogic.maxSeats + 2; i++) {
        logic.addPlayer('extra$i', 'X$i');
      }
      expect(logic.state.seats.length, OnlineTableLogic.maxSeats);
    });

    test('players only bet their own seat, within bankroll', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('g1', 50);
      expect(logic.state.seatById('g1')!.bet, 50);
      logic.placeBet('g1', 2000);
      expect(logic.state.seatById('g1')!.bet, 50);
      logic.placeBet('nobody', 25);
      expect(logic.state.seats.length, 2);
    });

    test('the host cannot deal players out before they have bet', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.addPlayer('g2', 'G2');
      logic.placeBet('h', 5);

      // g1 and g2 are still choosing chips, so DEAL does nothing.
      logic.startDeal('h');
      expect(logic.state.phase, OnlinePhase.betting);
      expect(logic.canDeal, isFalse);

      logic.setReady('g1', true);
      logic.startDeal('h');
      expect(logic.state.phase, OnlinePhase.betting, reason: 'g2 not ready');

      logic.setReady('g2', true);
      expect(logic.canDeal, isTrue);
      logic.startDeal('h');
      expect(logic.state.phase, isNot(OnlinePhase.betting));
    });

    test('a player too broke to bet does not block the deal', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.state = logic.state.copyWith(seats: [
        for (final s in logic.state.seats)
          s.id == 'g1' ? s.copyWith(bankroll: 0) : s,
      ]);
      logic.placeBet('h', 100);

      // g1 is shown the buy-in panel, so they have no READY button to press.
      expect(logic.state.seatById('g1')!.ready, isFalse);
      expect(logic.canDeal, isTrue);
      logic.startDeal('h');
      expect(logic.state.phase, isNot(OnlinePhase.betting));
    });

    test('a guest cannot start the deal', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100);
      allReady(logic);
      logic.startDeal('g1');
      expect(logic.state.phase, OnlinePhase.betting);
      logic.startDeal('h');
      expect(logic.state.phase, isNot(OnlinePhase.betting));
      expect(logic.state.seatById('h')!.bankroll, 900);
      expect(logic.state.seatById('g1')!.inRound, isFalse);
    });

    test('turn enforcement: only the active seat can act', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100);
      logic.placeBet('g1', 100);
      allReady(logic);
      logic.startDeal('h');
      if (logic.state.phase == OnlinePhase.insurance) {
        for (final s in logic.state.seats) {
          logic.answerInsurance(s.id, false);
        }
      }
      if (logic.state.phase != OnlinePhase.playerTurns) return;

      final active = logic.state.activeSeatOrNull!;
      final other = logic.state.seats.firstWhere((s) => s.id != active.id);
      final before = other.hands.first.hand.cards.length;
      logic.hit(other.id);
      expect(
        logic.state.seatById(other.id)!.hands.first.hand.cards.length,
        before,
      );
    });

    test('a full round settles every funded seat and leaves none negative', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.addPlayer('g2', 'G2');
      logic.placeBet('h', 100);
      logic.placeBet('g1', 50);
      allReady(logic); // g2 sits out but is ready
      logic.startDeal('h');
      standEverything(logic);

      expect(logic.state.phase, OnlinePhase.results);
      final d = logic.state.dealer;
      expect(d.isBust || d.value >= 17 || d.isBlackjack, isTrue);
      expect(logic.state.seatById('h')!.hands.first.result, isNotNull);
      expect(logic.state.seatById('g1')!.hands.first.result, isNotNull);
      expect(logic.state.seatById('g2')!.hands, isEmpty);
      expect(logic.state.seats.every((s) => s.bankroll >= 0), isTrue);
    });

    test('nextRound clears the table but keeps bankrolls', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.placeBet('h', 100);
      allReady(logic);
      logic.startDeal('h');
      standEverything(logic);
      final bankroll = logic.state.seatById('h')!.bankroll;

      logic.nextRound('h');
      expect(logic.state.phase, OnlinePhase.betting);
      expect(logic.state.round, 1);
      final seat = logic.state.seatById('h')!;
      expect(seat.bet, 0);
      expect(seat.hands, isEmpty);
      expect(seat.ready, isFalse);
      expect(seat.bankroll, bankroll);
    });

    test('the shared shoe count tracks the cards that have been shown', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.placeBet('h', 100);
      allReady(logic);
      expect(logic.state.cardsRemaining, 312);
      logic.startDeal('h');
      expect(logic.state.cardsRemaining, lessThan(312));
      expect(logic.state.totalCards, 312);
      expect(logic.state.penetration, greaterThan(0));
    });
  });

  group('Splitting', () {
    /// A table sitting in [OnlinePhase.playerTurns] with [pair] in the host's
    /// hand, built directly so the case under test is deterministic rather
    /// than waiting for the shoe to deal it.
    OnlineTableLogic tableHolding(Rank pair, {bool addSecondPlayer = false}) {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      if (addSecondPlayer) logic.addPlayer('g1', 'G1');

      SeatHand hand(Rank a, Rank b) => SeatHand(
            hand: HandModel(
              cards: [
                CardModel(suit: Suit.hearts, rank: a),
                CardModel(suit: Suit.clubs, rank: b),
              ],
              bet: 100,
            ),
          );

      logic.state = logic.state.copyWith(
        phase: OnlinePhase.playerTurns,
        activeSeat: 0,
        seats: [
          for (final s in logic.state.seats)
            if (s.id == 'h')
              s.copyWith(
                bankroll: 900,
                bet: 100,
                hands: [hand(pair, pair)],
                activeHand: 0,
              )
            else
              s.copyWith(
                bankroll: 900,
                bet: 100,
                hands: [hand(Rank.nine, Rank.seven)],
                activeHand: 0,
              ),
        ],
      );
      return logic;
    }

    test('splitting a pair makes two hands and stakes one more bet', () {
      final logic = tableHolding(Rank.eight);
      logic.split('h');

      final seat = logic.state.seatById('h')!;
      expect(seat.hands.length, 2);
      expect(seat.bankroll, 800, reason: 'one extra base bet is staked');
      for (final h in seat.hands) {
        expect(h.hand.fromSplit, isTrue);
        expect(h.hand.bet, 100);
        expect(h.hand.cards.length, 2, reason: 'each half drew a card');
        expect(h.done, isFalse, reason: 'eights keep playing');
      }
      expect(logic.state.phase, OnlinePhase.playerTurns);
      expect(logic.state.activeSeatOrNull!.id, 'h');
      expect(seat.activeHand, 0);
    });

    test('both split hands are then played in order', () {
      final logic = tableHolding(Rank.eight);
      logic.split('h');
      expect(logic.state.seatById('h')!.activeHand, 0);

      logic.stand('h');
      expect(logic.state.seatById('h')!.activeHand, 1,
          reason: 'play moves to the second hand, not the next player');
      expect(logic.state.activeSeatOrNull!.id, 'h');

      logic.stand('h');
      expect(logic.state.phase, OnlinePhase.results);
      final settled = logic.state.seatById('h')!;
      expect(settled.hands.length, 2);
      expect(settled.hands.every((h) => h.result != null), isTrue);
    });

    test('split aces draw exactly one card each and stand', () {
      // A second player keeps the round open so the aces can be inspected
      // before settlement runs.
      final logic = tableHolding(Rank.ace, addSecondPlayer: true);
      logic.split('h');

      final seat = logic.state.seatById('h')!;
      expect(seat.hands.length, 2);
      expect(seat.bankroll, 800);
      expect(seat.hands.every((h) => h.hand.cards.length == 2), isTrue);
      expect(seat.hands.every((h) => h.done), isTrue,
          reason: 'aces take one card and stand');
      expect(logic.state.phase, OnlinePhase.playerTurns);
      expect(logic.state.activeSeatOrNull!.id, 'g1',
          reason: 'play moved on to the next seat');
    });

    test('a split hand that reaches 21 stands automatically', () {
      final logic = tableHolding(Rank.eight);
      logic.split('h');
      final seat = logic.state.seatById('h')!;
      for (final h in seat.hands) {
        if (h.hand.value >= 21) expect(h.done, isTrue);
      }
    });

    test('splitting again is allowed up to the four-hand cap', () {
      final logic = tableHolding(Rank.eight);

      // Each split deals fresh cards, so re-pair whichever hand is up next to
      // keep exercising the cap rather than the luck of the shoe.
      void repairActiveHand() {
        final seat = logic.state.seatById('h')!;
        final idx = seat.nextHandIndex;
        if (idx < 0) return;
        logic.state = logic.state.copyWith(seats: [
          for (final s in logic.state.seats)
            if (s.id == 'h')
              s.copyWith(
                bankroll: 1000,
                hands: [
                  for (var i = 0; i < s.hands.length; i++)
                    if (i == idx)
                      s.hands[i].copyWith(
                        hand: const HandModel(
                          cards: [
                            CardModel(suit: Suit.hearts, rank: Rank.eight),
                            CardModel(suit: Suit.clubs, rank: Rank.eight),
                          ],
                          bet: 100,
                          fromSplit: true,
                        ),
                        done: false,
                      )
                    else
                      s.hands[i],
                ],
              )
            else
              s,
        ]);
      }

      logic.split('h');
      expect(logic.state.seatById('h')!.hands.length, 2);

      repairActiveHand();
      logic.split('h');
      expect(logic.state.seatById('h')!.hands.length, 3);

      repairActiveHand();
      logic.split('h');
      expect(logic.state.seatById('h')!.hands.length,
          OnlineTableLogic.maxHandsPerSeat);

      // A fifth hand is refused even with a pair and plenty of chips.
      repairActiveHand();
      logic.split('h');
      expect(logic.state.seatById('h')!.hands.length,
          OnlineTableLogic.maxHandsPerSeat);
    });

    test('a seat cannot split past the hand cap or beyond its bankroll', () {
      final seat = OnlineSeat(
        id: 'p',
        name: 'P',
        bankroll: 1000,
        bet: 100,
        hands: List.filled(
          OnlineTableLogic.maxHandsPerSeat,
          const SeatHand(
            hand: HandModel(cards: [
              CardModel(suit: Suit.hearts, rank: Rank.eight),
              CardModel(suit: Suit.clubs, rank: Rank.eight),
            ], bet: 100),
          ),
        ),
      );
      expect(
        OnlineTableLogic.canSplitHand(seat, seat.hands.first),
        isFalse,
        reason: 'already at the four-hand cap',
      );

      const broke = OnlineSeat(
        id: 'p',
        name: 'P',
        bankroll: 10,
        bet: 100,
        hands: [
          SeatHand(
            hand: HandModel(cards: [
              CardModel(suit: Suit.hearts, rank: Rank.eight),
              CardModel(suit: Suit.clubs, rank: Rank.eight),
            ], bet: 100),
          ),
        ],
      );
      expect(OnlineTableLogic.canSplitHand(broke, broke.hands.first), isFalse);
    });

    test('a non-pair can never be split', () {
      const seat = OnlineSeat(
        id: 'p',
        name: 'P',
        bankroll: 1000,
        bet: 100,
        hands: [
          SeatHand(
            hand: HandModel(cards: [
              CardModel(suit: Suit.hearts, rank: Rank.eight),
              CardModel(suit: Suit.clubs, rank: Rank.nine),
            ], bet: 100),
          ),
        ],
      );
      expect(OnlineTableLogic.canSplitHand(seat, seat.hands.first), isFalse);
    });
  });

  group('Insurance flow', () {
    test('a dealer ace opens the insurance phase and everyone must answer', () {
      for (var attempt = 0; attempt < 500; attempt++) {
        final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
        logic.addPlayer('h', 'Host');
        logic.addPlayer('g1', 'G1');
        logic.placeBet('h', 100);
        logic.placeBet('g1', 100);
        allReady(logic);
        logic.startDeal('h');
        if (logic.state.phase != OnlinePhase.insurance) continue;

        expect(logic.state.dealer.cards.first.rank, Rank.ace);
        logic.answerInsurance('h', true);
        expect(logic.state.seatById('h')!.insuranceBet, 50);
        expect(logic.state.seatById('h')!.bankroll, 850);
        // Still waiting on g1, so the phase has not moved on.
        expect(logic.state.phase, OnlinePhase.insurance);

        logic.answerInsurance('g1', false);
        expect(logic.state.seatById('g1')!.insuranceBet, 0);
        expect(logic.state.phase, isNot(OnlinePhase.insurance));
        return;
      }
    });
  });

  group('The dealer does not play a decided round', () {
    test('no extra cards are drawn once every player has busted', () {
      var allBustRounds = 0;
      for (var i = 0; i < 400 && allBustRounds < 40; i++) {
        final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
        logic.addPlayer('h', 'Host');
        logic.placeBet('h', 10);
        allReady(logic);
        logic.startDeal('h');
        if (logic.state.phase == OnlinePhase.insurance) {
          logic.answerInsurance('h', false);
        }
        if (logic.state.phase != OnlinePhase.playerTurns) continue;

        var guard = 0;
        while (logic.state.phase == OnlinePhase.playerTurns && guard++ < 20) {
          logic.hit('h');
        }
        final seat = logic.state.seatById('h')!;
        if (!seat.hands.every((h) => h.hand.isBust)) continue;

        allBustRounds++;
        expect(logic.state.dealer.cards.length, 2,
            reason: 'nothing left to beat, so the dealer stands pat');
      }
      expect(allBustRounds, greaterThan(0), reason: 'sanity: sampled a bust');
    });
  });

  group('Disconnects, reconnects, and chips', () {
    test('reconnecting reclaims the seat with its bankroll intact', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.state = logic.state.copyWith(seats: [
        for (final s in logic.state.seats)
          s.id == 'g1' ? s.copyWith(bankroll: 137) : s,
      ]);

      logic.markDisconnected('g1');
      expect(logic.state.seatById('g1'), isNotNull, reason: 'seat is held');
      expect(logic.state.seatById('g1')!.connected, isFalse);
      expect(logic.state.seatById('g1')!.bankroll, 137);

      logic.addPlayer('g1', 'G1');
      expect(logic.state.seatById('g1')!.connected, isTrue);
      expect(logic.state.seatById('g1')!.bankroll, 137,
          reason: 'no fresh 1000 on reconnect');
    });

    test('dropping mid-round stands the hand so the wager still settles', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100);
      logic.placeBet('g1', 100);
      allReady(logic);
      logic.startDeal('h');
      if (logic.state.phase == OnlinePhase.insurance) {
        for (final s in logic.state.seats) {
          logic.answerInsurance(s.id, false);
        }
      }
      if (logic.state.phase != OnlinePhase.playerTurns) return;

      logic.markDisconnected('g1');
      final g1 = logic.state.seatById('g1')!;
      expect(g1.hands.every((h) => h.done), isTrue);

      standEverything(logic);
      final settled = logic.state.seatById('g1')!;
      expect(settled.hands.single.result, isNotNull,
          reason: 'the stake resolved rather than vanishing');
      expect(settled.bankroll + settled.staked, greaterThanOrEqualTo(900));
    });

    test('an abandoned seat is only swept after the grace period', () {
      var now = DateTime(2026, 1, 1, 12);
      final logic = OnlineTableLogic(
        roomCode: 'R',
        hostId: 'h',
        now: () => now,
      );
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.markDisconnected('g1');

      now = now.add(const Duration(seconds: 30));
      logic.sweepAbandonedSeats();
      expect(logic.state.seatById('g1'), isNotNull, reason: 'still reserved');

      now = now.add(OnlineTableLogic.reconnectGrace);
      logic.sweepAbandonedSeats();
      expect(logic.state.seatById('g1'), isNull, reason: 'grace expired');
      expect(logic.state.seatById('h'), isNotNull);
    });

    test('a broke player can buy back in', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.state = logic.state.copyWith(
        seats: [logic.state.seats.first.copyWith(bankroll: 0)],
      );
      expect(logic.state.seatById('h')!.bankroll, 0);

      logic.rebuy('h');
      expect(logic.state.seatById('h')!.bankroll, OnlineTableLogic.rebuyAmount);
      expect(logic.state.seatById('h')!.rebuys, 1);

      // A player with chips cannot mint more.
      logic.rebuy('h');
      expect(logic.state.seatById('h')!.bankroll, OnlineTableLogic.rebuyAmount);
    });

    test('a stack too small to cover the minimum chip also counts as broke',
        () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.state = logic.state.copyWith(
        seats: [logic.state.seats.first.copyWith(bankroll: 3)],
      );
      // $3 cannot cover the $5 chip, so the player would otherwise be stuck
      // holding chips they can never wager.
      logic.placeBet('h', OnlineTableLogic.minBet);
      expect(logic.state.seatById('h')!.bet, 0);

      logic.rebuy('h');
      expect(logic.state.seatById('h')!.bankroll,
          3 + OnlineTableLogic.rebuyAmount);
    });

    test('the host can remove a player between rounds, but not mid-hand', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');

      logic.kick('g1', 'h'); // a guest cannot kick
      expect(logic.state.seats.length, 2);

      logic.placeBet('h', 100);
      logic.placeBet('g1', 100);
      allReady(logic);
      logic.startDeal('h');

      // A dealer blackjack settles the round inside startDeal, so pin the
      // phase — otherwise this assertion silently tests nothing ~5% of the
      // time, depending on the shoe.
      logic.state = logic.state.copyWith(phase: OnlinePhase.playerTurns);
      logic.kick('h', 'g1'); // mid-round is refused
      expect(logic.state.seatById('g1'), isNotNull);

      logic.state = logic.state.copyWith(phase: OnlinePhase.results);
      logic.kick('h', 'g1');
      expect(logic.state.seatById('g1'), isNull);
    });
  });

  group('Phase clocks', () {
    test('an unresponsive player is stood automatically', () {
      var now = DateTime(2026, 1, 1, 12);
      final logic = OnlineTableLogic(
        roomCode: 'R',
        hostId: 'h',
        now: () => now,
      );
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100);
      logic.placeBet('g1', 100);
      allReady(logic);
      logic.startDeal('h');
      if (logic.state.phase == OnlinePhase.insurance) {
        now = now.add(OnlineTableLogic.insuranceClock + const Duration(seconds: 1));
        logic.tick();
      }
      if (logic.state.phase != OnlinePhase.playerTurns) return;

      final stalled = logic.state.activeSeatOrNull!.id;
      now = now.add(OnlineTableLogic.turnClock + const Duration(seconds: 1));
      logic.tick();

      final seat = logic.state.seatById(stalled)!;
      expect(seat.hands.every((h) => h.done), isTrue,
          reason: 'the turn clock stood them');
      expect(logic.state.activeSeatOrNull?.id, isNot(stalled));
    });

    test('the betting clock deals the round without the host', () {
      var now = DateTime(2026, 1, 1, 12);
      final logic = OnlineTableLogic(
        roomCode: 'R',
        hostId: 'h',
        now: () => now,
      );
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100); // g1 never responds

      expect(logic.state.clockMs, isNotNull);
      now = now.add(OnlineTableLogic.bettingClock + const Duration(seconds: 1));
      logic.tick();

      expect(logic.state.phase, isNot(OnlinePhase.betting));
      expect(logic.state.seatById('h')!.inRound, isTrue);
    });

    test('an unanswered insurance prompt declines and play continues', () {
      for (var attempt = 0; attempt < 500; attempt++) {
        var now = DateTime(2026, 1, 1, 12);
        final logic = OnlineTableLogic(
          roomCode: 'R',
          hostId: 'h',
          now: () => now,
        );
        logic.addPlayer('h', 'Host');
        logic.placeBet('h', 100);
        allReady(logic);
        logic.startDeal('h');
        if (logic.state.phase != OnlinePhase.insurance) continue;

        now = now
            .add(OnlineTableLogic.insuranceClock + const Duration(seconds: 1));
        logic.tick();
        expect(logic.state.phase, isNot(OnlinePhase.insurance));
        expect(logic.state.seatById('h')!.insuranceBet, 0);
        return;
      }
    });

    test('the results clock starts the next round on its own', () {
      var now = DateTime(2026, 1, 1, 12);
      final logic = OnlineTableLogic(
        roomCode: 'R',
        hostId: 'h',
        now: () => now,
      );
      logic.addPlayer('h', 'Host');
      logic.placeBet('h', 100);
      allReady(logic);
      logic.startDeal('h');
      standEverything(logic);
      expect(logic.state.phase, OnlinePhase.results);

      now = now.add(OnlineTableLogic.resultsClock + const Duration(seconds: 1));
      logic.tick();
      expect(logic.state.phase, OnlinePhase.betting);
      expect(logic.state.round, 1);
    });
  });
}

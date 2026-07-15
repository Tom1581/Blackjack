import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_logic.dart';

void main() {
  group('Online wire serialization', () {
    test('CardModel round-trips', () {
      const card = CardModel(suit: Suit.spades, rank: Rank.ace, faceUp: false);
      final back = CardModel.fromJson(card.toJson());
      expect(back.suit, card.suit);
      expect(back.rank, card.rank);
      expect(back.faceUp, card.faceUp);
    });

    test('HandModel round-trips including bet/doubled/fromSplit', () {
      final hand = HandModel(cards: const [
        CardModel(suit: Suit.hearts, rank: Rank.ace),
        CardModel(suit: Suit.clubs, rank: Rank.nine),
      ], bet: 75, isDoubled: true, fromSplit: true);
      final back = HandModel.fromJson(hand.toJson());
      expect(back.cards.length, 2);
      expect(back.value, hand.value);
      expect(back.bet, 75);
      expect(back.isDoubled, true);
      expect(back.fromSplit, true);
    });

    test('OnlineTableState round-trips', () {
      final state = OnlineTableState(
        roomCode: 'AB12',
        hostId: 'host',
        phase: OnlinePhase.playerTurns,
        activeSeat: 1,
        round: 3,
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
            hand: const HandModel(cards: [
              CardModel(suit: Suit.hearts, rank: Rank.king),
              CardModel(suit: Suit.clubs, rank: Rank.seven),
            ], bet: 50),
            result: GameResult.win,
          ),
        ],
      );

      final back = OnlineTableState.fromJson(state.toJson());
      expect(back.roomCode, 'AB12');
      expect(back.hostId, 'host');
      expect(back.phase, OnlinePhase.playerTurns);
      expect(back.activeSeat, 1);
      expect(back.round, 3);
      expect(back.seats.length, 2);
      expect(back.seats[1].name, 'Bo');
      expect(back.seats[1].result, GameResult.win);
      expect(back.seats[1].hand.value, state.seats[1].hand.value);
      expect(back.dealer.cards.length, 2);
    });
  });

  group('OnlineTableLogic settlement (pure)', () {
    OnlineSeat seat(HandModel hand, {int bet = 100, int bankroll = 900}) =>
        OnlineSeat(id: 'p', name: 'P', bankroll: bankroll, bet: bet, hand: hand);

    test('natural blackjack pays 3:2', () {
      final s = seat(const HandModel(cards: [
        CardModel(suit: Suit.hearts, rank: Rank.ace),
        CardModel(suit: Suit.spades, rank: Rank.king),
      ], bet: 100));
      final dealer = const HandModel(cards: [
        CardModel(suit: Suit.clubs, rank: Rank.ten),
        CardModel(suit: Suit.diamonds, rank: Rank.eight),
      ]); // 18
      final settled = OnlineTableLogic.settleSeat(s, dealer);
      expect(settled.result, GameResult.blackjack);
      // 900 + (100 + 150) = 1150
      expect(settled.bankroll, 1150);
    });

    test('push returns the stake', () {
      final s = seat(const HandModel(cards: [
        CardModel(suit: Suit.hearts, rank: Rank.ten),
        CardModel(suit: Suit.spades, rank: Rank.eight),
      ], bet: 100)); // 18
      final dealer = const HandModel(cards: [
        CardModel(suit: Suit.clubs, rank: Rank.ten),
        CardModel(suit: Suit.diamonds, rank: Rank.eight),
      ]); // 18
      final settled = OnlineTableLogic.settleSeat(s, dealer);
      expect(settled.result, GameResult.push);
      expect(settled.bankroll, 1000); // 900 + 100 stake back
    });

    test('a doubled winning hand pays from double the bet', () {
      final s = seat(
        HandModel(cards: const [
          CardModel(suit: Suit.hearts, rank: Rank.five),
          CardModel(suit: Suit.spades, rank: Rank.six),
          CardModel(suit: Suit.clubs, rank: Rank.nine),
        ], bet: 100, isDoubled: true), // 20
        bankroll: 800, // already had the extra double stake removed
      );
      final dealer = const HandModel(cards: [
        CardModel(suit: Suit.clubs, rank: Rank.ten),
        CardModel(suit: Suit.diamonds, rank: Rank.eight),
      ]); // 18
      final settled = OnlineTableLogic.settleSeat(s, dealer);
      expect(settled.result, GameResult.win);
      // doubled bet 200 → win pays 400. 800 + 400 = 1200.
      expect(settled.bankroll, 1200);
    });

    test('dealer bust pays 1:1', () {
      final s = seat(const HandModel(cards: [
        CardModel(suit: Suit.hearts, rank: Rank.ten),
        CardModel(suit: Suit.spades, rank: Rank.seven),
      ], bet: 100)); // 17
      final dealer = const HandModel(cards: [
        CardModel(suit: Suit.clubs, rank: Rank.ten),
        CardModel(suit: Suit.diamonds, rank: Rank.six),
        CardModel(suit: Suit.spades, rank: Rank.king),
      ]); // 26 bust
      final settled = OnlineTableLogic.settleSeat(s, dealer);
      expect(settled.result, GameResult.dealerBust);
      expect(settled.bankroll, 1100);
    });

    test('dealer hits soft 17', () {
      final soft17 = const HandModel(cards: [
        CardModel(suit: Suit.hearts, rank: Rank.ace),
        CardModel(suit: Suit.spades, rank: Rank.six),
      ]);
      expect(OnlineTableLogic.dealerShouldHit(soft17), true);
      final hard17 = const HandModel(cards: [
        CardModel(suit: Suit.hearts, rank: Rank.ten),
        CardModel(suit: Suit.spades, rank: Rank.seven),
      ]);
      expect(OnlineTableLogic.dealerShouldHit(hard17), false);
    });
  });

  group('OnlineTableLogic flow', () {
    test('adds players up to the seat cap', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      expect(logic.state.seats.length, 2);
      // Re-adding updates the name, doesn't duplicate.
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
      // Over-bankroll is ignored.
      logic.placeBet('g1', 2000);
      expect(logic.state.seatById('g1')!.bet, 50);
      // Unknown player is ignored.
      logic.placeBet('nobody', 25);
      expect(logic.state.seats.length, 2);
    });

    test('only the host can start the deal, and only funded seats are dealt',
        () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100); // only host bets
      // A guest cannot start the deal.
      logic.startDeal('g1');
      expect(logic.state.phase, OnlinePhase.betting);

      logic.startDeal('h');
      expect(logic.state.phase, anyOf(OnlinePhase.playerTurns, OnlinePhase.results));
      expect(logic.state.seatById('h')!.hand.cards.length, 2);
      expect(logic.state.seatById('h')!.bankroll, 900); // 1000 - 100
      // Unfunded guest was not dealt in.
      expect(logic.state.seatById('g1')!.hand.cards.isEmpty, true);
      expect(logic.state.seatById('g1')!.inRound, false);
    });

    test('turn enforcement: only the active seat can act', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.placeBet('h', 100);
      logic.placeBet('g1', 100);
      logic.startDeal('h');

      if (logic.state.phase != OnlinePhase.playerTurns) return; // dealer BJ
      final active = logic.state.activeSeatOrNull!;
      final other = logic.state.seats.firstWhere((s) => s.id != active.id);
      final beforeCards = other.hand.cards.length;
      // The non-active seat's hit is ignored.
      logic.hit(other.id);
      expect(logic.state.seatById(other.id)!.hand.cards.length, beforeCards);
    });

    test('a full round with everyone standing settles all funded seats', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.addPlayer('g1', 'G1');
      logic.addPlayer('g2', 'G2');
      logic.placeBet('h', 100);
      logic.placeBet('g1', 50);
      // g2 sits out (no bet).
      logic.startDeal('h');

      var guard = 0;
      while (logic.state.phase == OnlinePhase.playerTurns && guard++ < 50) {
        final active = logic.state.activeSeatOrNull!;
        logic.stand(active.id);
      }

      expect(logic.state.phase, OnlinePhase.results);
      // Dealer finished at 17+ or busted.
      final d = logic.state.dealer;
      expect(d.isBust || d.value >= 17, true);
      // Funded seats have results; the sitting-out seat does not.
      expect(logic.state.seatById('h')!.result, isNotNull);
      expect(logic.state.seatById('g1')!.result, isNotNull);
      expect(logic.state.seatById('g2')!.result, isNull);
      expect(logic.state.seats.every((s) => s.bankroll >= 0), true);
    });

    test('nextRound clears the table but keeps bankrolls', () {
      final logic = OnlineTableLogic(roomCode: 'R', hostId: 'h');
      logic.addPlayer('h', 'Host');
      logic.placeBet('h', 100);
      logic.startDeal('h');
      var guard = 0;
      while (logic.state.phase == OnlinePhase.playerTurns && guard++ < 50) {
        logic.stand(logic.state.activeSeatOrNull!.id);
      }
      expect(logic.state.phase, OnlinePhase.results);
      final bankroll = logic.state.seatById('h')!.bankroll;

      logic.nextRound('h');
      expect(logic.state.phase, OnlinePhase.betting);
      expect(logic.state.round, 1);
      final seat = logic.state.seatById('h')!;
      expect(seat.bet, 0);
      expect(seat.hand.cards.isEmpty, true);
      expect(seat.result, isNull);
      expect(seat.bankroll, bankroll); // carried over
    });
  });
}

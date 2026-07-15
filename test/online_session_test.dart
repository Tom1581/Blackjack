import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';

import 'support/in_memory_transport.dart';

void main() {
  group('Online session (host + guest over in-memory transport)', () {
    late InMemoryBroker broker;
    late OnlineController host;
    late OnlineController guest;

    Future<void> connectBoth() async {
      broker = InMemoryBroker();
      host = OnlineController(
        transport: broker.createClient('host'),
        isHost: true,
        roomCode: 'ROOM',
        playerName: 'Ann',
      );
      guest = OnlineController(
        transport: broker.createClient('guest'),
        isHost: false,
        roomCode: 'ROOM',
        playerName: 'Bo',
      );
      await host.start();
      await guest.start();
      await flush();
    }

    tearDown(() {
      host.dispose();
      guest.dispose();
    });

    test('guest is seated via presence and sees the broadcast state', () async {
      await connectBoth();

      expect(host.conn, OnlineConn.connected);
      expect(host.table!.seats.length, 2);
      // Guest received the host's authoritative broadcast.
      expect(guest.table, isNotNull);
      expect(guest.table!.seats.length, 2);
      expect(guest.table!.seatById('guest')!.name, 'Bo');
      expect(guest.table!.hostId, 'host');
    });

    test('both players bet and the host reflects both wagers', () async {
      await connectBoth();

      host.placeBet(100); // host acts locally
      guest.placeBet(50); // guest sends an intent to the host
      await flush();

      expect(host.table!.seatById('host')!.bet, 100);
      expect(host.table!.seatById('guest')!.bet, 50);
      // Guest sees the same after the host re-broadcasts.
      expect(guest.table!.seatById('host')!.bet, 100);
      expect(guest.table!.seatById('guest')!.bet, 50);
    });

    test('an out-of-turn action is rejected by the host', () async {
      await connectBoth();
      host.placeBet(100);
      guest.placeBet(100);
      await flush();
      host.deal();
      await flush();

      if (host.table!.phase != OnlinePhase.playerTurns) return; // dealer BJ

      final activeId = host.table!.activeSeatOrNull!.id;
      final idleId = activeId == 'host' ? 'guest' : 'host';
      final idleController = idleId == 'host' ? host : guest;
      final before = host.table!.seatById(idleId)!.hand.cards.length;

      idleController.hit(); // not their turn
      await flush();

      expect(host.table!.seatById(idleId)!.hand.cards.length, before);
    });

    test('a full round plays out and both clients converge on the result',
        () async {
      await connectBoth();
      host.placeBet(100);
      guest.placeBet(100);
      await flush();
      host.deal();
      await flush();

      // Whoever is to act stands, until the dealer settles.
      var guard = 0;
      while (host.table!.phase == OnlinePhase.playerTurns && guard++ < 50) {
        final activeId = host.table!.activeSeatOrNull!.id;
        (activeId == 'host' ? host : guest).stand();
        await flush();
      }

      expect(host.table!.phase, OnlinePhase.results);
      // Both funded seats settled.
      expect(host.table!.seatById('host')!.result, isNotNull);
      expect(host.table!.seatById('guest')!.result, isNotNull);

      // Guest's rendered state matches the host's authority.
      expect(guest.table!.phase, OnlinePhase.results);
      expect(guest.table!.seatById('host')!.bankroll,
          host.table!.seatById('host')!.bankroll);
      expect(guest.table!.seatById('guest')!.bankroll,
          host.table!.seatById('guest')!.bankroll);
      expect(guest.table!.dealer.cards.length, host.table!.dealer.cards.length);

      // Host can start the next round; guests follow.
      host.nextRound();
      await flush();
      expect(host.table!.phase, OnlinePhase.betting);
      expect(host.table!.round, 1);
      expect(guest.table!.round, 1);
      expect(guest.table!.seatById('guest')!.hand.cards.isEmpty, true);
    });

    test('a disconnecting guest is unseated on the host', () async {
      await connectBoth();
      expect(host.table!.seats.length, 2);

      await guest.transport.leave();
      await flush();

      expect(host.table!.seats.length, 1);
      expect(host.table!.seatById('guest'), isNull);
      expect(host.table!.seatById('host'), isNotNull);
    });
  });

  group('Online multi-table and capacity', () {
    late InMemoryBroker broker;
    final created = <OnlineController>[];

    setUp(() {
      broker = InMemoryBroker();
      created.clear();
    });

    tearDown(() {
      for (final c in created) {
        c.dispose();
      }
    });

    Future<OnlineController> connect(
      String id, {
      required bool host,
      String room = 'ROOM',
    }) async {
      final c = OnlineController(
        transport: broker.createClient(id),
        isHost: host,
        roomCode: room,
        playerName: id,
      );
      created.add(c);
      await c.start();
      return c;
    }

    test('four players join one table and all play a full round', () async {
      final host = await connect('host', host: true);
      final g1 = await connect('g1', host: false);
      final g2 = await connect('g2', host: false);
      final g3 = await connect('g3', host: false);
      final all = [host, g1, g2, g3];
      await flush();

      // Everyone is seated and every client sees all four seats.
      for (final c in all) {
        expect(c.table!.seats.length, 4);
        expect(c.mySeat, isNotNull);
      }

      for (final c in all) {
        c.placeBet(50);
      }
      await flush();
      expect(host.table!.seats.every((s) => s.bet == 50), true);

      host.deal();
      await flush();

      var guard = 0;
      while (host.table!.phase == OnlinePhase.playerTurns && guard++ < 100) {
        final activeId = host.table!.activeSeatOrNull!.id;
        all.firstWhere((c) => c.clientId == activeId).stand();
        await flush();
      }

      expect(host.table!.phase, OnlinePhase.results);
      // Every client converges on the same settled table.
      for (final c in all) {
        expect(c.table!.phase, OnlinePhase.results);
        for (final id in ['host', 'g1', 'g2', 'g3']) {
          expect(c.table!.seatById(id)!.result, isNotNull);
          expect(c.table!.seatById(id)!.bankroll,
              host.table!.seatById(id)!.bankroll);
        }
      }
    });

    test('a table caps at maxSeats; the overflow joiner is told it is full',
        () async {
      final host = await connect('host', host: true);
      final max = host.maxSeats;
      // host + `max` guests = one more than the table can seat.
      final guests = [
        for (var i = 0; i < max; i++) await connect('g$i', host: false),
      ];
      await flush();

      expect(host.table!.seats.length, max);
      final overflow = guests.last;
      expect(overflow.mySeat, isNull);
      expect(overflow.tableFull, isTrue);
      // The seated players are unaffected.
      expect(host.tableFull, isFalse);
      expect(guests.first.mySeat, isNotNull);
    });

    test('different room codes are fully independent tables', () async {
      final a = await connect('a', host: true, room: 'AAAA');
      final b = await connect('b', host: true, room: 'BBBB');
      await flush();

      expect(a.table!.seats.length, 1);
      expect(b.table!.seats.length, 1);

      a.placeBet(100);
      await flush();

      // Table B is untouched by activity on table A, and cannot see A's player.
      expect(a.table!.seatById('a')!.bet, 100);
      expect(b.table!.seatById('b')!.bet, 0);
      expect(b.table!.seatById('a'), isNull);
    });
  });
}

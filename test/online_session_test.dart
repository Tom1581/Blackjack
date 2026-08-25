import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_logic.dart';

import 'support/in_memory_transport.dart';

/// Let queued transport messages and short timers run.
Future<void> settle([int ms = 25]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Wait for [condition] to become true.
///
/// Anything that has to travel between two clients needs this rather than a
/// fixed sleep: a busy machine can leave a broadcast in flight past any delay
/// you pick, which shows up as a rare, confusing failure.
Future<bool> waitUntil(bool Function() condition, {int tries = 60}) async {
  for (var i = 0; i < tries; i++) {
    if (condition()) return true;
    await settle(10);
  }
  return condition();
}

void main() {
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

  /// Controllers wired for tests: the host claims its code immediately instead
  /// of spending the production probe window listening for another table.
  OnlineController make(
    String id, {
    required bool host,
    String room = 'ROOM',
    String? name,
    Duration joinTimeout = const Duration(seconds: 30),
    Duration heartbeat = const Duration(seconds: 30),
    Duration hostProbe = Duration.zero,
  }) {
    final c = OnlineController(
      transport: broker.createClient(id),
      isHost: host,
      roomCode: room,
      playerName: name ?? id,
      hostProbe: hostProbe,
      joinTimeout: joinTimeout,
      heartbeat: heartbeat,
      hostAbsentGrace: const Duration(milliseconds: 30),
    );
    created.add(c);
    return c;
  }

  Future<OnlineController> connect(
    String id, {
    required bool host,
    String room = 'ROOM',
    String? name,
  }) async {
    final c = make(id, host: host, room: room, name: name);
    await c.start();
    await settle();
    return c;
  }

  /// Place bets and wait for every one of them to reach the host. Betting is
  /// a guest intent travelling to the host and a table travelling back, so
  /// asserting on it after a fixed sleep is a race.
  Future<void> betAll(
    OnlineController host,
    Map<OnlineController, int> bets,
  ) async {
    bets.forEach((client, amount) => client.placeBet(amount));
    final landed = await waitUntil(() => bets.entries.every(
          (e) => host.table!.seatById(e.key.clientId)?.bet == e.value,
        ));
    expect(landed, isTrue, reason: 'every wager reached the host');
  }

  /// Everyone marks themselves ready, then the host deals.
  Future<void> dealRound(
    OnlineController host,
    List<OnlineController> all,
  ) async {
    for (final c in all) {
      c.setReady(true);
    }
    await waitUntil(() => host.table!.seats
        .where((s) => s.connected)
        .every((s) => s.ready));
    host.deal();
    await waitUntil(() => host.table!.phase != OnlinePhase.betting);
    // Clear insurance if it came up.
    if (host.table!.phase == OnlinePhase.insurance) {
      for (final c in all) {
        c.takeInsurance(false);
      }
      await waitUntil(() => host.table!.phase != OnlinePhase.insurance);
    }
  }

  Future<void> playOut(
    OnlineController host,
    List<OnlineController> all,
  ) async {
    var guard = 0;
    while (host.table!.phase == OnlinePhase.playerTurns && guard++ < 60) {
      final activeId = host.table!.activeSeatOrNull!.id;
      all.firstWhere((c) => c.clientId == activeId).stand();
      await settle();
    }
  }

  group('A shared table', () {
    test('guests are seated via presence and see the broadcast state',
        () async {
      final host = await connect('host', host: true, name: 'Ann');
      final guest = await connect('guest', host: false, name: 'Bo');

      expect(host.conn, OnlineConn.connected);
      expect(host.table!.seats.length, 2);
      expect(guest.table, isNotNull);
      expect(guest.table!.seats.length, 2);
      expect(guest.table!.seatById('guest')!.name, 'Bo');
      expect(guest.table!.hostId, 'host');
    });

    test('both players bet and every client sees both wagers', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);

      await betAll(host, {host: 100, guest: 50});

      expect(host.table!.seatById('host')!.bet, 100);
      expect(host.table!.seatById('guest')!.bet, 50);
      expect(guest.table!.seatById('host')!.bet, 100);
      expect(guest.table!.seatById('guest')!.bet, 50);
    });

    test('an out-of-turn action is rejected by the host', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);
      await betAll(host, {host: 100, guest: 100});
      await dealRound(host, [host, guest]);
      if (host.table!.phase != OnlinePhase.playerTurns) return;

      final activeId = host.table!.activeSeatOrNull!.id;
      final idleId = activeId == 'host' ? 'guest' : 'host';
      final idle = idleId == 'host' ? host : guest;
      final before =
          host.table!.seatById(idleId)!.hands.first.hand.cards.length;

      idle.hit();
      await settle();

      expect(
        host.table!.seatById(idleId)!.hands.first.hand.cards.length,
        before,
      );
    });

    test('a full round plays out and both clients converge', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);
      await betAll(host, {host: 100, guest: 100});
      await dealRound(host, [host, guest]);
      await playOut(host, [host, guest]);

      expect(host.table!.phase, OnlinePhase.results);
      expect(host.table!.seatById('host')!.hands.first.result, isNotNull);
      expect(host.table!.seatById('guest')!.hands.first.result, isNotNull);

      expect(guest.table!.phase, OnlinePhase.results);
      for (final id in ['host', 'guest']) {
        expect(guest.table!.seatById(id)!.bankroll,
            host.table!.seatById(id)!.bankroll);
      }
      expect(guest.table!.dealer.cards.length, host.table!.dealer.cards.length);

      host.nextRound();
      await settle();
      expect(host.table!.phase, OnlinePhase.betting);
      expect(guest.table!.round, 1);
      expect(guest.table!.seatById('guest')!.hands, isEmpty);
    });

    test('four players share one table for a whole round', () async {
      final host = await connect('host', host: true);
      final g1 = await connect('g1', host: false);
      final g2 = await connect('g2', host: false);
      final g3 = await connect('g3', host: false);
      final all = [host, g1, g2, g3];

      for (final c in all) {
        expect(c.table!.seats.length, 4);
        expect(c.mySeat, isNotNull);
      }

      await betAll(host, {for (final c in all) c: 50});
      expect(host.table!.seats.every((s) => s.bet == 50), isTrue);

      await dealRound(host, all);
      await playOut(host, all);

      expect(host.table!.phase, OnlinePhase.results);
      for (final c in all) {
        expect(c.table!.phase, OnlinePhase.results);
        for (final id in ['host', 'g1', 'g2', 'g3']) {
          expect(c.table!.seatById(id)!.hands.first.result, isNotNull);
          expect(c.table!.seatById(id)!.bankroll,
              host.table!.seatById(id)!.bankroll);
        }
      }
    });

    test('a table caps at maxSeats and the overflow joiner is told', () async {
      final host = await connect('host', host: true);
      final guests = [
        for (var i = 0; i < host.maxSeats; i++)
          await connect('g$i', host: false),
      ];

      expect(host.table!.seats.length, host.maxSeats);
      final overflow = guests.last;
      expect(overflow.mySeat, isNull);
      expect(overflow.tableFull, isTrue);
      expect(host.tableFull, isFalse);
      expect(guests.first.mySeat, isNotNull);
    });

    test('different room codes are fully independent tables', () async {
      final a = await connect('a', host: true, room: 'AAAAA');
      final b = await connect('b', host: true, room: 'BBBBB');

      expect(a.table!.seats.length, 1);
      expect(b.table!.seats.length, 1);

      a.placeBet(100);
      await settle();

      expect(a.table!.seatById('a')!.bet, 100);
      expect(b.table!.seatById('b')!.bet, 0);
      expect(b.table!.seatById('a'), isNull);
    });

    test('the whole table shares one running count', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);
      await betAll(host, {host: 100, guest: 100});
      await dealRound(host, [host, guest]);

      expect(guest.table!.cardsRemaining, host.table!.cardsRemaining);
      expect(guest.table!.runningCount, host.table!.runningCount);
      expect(guest.table!.cardsRemaining, lessThan(312));
    });
  });

  group('Nobody can act as somebody else', () {
    test('a forged actor id in an intent is ignored', () async {
      final host = await connect('host', host: true);
      final mallory = await connect('mallory', host: false);
      await connect('victim', host: false);

      expect(host.table!.seatById('victim')!.bet, 0);

      // Mallory writes the victim's id into the message body. The host takes
      // the actor from the transport, so the bet lands on Mallory's own seat.
      await mallory.transport.send('intent', {
        'from': 'victim',
        'action': 'bet',
        'amount': 900,
      });
      await settle();

      expect(host.table!.seatById('victim')!.bet, 0,
          reason: 'the victim was untouched');
      expect(host.table!.seatById('mallory')!.bet, 900,
          reason: 'the action was attributed to whoever actually sent it');
    });

    test('a forged table state from a non-host is ignored', () async {
      await connect('host', host: true);
      final mallory = await connect('mallory', host: false);
      final victim = await connect('victim', host: false);

      final realSeats = victim.table!.seats.length;
      final realRound = victim.table!.round;

      const forged = OnlineTableState(
        roomCode: 'ROOM',
        hostId: 'mallory',
        phase: OnlinePhase.results,
        round: 999,
        seq: 99999,
        seats: [
          OnlineSeat(id: 'mallory', name: 'mallory', bankroll: 999999),
          OnlineSeat(id: 'victim', name: 'victim', bankroll: 0),
        ],
      );
      await mallory.transport.send('state', forged.toJson());
      await settle();

      expect(victim.table!.hostId, 'host');
      expect(victim.table!.round, realRound);
      expect(victim.table!.seats.length, realSeats);
      expect(victim.table!.seatById('victim')!.bankroll, 1000);
      expect(victim.table!.seatById('mallory')!.bankroll, 1000);
    });

    test('a state replayed with an old sequence cannot rewind the table',
        () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);

      host.placeBet(100);
      await settle();
      final current = guest.table!;
      expect(current.seatById('host')!.bet, 100);

      // Re-send an earlier snapshot from the real host.
      final stale = current.copyWith(
        seq: 1,
        seats: [
          for (final s in current.seats) s.copyWith(bet: 0),
        ],
      );
      await host.transport.send('state', stale.toJson());
      await settle();

      expect(guest.table!.seatById('host')!.bet, 100,
          reason: 'the stale broadcast was dropped');
    });

    test('a build running a different wire version is refused', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);
      expect(guest.conn, OnlineConn.connected);

      final json = host.table!.toJson();
      json['v'] = onlineWireVersion + 7;
      json['seq'] = 99999;
      await host.transport.send('state', json);
      await settle();

      expect(guest.conn, OnlineConn.versionMismatch);
      expect(guest.isBlocked, isTrue);
    });
  });

  group('The table survives real-world interruptions', () {
    test('a wrong room code reports no table instead of spinning forever',
        () async {
      final lost = make(
        'lost',
        host: false,
        room: 'ZZZZZ',
        joinTimeout: const Duration(milliseconds: 40),
      );
      await lost.start();
      await settle(120);

      expect(lost.table, isNull);
      expect(lost.conn, OnlineConn.noTable);
      expect(lost.isBlocked, isTrue);
    });

    test('guests are told when the host leaves', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);
      expect(guest.conn, OnlineConn.connected);

      await host.transport.leave();
      await settle(120);

      expect(guest.conn, OnlineConn.hostGone);
      expect(guest.isBlocked, isTrue);
    });

    test('a dropped guest keeps their seat and their chips', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);

      // Move the guest's bankroll off the starting amount.
      await betAll(host, {host: 100, guest: 400});
      await dealRound(host, [host, guest]);
      await playOut(host, [host, guest]);
      host.nextRound();
      await settle();

      final settled = host.table!.seatById('guest')!.bankroll;
      expect(settled, isNot(1000), reason: 'sanity: the bankroll moved');

      await guest.transport.leave();
      await settle(40);

      final held = host.table!.seatById('guest');
      expect(held, isNotNull, reason: 'the seat is reserved, not deleted');
      expect(held!.connected, isFalse);
      expect(held.bankroll, settled, reason: 'no fresh 1000 minted');
    });

    test('a guest who drops mid-round still has their wager settled', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);
      await betAll(host, {host: 100, guest: 500});
      await dealRound(host, [host, guest]);
      if (host.table!.phase != OnlinePhase.playerTurns) return;

      expect(host.table!.seatById('guest')!.bankroll, 500);
      await guest.transport.leave();
      await settle(40);

      // The host plays the rest out; the dropped seat was stood, not deleted.
      var guard = 0;
      while (host.table!.phase == OnlinePhase.playerTurns && guard++ < 60) {
        host.stand();
        await settle();
      }

      final seat = host.table!.seatById('guest')!;
      expect(seat.hands.single.result, isNotNull,
          reason: 'the staked chips resolved instead of vanishing');
    });

    test('a heartbeat keeps guests fed even when nothing happens', () async {
      final host = make(
        'host',
        host: true,
        heartbeat: const Duration(milliseconds: 30),
      );
      await host.start();
      final guest = await connect('guest', host: false);
      await settle();

      final before = guest.table!.seq;
      await settle(120); // nobody does anything
      expect(guest.table!.seq, greaterThan(before),
          reason: 'the host keeps proving it is alive');
    });

    test('a brief presence blip does not tear the table down', () async {
      final host = await connect('host', host: true);
      final guest = OnlineController(
        transport: broker.createClient('guest'),
        isHost: false,
        roomCode: 'ROOM',
        playerName: 'guest',
        hostProbe: Duration.zero,
        heartbeat: const Duration(seconds: 30),
        hostAbsentGrace: const Duration(milliseconds: 400),
      );
      created.add(guest);
      await guest.start();
      await settle();
      expect(guest.conn, OnlineConn.connected);

      // The host falls off the presence roster.
      await host.transport.leave();

      await settle(60);
      expect(guest.conn, OnlineConn.connected,
          reason: 'a flicker inside the grace window is not a departure');

      await settle(500);
      expect(guest.conn, OnlineConn.hostGone,
          reason: 'but staying gone does end the table');
    });

    test('insurance is offered to the table and routed to the host', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);

      // Play rounds until the dealer turns up an ace.
      var found = false;
      for (var round = 0; round < 60 && !found; round++) {
        await betAll(host, {host: 100, guest: 100});
        for (final c in [host, guest]) {
          c.setReady(true);
        }
        await settle();
        host.deal();
        await settle();

        if (host.table!.phase == OnlinePhase.insurance) {
          found = true;
          // The guest learns about insurance only when the broadcast arrives.
          expect(await waitUntil(() => guest.needsInsurance), isTrue);
          expect(guest.table!.dealer.cards.first.rank, Rank.ace);

          final before = host.table!.seatById('guest')!.bankroll;
          guest.takeInsurance(true);
          expect(
            await waitUntil(
                () => host.table!.seatById('guest')!.insuranceAnswered),
            isTrue,
          );
          final after = host.table!.seatById('guest')!;
          // Insurance costs half the main bet, unless the stack cannot cover
          // it — in which case the host declines on the player's behalf.
          expect(after.insuranceBet, before >= 50 ? 50 : 0);
          expect(after.bankroll, before - after.insuranceBet);
          // The host still owes an answer, so the phase has not moved.
          expect(host.table!.phase, OnlinePhase.insurance);

          host.takeInsurance(false);
          expect(
            await waitUntil(
                () => host.table!.phase != OnlinePhase.insurance),
            isTrue,
          );
          break;
        }

        await playOut(host, [host, guest]);
        host.nextRound();
        await settle();
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a guest can ask the host to resend the table', () async {
      await connect('host', host: true);
      final guest = await connect('guest', host: false);
      final before = guest.table!.seq;

      guest.requestResync();
      await settle();

      expect(guest.table!.seq, greaterThan(before));
    });
  });

  group('One code, one table', () {
    test('a second host on the same code stands down', () async {
      final first = await connect('a', host: true, room: 'DUPE1');
      final guest = await connect('g', host: false, room: 'DUPE1');
      expect(guest.table!.hostId, 'a');

      final second = make(
        'b',
        host: true,
        room: 'DUPE1',
        hostProbe: const Duration(milliseconds: 60),
      );
      await second.start();
      await settle(140);

      expect(second.conn, OnlineConn.codeTaken,
          reason: 'it heard an existing table and did not claim the code');
      expect(second.table, isNull);

      // The real table is untouched.
      expect(first.table!.hostId, 'a');
      expect(guest.table!.hostId, 'a');

      first.placeBet(100);
      await settle();
      expect(guest.table!.seatById('a')!.bet, 100);
      expect(guest.table!.hostId, 'a', reason: 'no split brain');
    });
  });

  group('Betting is fair and chips are recoverable', () {
    test('the host cannot deal until everyone has finished betting', () async {
      final host = await connect('host', host: true);
      final g1 = await connect('g1', host: false);
      final g2 = await connect('g2', host: false);

      host.placeBet(5);
      await settle();
      host.deal();
      await settle();
      expect(host.table!.phase, OnlinePhase.betting,
          reason: 'g1 and g2 are still choosing chips');

      g1.setReady(true);
      g2.setReady(true);
      await settle();
      host.deal();
      await settle();

      expect(host.table!.phase, isNot(OnlinePhase.betting));
      expect(g1.table!.phase, isNot(OnlinePhase.betting));
    });

    test('a broke player can buy back in and keep playing', () async {
      final host = await connect('host', host: true);
      final guest = await connect('guest', host: false);

      // Take the guest to zero and check the UI gate opens.
      host.placeBet(0); // no-op, keeps the host out of the round
      await betAll(host, {guest: 1000});
      await dealRound(host, [host, guest]);
      await playOut(host, [host, guest]);
      host.nextRound();
      await settle();

      if (host.table!.seatById('guest')!.bankroll != 0) return; // won or pushed


      expect(guest.canRebuy, isTrue);
      guest.rebuy();
      await settle();
      expect(guest.mySeat!.bankroll, OnlineTableLogic.rebuyAmount);
      expect(guest.canRebuy, isFalse);
    });
  });
}

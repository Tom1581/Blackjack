import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/lobby/table_directory.dart';
import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/transport/realtime_transport.dart';

import 'support/in_memory_transport.dart';

Future<void> settle([int ms = 25]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Wraps a transport to count how often the advert is actually rewritten.
class _CountingTransport implements RealtimeTransport {
  final RealtimeTransport inner;
  int presenceUpdates = 0;
  int joins = 0;

  _CountingTransport(this.inner);

  @override
  String get clientId => inner.clientId;
  @override
  bool get usesServerStampedIdentity => inner.usesServerStampedIdentity;
  @override
  Stream<TransportMessage> get messages => inner.messages;
  @override
  Stream<List<PresenceMember>> get presence => inner.presence;
  @override
  Future<void> join(String room, Map<String, dynamic> data) {
    joins++;
    return inner.join(room, data);
  }

  @override
  Future<void> updatePresence(Map<String, dynamic> data) {
    presenceUpdates++;
    return inner.updatePresence(data);
  }

  @override
  Future<void> send(String event, Map<String, dynamic> payload) =>
      inner.send(event, payload);
  @override
  Future<void> leave() => inner.leave();
}

void main() {
  late InMemoryBroker broker;
  final cleanup = <Future<void> Function()>[];

  setUp(() {
    broker = InMemoryBroker();
    cleanup.clear();
  });

  tearDown(() async {
    for (final stop in cleanup) {
      await stop();
    }
  });

  LobbyAnnouncer announcer(String id) {
    final a = LobbyAnnouncer(broker.createClient(id));
    cleanup.add(a.stop);
    return a;
  }

  Future<LobbyBrowser> browser(String id) async {
    final b = LobbyBrowser(broker.createClient(id));
    cleanup.add(b.stop);
    await b.start();
    await settle();
    return b;
  }

  TableListing listing(
    String code, {
    String host = 'Ann',
    int seated = 1,
    int max = 5,
    OnlinePhase phase = OnlinePhase.betting,
    int round = 0,
  }) =>
      TableListing(
        code: code,
        hostName: host,
        seated: seated,
        maxSeats: max,
        phase: phase,
        round: round,
      );

  group('A table listing', () {
    test('round-trips through presence data', () {
      final l = listing('ABCDE',
          host: 'Bo',
          seated: 3,
          max: 5,
          phase: OnlinePhase.playerTurns,
          round: 4);
      final back = TableListing.tryParse(l.toJson())!;
      expect(back, l);
      expect(back.code, 'ABCDE');
      expect(back.hostName, 'Bo');
      expect(back.seated, 3);
      expect(back.phase, OnlinePhase.playerTurns);
      expect(back.round, 4);
    });

    test('reports seats and whether it can be joined', () {
      expect(listing('A', seated: 3, max: 5).openSeats, 2);
      expect(listing('A', seated: 3, max: 5).isJoinable, isTrue);
      expect(listing('A', seated: 5, max: 5).isJoinable, isFalse);
      expect(listing('A', seated: 5, max: 5).isFull, isTrue);
      expect(listing('A', phase: OnlinePhase.results).inProgress, isTrue);
      expect(listing('A', phase: OnlinePhase.betting).inProgress, isFalse);
    });

    test('someone merely browsing is not mistaken for a table', () {
      expect(TableListing.tryParse(const {'browsing': true}), isNull);
      expect(TableListing.tryParse(const {'c': '', 'h': 'Ann'}), isNull);
      expect(TableListing.tryParse(const {'c': 'ABCDE'}), isNull);
    });

    test('a malformed phase falls back rather than throwing', () {
      final parsed = TableListing.tryParse({
        'c': 'ABCDE',
        'h': 'Ann',
        's': 2,
        'm': 5,
        'p': 99,
      })!;
      expect(parsed.phase, OnlinePhase.betting);
    });
  });

  group('The lobby lists what is actually open', () {
    test('a hosted table shows up for everyone browsing', () async {
      final b = await browser('watcher');
      expect(b.tables, isEmpty);

      await announcer('host1').announce(listing('AAAAA', host: 'Ann'));
      await settle();

      expect(b.tables!.length, 1);
      expect(b.tables!.single.code, 'AAAAA');
      expect(b.tables!.single.hostName, 'Ann');
    });

    test('many tables run at once and are all listed', () async {
      final b = await browser('watcher');
      await announcer('h1').announce(listing('AAAAA', host: 'Ann', seated: 2));
      await announcer('h2').announce(listing('BBBBB', host: 'Bo', seated: 4));
      await announcer('h3').announce(listing('CCCCC', host: 'Cy', seated: 1));
      await settle();

      expect(b.tables!.length, 3);
      expect(
        b.tables!.map((t) => t.code).toSet(),
        {'AAAAA', 'BBBBB', 'CCCCC'},
      );
    });

    test('joinable tables come first, then the busiest', () async {
      final b = await browser('watcher');
      await announcer('h1').announce(listing('FULLL', host: 'F', seated: 5));
      await announcer('h2').announce(listing('QUIET', host: 'Q', seated: 1));
      await announcer('h3').announce(listing('BUSYY', host: 'B', seated: 4));
      await announcer('h4').announce(listing('PLAYY',
          host: 'P', seated: 3, phase: OnlinePhase.playerTurns));
      await settle();

      final codes = b.tables!.map((t) => t.code).toList();
      expect(codes.last, 'FULLL', reason: 'a full table is the least useful');
      expect(codes.indexOf('BUSYY'), lessThan(codes.indexOf('QUIET')),
          reason: 'a livelier table is more inviting than an empty one');
      expect(codes.indexOf('BUSYY'), lessThan(codes.indexOf('PLAYY')),
          reason: 'a table taking bets beats one mid-round');
    });

    test('a host leaving removes their table from the lobby', () async {
      final b = await browser('watcher');
      final a = announcer('h1');
      await a.announce(listing('AAAAA'));
      await settle();
      expect(b.tables!.length, 1);

      await a.stop();
      await settle();
      expect(b.tables, isEmpty, reason: 'presence cleans up on its own');
    });

    test('a listing stays current as the table fills and plays', () async {
      final b = await browser('watcher');
      final a = announcer('h1');
      await a.announce(listing('AAAAA', seated: 1));
      await settle();
      expect(b.tables!.single.seated, 1);

      await a.announce(listing('AAAAA', seated: 3));
      await settle();
      expect(b.tables!.single.seated, 3);
      expect(b.tables!.single.inProgress, isFalse);

      await a.announce(listing('AAAAA',
          seated: 3, phase: OnlinePhase.playerTurns, round: 2));
      await settle();
      expect(b.tables!.single.inProgress, isTrue);
      expect(b.tables!.single.round, 2);
    });

    test('re-announcing an unchanged table does not rewrite the advert',
        () async {
      final counting = _CountingTransport(broker.createClient('h1'));
      final a = LobbyAnnouncer(counting);
      cleanup.add(a.stop);

      await a.announce(listing('AAAAA', seated: 1));
      expect(counting.joins, 1);
      expect(counting.presenceUpdates, 0);

      // The host broadcasts every 2.5s; an unchanged table must stay quiet.
      for (var i = 0; i < 5; i++) {
        await a.announce(listing('AAAAA', seated: 1));
      }
      expect(counting.presenceUpdates, 0, reason: 'nothing changed');

      await a.announce(listing('AAAAA', seated: 2));
      expect(counting.presenceUpdates, 1, reason: 'a real change publishes');
    });

    test('two browsers see the same lobby without listing each other',
        () async {
      final b1 = await browser('w1');
      final b2 = await browser('w2');
      await announcer('h1').announce(listing('AAAAA'));
      await settle();

      expect(b1.tables!.length, 1);
      expect(b2.tables!.length, 1);
      expect(b1.tables!.single.code, b2.tables!.single.code);
    });
  });

  group('Hosting publishes to the lobby end to end', () {
    test('a hosted table appears, grows as players join, and then goes',
        () async {
      final watcher = await browser('watcher');

      final host = OnlineController(
        transport: broker.createClient('host'),
        isHost: true,
        roomCode: 'AAAAA',
        playerName: 'Ann',
        hostProbe: Duration.zero,
        heartbeat: const Duration(seconds: 30),
        lobbyTransport: broker.createClient('host'),
      );
      await host.start();
      await settle(60);

      expect(watcher.tables!.length, 1);
      expect(watcher.tables!.single.code, 'AAAAA');
      expect(watcher.tables!.single.hostName, 'Ann');
      expect(watcher.tables!.single.seated, 1);
      expect(watcher.tables!.single.maxSeats, host.maxSeats);

      final guest = OnlineController(
        transport: broker.createClient('guest'),
        isHost: false,
        roomCode: 'AAAAA',
        playerName: 'Bo',
        heartbeat: const Duration(seconds: 30),
      );
      await guest.start();
      await settle(60);

      expect(watcher.tables!.single.seated, 2,
          reason: 'the advert tracks the real seat count');

      guest.dispose();
      host.dispose();
      await settle(60);
      expect(watcher.tables, isEmpty);
    });

    test('an invite-only table is never advertised', () async {
      final watcher = await browser('watcher');

      final host = OnlineController(
        transport: broker.createClient('host'),
        isHost: true,
        roomCode: 'AAAAA',
        playerName: 'Ann',
        hostProbe: Duration.zero,
        heartbeat: const Duration(seconds: 30),
        lobbyTransport: broker.createClient('host'),
        listPublicly: false,
      );
      await host.start();
      await settle(60);

      expect(watcher.tables, isEmpty,
          reason: 'private tables are reachable by code only');
      // ...but the table itself is perfectly live.
      expect(host.table!.seats.length, 1);

      host.dispose();
    });

    test('a table with no lobby channel simply is not listed', () async {
      final watcher = await browser('watcher');
      final host = OnlineController(
        transport: broker.createClient('host'),
        isHost: true,
        roomCode: 'AAAAA',
        playerName: 'Ann',
        hostProbe: Duration.zero,
        heartbeat: const Duration(seconds: 30),
      );
      await host.start();
      await settle(60);

      expect(watcher.tables, isEmpty);
      expect(host.table, isNotNull);
      host.dispose();
    });
  });

  test('the lobby code can never collide with a generated room code', () {
    // Room codes come from an alphabet with no O, I, 0 or 1.
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    expect(
      lobbyRoomCode.split('').any((ch) => !alphabet.contains(ch)),
      isTrue,
      reason: 'the lobby name uses a character no room code can contain',
    );
  });
}

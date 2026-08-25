// LIVE end-to-end check against the real Supabase Realtime service.
//
// Deliberately NOT named *_test.dart, so `flutter test` never picks it up and
// the normal suite stays hermetic. Run it explicitly:
//
//     flutter test test/live/live_table_check.dart
//
// It opens three independent Supabase clients — three "phones" — puts them at
// one table by room code, and plays a complete round through the real
// OnlineController and SupabaseTransport, over the real network.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:blackjack_app/core/supabase/supabase_config.dart';
import 'package:blackjack_app/features/online/lobby/table_directory.dart';
import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/transport/supabase_transport.dart';

/// Poll until [check] passes, so the test tracks the real service rather than
/// guessing at fixed sleeps.
Future<void> waitFor(
  String what,
  bool Function() check, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('Timed out waiting for: $what');
}

void main() {
  test('three real clients play a full round on one live table', () async {
    final rng = Random();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final room =
        List.generate(5, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
    // ignore: avoid_print
    print('LIVE room code: $room');

    final clients = [
      for (var i = 0; i < 3; i++)
        SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey),
    ];
    final names = ['Ann', 'Bo', 'Cy'];
    final ids = ['live_host', 'live_g1', 'live_g2'];

    final players = <OnlineController>[];
    for (var i = 0; i < 3; i++) {
      players.add(OnlineController(
        transport: SupabaseTransport(clients[i], ids[i]),
        isHost: i == 0,
        roomCode: room,
        playerName: names[i],
      ));
    }
    final host = players.first;

    try {
      // ── Everyone joins the same room code ──────────────────────────────
      await host.start();
      await Future<void>.delayed(const Duration(seconds: 2)); // probe window
      for (final g in players.skip(1)) {
        await g.start();
      }

      await waitFor('all three seated on the host', () {
        return host.table != null && host.table!.seats.length == 3;
      });
      // ignore: avoid_print
      print('seated on host: ${host.table!.seats.map((s) => s.name).join(', ')}');

      await waitFor('all three clients rendering all three seats', () {
        return players.every((p) => p.table?.seats.length == 3);
      });
      for (final p in players) {
        expect(p.mySeat, isNotNull, reason: '${p.playerName} has a seat');
        expect(p.table!.hostId, 'live_host');
      }

      // ── Bets, from three different devices ─────────────────────────────
      for (final p in players) {
        p.placeBet(100);
      }
      await waitFor('every wager reaching the host', () {
        return host.table!.seats.every((s) => s.bet == 100);
      });
      await waitFor('every client seeing all three wagers', () {
        return players.every(
          (p) => p.table!.seats.every((s) => s.bet == 100),
        );
      });
      // ignore: avoid_print
      print('all three wagers landed and propagated');

      // ── The deal ───────────────────────────────────────────────────────
      for (final p in players) {
        p.setReady(true);
      }
      await waitFor('everyone ready', () {
        return host.table!.seats.every((s) => s.ready);
      });
      host.deal();
      await waitFor('cards out', () {
        return host.table!.phase != OnlinePhase.betting;
      });

      if (host.table!.phase == OnlinePhase.insurance) {
        // ignore: avoid_print
        print('dealer showed an ace — answering insurance');
        for (final p in players) {
          p.takeInsurance(false);
        }
        await waitFor('insurance closed', () {
          return host.table!.phase != OnlinePhase.insurance;
        });
      }

      // The dealer's hole card must not have crossed the wire.
      final guestDealer = players[1].table!.dealer;
      if (guestDealer.cards.length > 1 && !guestDealer.cards[1].faceUp) {
        expect(guestDealer.cards[1].hidden, isTrue,
            reason: 'the hole card reached the guest redacted');
        // ignore: avoid_print
        print('hole card confirmed redacted on the guest');
      }

      // ── Play it out, each player acting from their own client ──────────
      var guard = 0;
      while (host.table!.phase == OnlinePhase.playerTurns && guard++ < 30) {
        final activeId = host.table!.activeSeatOrNull!.id;
        final actor = players.firstWhere((p) => p.clientId == activeId);
        // ignore: avoid_print
        print('  ${actor.playerName} stands');
        actor.stand();
        await waitFor('turn to move on from $activeId', () {
          return host.table!.phase != OnlinePhase.playerTurns ||
              host.table!.activeSeatOrNull?.id != activeId;
        });
      }

      await waitFor('the round to settle', () {
        return host.table!.phase == OnlinePhase.results;
      });

      // ── Everyone must agree on the outcome ─────────────────────────────
      await waitFor('all three clients converging on the result', () {
        return players.every((p) =>
            p.table!.phase == OnlinePhase.results &&
            p.table!.seq >= host.table!.seq - 1);
      });

      for (final p in players) {
        for (final id in ids) {
          final mine = p.table!.seatById(id)!;
          final theirs = host.table!.seatById(id)!;
          expect(mine.bankroll, theirs.bankroll,
              reason: '${p.playerName} agrees on $id\'s bankroll');
          expect(mine.hands.first.result, theirs.hands.first.result,
              reason: '${p.playerName} agrees on $id\'s result');
        }
        expect(p.table!.dealer.cards.length, host.table!.dealer.cards.length);
        expect(p.table!.runningCount, host.table!.runningCount);
      }

      // ignore: avoid_print
      print('dealer ${host.table!.dealer.value}: '
          '${host.table!.seats.map((s) => '${s.name} '
              '${s.hands.first.hand.value} ${s.hands.first.result!.name} '
              '(\$${s.bankroll})').join(' | ')}');
      // ignore: avoid_print
      print('LIVE_SHARED_TABLE_OK — three clients, one table, one result');
    } finally {
      for (final p in players) {
        p.dispose();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      for (final c in clients) {
        await c.removeAllChannels();
        await c.dispose();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('open tables are discoverable in the live lobby', () async {
    final rng = Random();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String code() =>
        List.generate(5, (_) => alphabet[rng.nextInt(alphabet.length)]).join();

    final codeA = code();
    final codeB = code();
    // ignore: avoid_print
    print('LIVE lobby codes: $codeA, $codeB');

    final clients = [
      for (var i = 0; i < 3; i++)
        SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey),
    ];

    final hostA = LobbyAnnouncer(SupabaseTransport(clients[0], 'lobby_a'));
    final hostB = LobbyAnnouncer(SupabaseTransport(clients[1], 'lobby_b'));
    final watcher = LobbyBrowser(SupabaseTransport(clients[2], 'lobby_w'));

    try {
      await watcher.start();
      await Future<void>.delayed(const Duration(seconds: 2));

      await hostA.announce(TableListing(
        code: codeA,
        hostName: 'Ann',
        seated: 2,
        maxSeats: 5,
      ));
      await hostB.announce(TableListing(
        code: codeB,
        hostName: 'Bo',
        seated: 5,
        maxSeats: 5,
      ));

      await waitFor('both live tables appearing in the lobby', () {
        final codes = watcher.tables?.map((t) => t.code).toSet() ?? {};
        return codes.contains(codeA) && codes.contains(codeB);
      });

      final byCode = {for (final t in watcher.tables!) t.code: t};
      expect(byCode[codeA]!.hostName, 'Ann');
      expect(byCode[codeA]!.seated, 2);
      expect(byCode[codeA]!.isJoinable, isTrue);
      expect(byCode[codeB]!.isJoinable, isFalse, reason: 'Bo\'s table is full');
      // A joinable table is listed ahead of a full one.
      final order = watcher.tables!.map((t) => t.code).toList();
      expect(order.indexOf(codeA), lessThan(order.indexOf(codeB)));
      // ignore: avoid_print
      print('lobby sees ${watcher.tables!.length} table(s); '
          '$codeA joinable, $codeB full');

      // Seats filling up is reflected without re-joining the channel.
      await hostA.announce(TableListing(
        code: codeA,
        hostName: 'Ann',
        seated: 4,
        maxSeats: 5,
        phase: OnlinePhase.playerTurns,
      ));
      await waitFor('the advert tracking the table', () {
        final t = watcher.tables?.where((t) => t.code == codeA);
        return t != null && t.isNotEmpty && t.first.seated == 4;
      });
      // ignore: avoid_print
      print('$codeA now shows 4/5 and in play');

      // Closing a table takes it out of the lobby.
      await hostB.stop();
      await waitFor('the closed table disappearing', () {
        final codes = watcher.tables?.map((t) => t.code).toSet() ?? {};
        return !codes.contains(codeB);
      });
      // ignore: avoid_print
      print('LIVE_LOBBY_OK — tables listed, updated, and cleaned up');
    } finally {
      await hostA.stop();
      await hostB.stop();
      await watcher.stop();
      await Future<void>.delayed(const Duration(seconds: 1));
      for (final c in clients) {
        await c.removeAllChannels();
        await c.dispose();
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// A full online table — five players — on a phone: every seat, its name and
// its cards on screen together on a common phone, nothing clipped or broken
// mid-word on any width, and the turn badge naming whose turn it is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_screen.dart';
import 'package:blackjack_app/theme/app_theme.dart';

import 'support/in_memory_transport.dart';
import 'support/layout_checks.dart';
import 'support/real_fonts.dart';

const _names = ['Alex', 'Maya', 'Jordan', 'Priya', 'Diego'];

void main() {
  setUpAll(() async {
    expect(await loadRealFonts(), isTrue, reason: 'layout needs real fonts');
  });

  /// Alex hosts on screen; four friends join, bet, and are dealt in. Returns
  /// once the first player is to act.
  Future<(OnlineController, List<OnlineController>)> dealFullTable(
    WidgetTester tester,
    Size size,
  ) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final broker = InMemoryBroker();
    OnlineController seat(String name, {bool host = false}) => OnlineController(
          transport: broker.createClient(name.toLowerCase()),
          isHost: host,
          roomCode: 'K7MQ2XPR9D',
          playerName: name,
          hostProbe: Duration.zero,
          heartbeat: const Duration(seconds: 30),
        );

    final me = seat(_names.first, host: true);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: OnlineTableScreen(controller: me),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final friends = [for (final n in _names.skip(1)) seat(n)];
    for (final f in friends) {
      await f.start();
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(me.table!.seats, hasLength(5));

    for (final c in [me, ...friends]) {
      c.placeBet(25);
    }
    await tester.pump(const Duration(milliseconds: 100));
    for (final f in friends) {
      f.setReady(true);
    }
    await tester.pump(const Duration(milliseconds: 100));
    me.deal();
    await tester.pump(const Duration(milliseconds: 100));
    if (me.table!.phase == OnlinePhase.insurance) {
      for (final c in [me, ...friends]) {
        c.takeInsurance(false);
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    // A dealer blackjack settles the round at once; deal another if so.
    for (var round = 0;
        round < 5 && me.table!.phase == OnlinePhase.results;
        round++) {
      me.nextRound();
      await tester.pump(const Duration(milliseconds: 100));
      for (final c in [me, ...friends]) {
        c.placeBet(25);
      }
      await tester.pump(const Duration(milliseconds: 100));
      for (final f in friends) {
        f.setReady(true);
      }
      await tester.pump(const Duration(milliseconds: 100));
      me.deal();
      await tester.pump(const Duration(milliseconds: 100));
      if (me.table!.phase == OnlinePhase.insurance) {
        for (final c in [me, ...friends]) {
          c.takeInsurance(false);
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(me.table!.phase, OnlinePhase.playerTurns);
    await tester.pump(const Duration(milliseconds: 300));
    return (me, friends);
  }

  Future<void> tearDownTable(
    WidgetTester tester,
    List<OnlineController> friends,
  ) async {
    for (final f in friends) {
      f.dispose();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  for (final width in phoneWidths) {
    testWidgets('five players at ${width.toInt()} dp lay out cleanly',
        (tester) async {
      final (_, friends) =
          await dealFullTable(tester, Size(width, phoneHeight(width)));
      expect(tester.takeException(), isNull);
      for (final name in _names) {
        expect(find.textContaining(name), findsWidgets, reason: name);
      }
      expectCleanLayout(tester, where: 'five seats');
      await tearDownTable(tester, friends);
    });
  }

  testWidgets(
      'on a 411 x 731 phone all five seats show at once, above the controls',
      (tester) async {
    final (me, friends) = await dealFullTable(tester, const Size(411, 731));
    final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
    for (final name in _names) {
      final label = find.text(name == 'Alex' ? 'Alex (you)' : name);
      expect(label, findsOneWidget, reason: name);
      final pod = tester.getRect(
          find.ancestor(of: label, matching: find.byType(AnimatedContainer)));
      expect(pod.bottom, lessThanOrEqualTo(viewport.bottom),
          reason: '$name\'s seat ends at ${pod.bottom}, the table at '
              '${viewport.bottom}');
      expect(pod.top, greaterThanOrEqualTo(viewport.top));
    }
    // Three to a row.
    final alex = tester.getTopLeft(find.text('Alex (you)'));
    expect(tester.getTopLeft(find.text('Jordan')).dy, closeTo(alex.dy, 2));
    expect(tester.getTopLeft(find.text('Priya')).dy, greaterThan(alex.dy));

    // The badge says whose turn it is: "YOUR TURN" only on your own seat.
    final active = me.table!.activeSeatOrNull!;
    if (active.id == me.clientId) {
      expect(find.text('YOUR TURN'), findsOneWidget);
      expect(find.text('PLAYING'), findsNothing);
    } else {
      expect(find.text('PLAYING'), findsOneWidget);
      expect(find.text('YOUR TURN'), findsNothing);
    }
    await tearDownTable(tester, friends);
  });

  testWidgets('another player\'s turn reads PLAYING, not YOUR TURN',
      (tester) async {
    final (me, friends) = await dealFullTable(tester, const Size(411, 731));
    // Play until someone other than Alex is to act.
    for (var i = 0; i < 10; i++) {
      final active = me.table!.activeSeatOrNull;
      if (active == null || active.id != me.clientId) break;
      me.stand();
      await tester.pump(const Duration(milliseconds: 100));
    }
    final active = me.table!.activeSeatOrNull;
    expect(active, isNotNull);
    expect(active!.id, isNot(me.clientId));
    expect(find.text('PLAYING'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsNothing);
    await tearDownTable(tester, friends);
  });
}

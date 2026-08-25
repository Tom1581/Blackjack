import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_screen.dart';

import 'support/in_memory_transport.dart';

void main() {
  late InMemoryBroker broker;

  setUp(() => broker = InMemoryBroker());

  OnlineController controller(
    String id, {
    required bool host,
    String room = 'TESTS',
    Duration joinTimeout = const Duration(seconds: 30),
  }) =>
      OnlineController(
        transport: broker.createClient(id),
        isHost: host,
        roomCode: room,
        playerName: id == 'host' ? 'Ann' : 'Bo',
        hostProbe: Duration.zero,
        joinTimeout: joinTimeout,
        heartbeat: const Duration(seconds: 30),
      );

  Future<OnlineController> pumpTable(
    WidgetTester tester,
    OnlineController c,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 940));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The screen owns the controller and disposes it on teardown.
    await tester.pumpWidget(MaterialApp(home: OnlineTableScreen(controller: c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  testWidgets('the host sees the room code, the shoe HUD, and their own seat',
      (tester) async {
    await pumpTable(tester, controller('host', host: true));

    expect(find.text('TESTS'), findsOneWidget); // room code in the header
    expect(find.textContaining('(you)'), findsOneWidget);
    expect(find.text('DEAL'), findsOneWidget); // host-only
    expect(find.text('25'), findsOneWidget); // a chip
    expect(find.text('RC'), findsOneWidget); // shared running count
    expect(find.text('TC'), findsOneWidget);
  });

  testWidgets('tapping a chip places the bet and starts the betting clock',
      (tester) async {
    await pumpTable(tester, controller('host', host: true));

    await tester.tap(find.text('25'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Your bet: \$25'), findsOneWidget);
    expect(find.textContaining('Balance: \$1000'), findsOneWidget);
  });

  testWidgets('DEAL stays locked until the table is ready, then deals',
      (tester) async {
    final c = await pumpTable(tester, controller('host', host: true));

    // Nothing wagered yet, so dealing does nothing.
    await tester.tap(find.text('DEAL'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.table!.phase, OnlinePhase.betting);

    await tester.tap(find.text('25'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('DEAL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(c.table!.phase, isNot(OnlinePhase.betting));
    expect(find.text('DEAL'), findsNothing);

    // We are acting, answering insurance, or already settled.
    final acting = find.text('HIT').evaluate().isNotEmpty;
    final settled = find.textContaining('NEXT ROUND').evaluate().isNotEmpty;
    final insuring = find.textContaining('insurance').evaluate().isNotEmpty;
    expect(acting || settled || insuring, isTrue);
  });

  testWidgets('the table lays out on a small phone without overflowing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = controller('host', host: true);
    await tester.pumpWidget(MaterialApp(home: OnlineTableScreen(controller: c)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'betting bar fits');

    // CLEAR / READY / DEAL share one row on the narrowest common phone.
    expect(find.text('CLEAR'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('DEAL'), findsOneWidget);

    await tester.tap(find.text('25'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('DEAL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'action bar fits too');
  });

  testWidgets('two seat pods fit side by side on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final host = controller('host', host: true);
    await host.start();

    final guest = controller('guest', host: false);
    await tester.pumpWidget(
      MaterialApp(home: OnlineTableScreen(controller: guest)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    final ann = tester.getTopLeft(find.text('Ann'));
    final bo = tester.getTopLeft(find.text('Bo (you)'));
    expect(ann.dy, bo.dy, reason: 'both seats share a row rather than stacking');

    host.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('a guest waiting on a dead room code is told, not left spinning',
      (tester) async {
    await pumpTable(
      tester,
      controller(
        'guest',
        host: false,
        room: 'NOPE9',
        joinTimeout: const Duration(milliseconds: 400),
      ),
    );

    expect(find.text('Connecting to the table…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('No table with code NOPE9'), findsOneWidget);
    expect(find.text('BACK'), findsOneWidget);
    expect(find.text('Connecting to the table…'), findsNothing);
  });

  testWidgets('a guest is told when the host leaves', (tester) async {
    final host = controller('host', host: true);
    await host.start();

    final guest = await pumpTable(tester, controller('guest', host: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(guest.conn, OnlineConn.connected);

    // The host closes their screen — the whole table goes with it once the
    // presence blip grace period has passed.
    host.dispose();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('The host left'), findsOneWidget);
    expect(find.text('LEAVE TABLE'), findsOneWidget);
  });

  testWidgets('a guest sees the host and their own seat side by side',
      (tester) async {
    final host = controller('host', host: true);
    await host.start();

    await pumpTable(tester, controller('guest', host: false));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bo (you)'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('DEAL'), findsNothing, reason: 'guests do not deal');
    expect(find.text('READY'), findsOneWidget);
    expect(
      find.text('The host deals when everyone is ready.'),
      findsOneWidget,
    );

    host.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  });
}

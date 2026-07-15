import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_table_screen.dart';

import 'support/in_memory_transport.dart';

void main() {
  Future<OnlineController> pumpHostTable(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final broker = InMemoryBroker();
    final host = OnlineController(
      transport: broker.createClient('host'),
      isHost: true,
      roomCode: 'TEST',
      playerName: 'Ann',
    );
    // The screen owns the controller and disposes it on teardown.
    await tester.pumpWidget(
      MaterialApp(home: OnlineTableScreen(controller: host)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return host;
  }

  testWidgets('online table shows the room code and host betting controls',
      (tester) async {
    await pumpHostTable(tester);

    expect(find.text('TEST'), findsOneWidget); // room code in header
    expect(find.text('DEAL'), findsOneWidget); // host-only
    expect(find.text('25'), findsOneWidget); // a chip
    expect(find.textContaining('(you)'), findsOneWidget); // host's own seat
  });

  testWidgets('tapping a chip places the host bet', (tester) async {
    await pumpHostTable(tester);

    await tester.tap(find.text('25'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Your bet: \$25'), findsOneWidget);
  });

  testWidgets('host can deal and the table leaves the betting phase',
      (tester) async {
    await pumpHostTable(tester);

    await tester.tap(find.text('25'));
    await tester.pump();
    await tester.tap(find.text('DEAL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Once dealt we are no longer in the betting phase, so DEAL is gone.
    expect(find.text('DEAL'), findsNothing);
    // We are either taking our turn or (rarely) already at results.
    final acting = find.text('HIT').evaluate().isNotEmpty;
    final settled = find.text('NEXT ROUND').evaluate().isNotEmpty;
    expect(acting || settled, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/supabase/supabase_service.dart';
import 'package:blackjack_app/features/online/lobby/table_directory.dart';
import 'package:blackjack_app/features/online/online_entry_screen.dart';
import 'package:blackjack_app/features/online/online_providers.dart';
import 'package:blackjack_app/features/online/online_state.dart';

import 'support/in_memory_transport.dart';

void main() {
  late InMemoryBroker broker;
  final announcers = <LobbyAnnouncer>[];

  setUp(() {
    broker = InMemoryBroker();
    announcers.clear();
    SharedPreferences.setMockInitialValues({
      'online_player_id': 'me',
      'online_player_name': 'Zed',
    });
  });

  tearDown(() async {
    for (final a in announcers) {
      await a.stop();
    }
    AppSupabase.resetForTest();
  });

  /// Online needs the backend up; single-player never does. Tests say which
  /// world they are in rather than inheriting whatever ran before.
  Future<void> setBackendUp(bool up) async {
    AppSupabase.resetForTest();
    AppSupabase.initializer =
        up ? () async {} : () async => throw StateError('offline');
    await AppSupabase.tryInitialize();
  }

  Future<void> host(
    String code, {
    required String name,
    int seated = 1,
    int max = 5,
    OnlinePhase phase = OnlinePhase.betting,
  }) async {
    final a = LobbyAnnouncer(broker.createClient('h_$code'));
    announcers.add(a);
    await a.announce(TableListing(
      code: code,
      hostName: name,
      seated: seated,
      maxSeats: max,
      phase: phase,
    ));
  }

  Future<void> pumpEntry(WidgetTester tester, {bool backendUp = true}) async {
    await setBackendUp(backendUp);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportFactoryProvider.overrideWithValue(broker.createClient),
        ],
        child: const MaterialApp(home: OnlineEntryScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('the lobby lists the tables that are open right now',
      (tester) async {
    await host('AAAAA', name: 'Ann', seated: 2);
    await host('BBBBB', name: 'Bo', seated: 4);

    await pumpEntry(tester);

    expect(find.text('OPEN TABLES'), findsOneWidget);
    expect(find.text('2 live'), findsOneWidget);
    expect(find.text("Ann's table"), findsOneWidget);
    expect(find.text("Bo's table"), findsOneWidget);
    expect(find.textContaining('AAAAA  ·  2/5'), findsOneWidget);
    expect(find.textContaining('BBBBB  ·  4/5'), findsOneWidget);
    expect(find.text('JOIN'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty lobby says so instead of showing nothing',
      (tester) async {
    await pumpEntry(tester);

    expect(find.text('none yet'), findsOneWidget);
    expect(
      find.textContaining('Nobody is hosting right now'),
      findsOneWidget,
    );
    expect(find.text('JOIN'), findsNothing);
  });

  testWidgets('a full table is shown but cannot be joined', (tester) async {
    await host('AAAAA', name: 'Ann', seated: 5);
    await host('BBBBB', name: 'Bo', seated: 2);

    await pumpEntry(tester);

    expect(find.text('FULL'), findsOneWidget);
    expect(find.text('JOIN'), findsOneWidget, reason: 'only Bo is joinable');

    // The joinable table is listed above the full one.
    final bo = tester.getTopLeft(find.text("Bo's table"));
    final ann = tester.getTopLeft(find.text("Ann's table"));
    expect(bo.dy, lessThan(ann.dy));
  });

  testWidgets('a table appearing while you watch shows up on its own',
      (tester) async {
    await pumpEntry(tester);
    expect(find.text("Ann's table"), findsNothing);

    await host('AAAAA', name: 'Ann', seated: 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Ann's table"), findsOneWidget);
    expect(find.text('1 live'), findsOneWidget);
  });

  testWidgets('many tables are capped with a count of the rest',
      (tester) async {
    for (var i = 0; i < 9; i++) {
      await host('TBL0$i', name: 'H$i', seated: 2);
    }

    await pumpEntry(tester);

    expect(find.text('9 live'), findsOneWidget);
    expect(find.text('JOIN'), findsNWidgets(6), reason: 'the list is capped');
    expect(find.textContaining('+3 more open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hosting can be switched between listed and invite only',
      (tester) async {
    await pumpEntry(tester);

    expect(
      find.text('Invite only — friends with the code'),
      findsOneWidget,
      reason: 'invite-only by default: the host deals, so strangers are '
          'something you opt into, not something you land in',
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(
      find.text('Listed in the lobby — anyone can join'),
      findsOneWidget,
    );
  });

  testWidgets('joining by code is still offered alongside the list',
      (tester) async {
    await pumpEntry(tester);

    expect(find.text('HOST A NEW TABLE'), findsOneWidget);
    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
    expect(find.text('CREATE A TABLE'), findsOneWidget);
    expect(find.text('JOIN TABLE'), findsOneWidget);
  });

  testWidgets('a player can enter a twelve-character display name',
      (tester) async {
    await pumpEntry(tester);

    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Test Host');
    await tester.pump();

    expect(tester.widget<TextField>(nameField).controller!.text, 'Test Host');

    // The UI guard mirrors the database's 1–12 character rule, so a name
    // cannot reach a create/join request that the service will reject.
    await tester.enterText(nameField, 'abcdefghijklmnop');
    await tester.pump();
    expect(
        tester.widget<TextField>(nameField).controller!.text, 'abcdefghijkl');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a backend that is down offers a retry, not a dead end',
      (tester) async {
    await pumpEntry(tester, backendUp: false);

    expect(find.text('Online play is unavailable'), findsOneWidget);
    expect(find.text('TRY AGAIN'), findsOneWidget);
    expect(find.text('Back to single player'), findsOneWidget);
    // The lobby is not shown, and nothing threw on the way here.
    expect(find.text('OPEN TABLES'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying a recovered backend brings the lobby back',
      (tester) async {
    await pumpEntry(tester, backendUp: false);
    expect(find.text('Online play is unavailable'), findsOneWidget);

    // The connection comes back, and the player taps Try again.
    AppSupabase.initializer = () async {};
    await host('AAAAA', name: 'Ann', seated: 2);
    await tester.tap(find.text('TRY AGAIN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Online play is unavailable'), findsNothing);
    expect(find.text('OPEN TABLES'), findsOneWidget);
    expect(find.text("Ann's table"), findsOneWidget);
  });
}

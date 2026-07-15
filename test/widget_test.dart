// Widget tests for the blackjack table — focused on the betting surface, which
// is fully self-contained (no ads, prefs, or network) and so is deterministic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:blackjack_app/features/table/table_screen.dart';
import 'package:blackjack_app/features/table/table_provider.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

void main() {
  // Use a phone-sized surface so the vertical table layout doesn't overflow the
  // default 800×600 test viewport.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Future<void> pumpTable(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 920));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_wrap(const TableScreen(), overrides: overrides));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('table opens in betting phase with a single main spot',
      (tester) async {
    await pumpTable(tester);

    expect(find.text('DEAL'), findsOneWidget);
    // 'MAIN' appears both as the felt circle label and the bet-target tab.
    expect(find.text('MAIN'), findsWidgets);
    // No multi-hand spots when only one hand is configured.
    expect(find.text('HAND 1'), findsNothing);
    expect(find.text('SIDE'), findsWidgets);
  });

  testWidgets('tapping a chip registers a main bet on the felt',
      (tester) async {
    await pumpTable(tester);

    await tester.tap(find.text('25'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The main betting circle now shows its running total.
    expect(find.text('MAIN · \$25'), findsOneWidget);
  });

  testWidgets('three-hand mode paints three main betting spots',
      (tester) async {
    await pumpTable(
      tester,
      overrides: [spotCountProvider.overrideWith((ref) => 3)],
    );

    // 'HAND 1' shows on the felt AND as the active bet-target tab; the other
    // two spots appear only on the felt.
    expect(find.text('HAND 1'), findsWidgets);
    expect(find.text('HAND 2'), findsOneWidget);
    expect(find.text('HAND 3'), findsOneWidget);
    // The single-spot 'MAIN' label is gone in multi-hand mode.
    expect(find.text('MAIN'), findsNothing);
  });

  testWidgets('a chip lands on the selected hand in multi-hand mode',
      (tester) async {
    await pumpTable(
      tester,
      overrides: [spotCountProvider.overrideWith((ref) => 2)],
    );

    // Select the second hand, then drop a chip.
    await tester.tap(find.text('HAND 2'));
    await tester.pump();
    await tester.tap(find.text('50'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The bet must land on hand 2 — hand 1 stays empty.
    expect(find.text('HAND 2 · \$50'), findsOneWidget);
    expect(find.text('HAND 1'), findsOneWidget);
  });
}

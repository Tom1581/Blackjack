// The lobby's table settings on a small phone: every row, including the ones
// that only appear once another is switched on, lays out without overflow and
// persists.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/rules/rules_store.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/lobby/lobby_screen.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/theme/app_theme.dart';

import 'support/real_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await loadRealFonts(), isTrue, reason: 'layout needs real fonts');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablePrefs.resetForTest();
    RulesStore.resetForTest();
    StrategyCoach.resetForTest();
  });

  Future<ProviderContainer> pumpLobby(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const LobbyScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 1200));
    return container;
  }

  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('every settings row fits a 360dp phone', (tester) async {
    final c = await pumpLobby(tester);

    await scrollTo(tester, find.text('Index plays (Illustrious 18)'));
    expect(find.text('Bet spread coach'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Turn the count HUD off: the count-check row appears.
    await scrollTo(tester, find.text('Show Hi-Lo Count HUD'));
    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(showCountProvider), isFalse);
    expect(find.text('Count check quiz'), findsOneWidget);
    expect(TablePrefs.showCount, isFalse, reason: 'saved for next launch');

    // Turn the bet coach on: the unit chips appear, and fit.
    await scrollTo(tester, find.text('Bet spread coach'));
    final coachSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Bet spread coach'),
        matching: find.byType(Row),
      ).first,
      matching: find.byType(Switch),
    );
    await tester.tap(coachSwitch);
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(betCoachProvider), isTrue);
    await scrollTo(tester, find.text('Unit'));
    expect(find.text('\$100'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('\$10').last);
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(betUnitProvider), 10);
    expect(TablePrefs.betUnit, 10);

    // The shoe row now offers eight decks.
    await scrollTo(tester, find.text('8 D'));
    await tester.tap(find.text('8 D'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(shoeModeProvider), ShoeMode.eightDeck);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the rule picker lists the surrender tables', (tester) async {
    await pumpLobby(tester);
    await scrollTo(tester, find.text('Table rules'));
    await tester.tap(find.text('Table rules'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('H17 + Surrender'), findsOneWidget);
    expect(find.text('S17 + Surrender'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}

// The practice table's settings on a small phone: every row of the Practice
// Setup sheet, including the ones that only appear once another is switched
// on, lays out without overflow and persists.

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

  /// Open Practice Setup from its card at the bottom of the home screen.
  Future<void> openSetup(WidgetTester tester) async {
    final card = find.byKey(const ValueKey('home-practice-setup'));
    await tester.scrollUntilVisible(card, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('PRACTICE SETUP'), findsWidgets);
  }

  /// Scroll the Practice Setup sheet until [target] shows — [up] for a row
  /// above the current position.
  Future<void> scrollTo(WidgetTester tester, Finder target,
      {bool up = false}) async {
    await tester.scrollUntilVisible(target, up ? -200 : 200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('practice-setup-sheet')),
              matching: find.byType(Scrollable),
            )
            .first);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('every settings row fits a 360dp phone', (tester) async {
    final c = await pumpLobby(tester);
    await openSetup(tester);

    await scrollTo(tester, find.text('Index plays (Illustrious 18)'));
    expect(find.text('Bet spread coach'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Turn the count HUD off: the count-check row appears.
    await scrollTo(tester, find.text('Show Hi-Lo Count HUD'));
    await tester.tap(find.byKey(const ValueKey('setup-show-count')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(showCountProvider), isFalse);
    expect(find.text('Count check quiz'), findsOneWidget);
    expect(TablePrefs.showCount, isFalse, reason: 'saved for next launch');

    // Turn the bet coach on: the unit chips appear, and fit.
    await scrollTo(tester, find.text('Bet spread coach'));
    final coachSwitch = find.descendant(
      of: find
          .ancestor(
            of: find.text('Bet spread coach'),
            matching: find.byType(Row),
          )
          .first,
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

    // The shoe row offers eight decks, spelled out.
    await scrollTo(tester, find.text('8 decks'), up: true);
    await tester.tap(find.text('8 decks'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.read(shoeModeProvider), ShoeMode.eightDeck);
    expect(find.text('Continuous shuffle'), findsOneWidget,
        reason: 'no more "C.S."');
    expect(tester.takeException(), isNull);

    // The explainer sits with the count settings it explains.
    await scrollTo(tester, find.text('How Hi-Lo counting works'));
    await tester.tap(find.text('How Hi-Lo counting works'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('HOW HI-LO COUNTING WORKS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Closing the sheet, the home card shows the new table.
    Navigator.of(
            tester.element(find.byKey(const ValueKey('practice-setup-sheet'))))
        .pop();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('8 decks · H17 · DAS · 3:2'), findsOneWidget);
    expect(find.text('Count hidden'), findsOneWidget);
    expect(find.text('Bet coach'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the rule picker lists the surrender tables', (tester) async {
    await pumpLobby(tester);
    await openSetup(tester);
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

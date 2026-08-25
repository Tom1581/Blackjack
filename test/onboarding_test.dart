import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/onboarding/onboarding.dart';
import 'package:blackjack_app/features/onboarding/onboarding_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('The intro flag', () {
    test('a fresh install has not seen it', () async {
      expect(await Onboarding.seen(), isFalse);
    });

    test('it is only shown once', () async {
      await Onboarding.markSeen();
      expect(await Onboarding.seen(), isTrue);
    });
  });

  group('The intro itself', () {
    Future<int> pumpIntro(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var doneCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: OnboardingScreen(onDone: () => doneCalls++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return doneCalls;
    }

    testWidgets('it opens on what the app is for', (tester) async {
      await pumpIntro(tester);
      expect(find.textContaining('Count cards'), findsOneWidget);
      expect(find.text('NEXT'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('it explains the count before asking anyone to use it',
        (tester) async {
      await pumpIntro(tester);
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      expect(find.text('The Hi-Lo count'), findsOneWidget);
      // The whole system, on one screen.
      expect(find.text('2–6'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('7–9'), findsOneWidget);
      expect(find.text('10–A'), findsOneWidget);
      expect(find.text('−1'), findsOneWidget);
    });

    testWidgets('the last page ends on a deal button', (tester) async {
      await pumpIntro(tester);
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();

      expect(find.text('DEAL ME IN'), findsOneWidget);
      expect(find.text('NEXT'), findsNothing);
      // Skip is pointless on the final page.
      expect(find.text('Skip'), findsNothing);
      expect(find.textContaining('five players at one table'), findsOneWidget);
    });

    testWidgets('finishing marks the intro seen and hands control back',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var done = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: OnboardingScreen(onDone: () => done++)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DEAL ME IN'));
      await tester.pumpAndSettle();

      expect(done, 1);
      expect(await Onboarding.seen(), isTrue);
    });

    testWidgets('skipping also counts as having seen it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var done = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: OnboardingScreen(onDone: () => done++)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(done, 1);
      expect(await Onboarding.seen(), isTrue,
          reason: 'nobody should be shown an intro they already dismissed');
    });
  });
}

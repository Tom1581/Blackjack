// Hi-Lo Training on a phone: the hub and every mode played end to end
// through the real screens, on 360dp and 320dp phones with the real fonts.
// The logic behind them is in hilo_training_test.dart.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/rules/rules_store.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game.dart';
import 'package:blackjack_app/features/hilo_training/hilo_text.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_progress.dart';
import 'package:blackjack_app/features/hilo_training/hilo_setup_screens.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_screen.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_session.dart';
import 'package:blackjack_app/features/hilo_training/widgets/count_quiz_panel.dart';
import 'package:blackjack_app/features/hilo_training/widgets/hilo_table_view.dart';
import 'package:blackjack_app/features/lobby/lobby_screen.dart';
import 'package:blackjack_app/theme/app_theme.dart';

import 'support/real_fonts.dart';

/// Daily Challenge #3.
DateTime _now() => DateTime(2026, 10, 1, 20, 15);

const _small = Size(320, 568);
const _phone = Size(360, 640);

Future<void> _open(WidgetTester tester, Size size, {Widget? home}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: home ?? const HiLoTrainingScreen(now: _now),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 3));
}

/// Tap, then let a pushed route through its offstage first frame and its
/// transition — 800 ms for this Flutter's Android page transition — so the
/// screen underneath is offstage again before anything is looked for.
Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 900));
  expect(tester.takeException(), isNull);
}

Finder _key(String k) => find.byKey(ValueKey(k));

/// Deal until the dealer asks, checking the felt fits at every step.
Future<void> _dealUntilAsked(WidgetTester tester) async {
  for (var i = 0; i < 300; i++) {
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    if (_key('hilo-check').evaluate().isNotEmpty) return;
  }
  fail('the dealer never asked');
}

/// The question the dealer is asking, read off the table.
HiLoQuestion _question(WidgetTester tester) => tester
    .widget<HiLoTableView>(find.byType(HiLoTableView))
    .session
    .openQuestion!;

/// The count the dealer is asking for.
int _truth(WidgetTester tester) => _question(tester).answer;

Future<void> _enter(WidgetTester tester, int value) async {
  if (value < 0) await tester.tap(_key('hilo-key-sign'));
  for (final d in value.abs().toString().split('')) {
    await tester.tap(_key('hilo-key-$d'));
  }
  await tester.pump();
  await tester.tap(_key('hilo-check'));
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
}

Future<void> _continue(WidgetTester tester) async {
  await tester.ensureVisible(_key('hilo-continue'));
  await tester.tap(_key('hilo-continue'));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await loadRealFonts(), isTrue, reason: 'layout needs real fonts');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('The hub', () {
    for (final size in const [_phone, _small]) {
      testWidgets('lays out on a ${size.width.toInt()}dp phone, fresh',
          (tester) async {
        await _open(tester, size);
        expect(find.text('Rookie'), findsOneWidget);
        expect(find.text('DAILY CHALLENGE #3'), findsOneWidget);
        expect(_key('hilo-daily-play'), findsOneWidget);
        for (final mode in ['survival', 'duel', 'practice']) {
          await tester.ensureVisible(_key('hilo-mode-$mode'));
          await tester.pump();
        }
        await tester.ensureVisible(find.text('HOW SCORING WORKS'));
        await tester.pump();
        expect(find.text('ACHIEVEMENTS  0/15'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _close(tester);
      });
    }

    testWidgets('opens the shared Daily and Survival board sheets',
        (tester) async {
      await _open(tester, _small);

      await _tap(tester, _key('hilo-daily-board'));
      expect(find.text("TODAY'S TOP 100"), findsOneWidget);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.text("TODAY'S TOP 100"))).pop();
      await tester.pump(const Duration(milliseconds: 900));

      await _tap(tester, _key('hilo-survival-board'));
      expect(find.text('SURVIVAL'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });

    testWidgets('shows a player\'s records', (tester) async {
      const profile = HiLoProfile(
        xp: 1200,
        games: 12,
        questions: 100,
        correct: 88,
        bestStreak: 14,
        survivalTop: [4210, 3000],
        survivalBestLevel: 6,
        practiceBest: 5000,
        dailyLastPlayed: 3,
        dailyStreak: 3,
        dailyScores: {1: 1800, 2: 2200, 3: 2450},
        duels: 2,
        achievements: {
          HiLoAchievement.firstCount,
          HiLoAchievement.quickDraw,
          HiLoAchievement.regular,
        },
      );
      SharedPreferences.setMockInitialValues(
          {'hilo_training_profile': jsonEncode(profile.toJson())});
      await _open(tester, _small);
      expect(find.text('Counter'), findsOneWidget);
      expect(find.textContaining('88% right'), findsOneWidget);
      expect(find.text('2,450 pts'), findsOneWidget);
      expect(_key('hilo-daily-replay'), findsOneWidget);
      expect(find.textContaining('Next shoe in 3h 45m'), findsOneWidget);
      expect(find.text('BEST 4,210 · LEVEL 6'), findsOneWidget);
      expect(find.text('2 DUELS PLAYED'), findsOneWidget);
      expect(find.text('ACHIEVEMENTS  3/15'), findsOneWidget);
      await tester.ensureVisible(find.text('#1').first);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _tap(tester, find.text('SEE ALL'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Poker Face'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  });

  group('Practice', () {
    testWidgets('a perfect game at a full table, casino pace, 320dp',
        (tester) async {
      await _open(tester, _small);
      await _tap(tester, _key('hilo-mode-practice'));
      expect(find.text('PRACTICE'), findsOneWidget);
      await _tap(tester, find.text('5').first); // players
      await _tap(tester, find.text('Casino'));
      await _tap(tester, find.text('Often'));
      await _tap(tester, find.text('5').last); // questions
      await _tap(tester, find.text('DEAL'));
      expect(find.text('KEEP THE COUNT — THE DEALER WILL ASK'), findsOneWidget);

      for (var q = 1; q <= 5; q++) {
        await _dealUntilAsked(tester);
        expect(find.text('$q / 5'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing,
            reason: 'practice has no clock');
        await _enter(tester, _truth(tester));
        expect(find.text('SPOT ON'), findsOneWidget);
        expect(_key('hilo-points'), findsOneWidget);
        // The combo steps up on the third right answer in a row.
        expect(_key('hilo-combo-up'), q == 3 ? findsOneWidget : findsNothing);
        expect(
            find.text(q == 5 ? 'SEE RESULTS' : 'KEEP DEALING'), findsOneWidget);
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('PERFECT COUNT'), findsOneWidget);
      expect(find.text('NEW PERSONAL BEST'), findsOneWidget);
      expect(find.text('CHALLENGE A FRIEND'), findsOneWidget);
      expect(find.text('ACHIEVEMENT UNLOCKED'), findsOneWidget);
      expect(find.text('Casino Speed'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final profile = await HiLoTrainingProgress.loadProfile();
      expect(profile.correct, 5);
      expect(profile.practiceBest, greaterThan(0));

      // DONE goes back to the settings, and back again to the hub.
      await _tap(tester, find.text('DONE'));
      expect(find.text('DEAL'), findsOneWidget);
      await _tap(tester, find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('BEST ${points(profile.practiceBest)}'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('leaving the app pauses the dealer', (tester) async {
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-mode-practice'));
      await _tap(tester, find.text('DEAL'));
      await tester.pump(const Duration(seconds: 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('RESUME'), findsOneWidget);
      expect(find.text('PAUSED'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('RESUME'), findsOneWidget,
          reason: 'waits for the player to come back to it');
      await _tap(tester, find.text('RESUME'));
      expect(find.text('PAUSE'), findsOneWidget);
      // FINISH before any question simply leaves.
      await _tap(tester, find.text('FINISH'));
      expect(find.text('DEAL'), findsOneWidget);
      await _close(tester);
    });
  });

  group('The Daily Challenge', () {
    testWidgets('one ranked game on the clock, then replays are practice',
        (tester) async {
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-daily-play'));
      expect(find.text('DAILY #3'), findsOneWidget);
      expect((await HiLoTrainingProgress.loadProfile()).playedDaily(3), isTrue,
          reason: 'the ranked try counts from the first card');

      // Question 1: let the clock run out.
      await _dealUntilAsked(tester);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('TIME\'S UP'), findsOneWidget);
      expect(find.text('No answer in time'), findsOneWidget);
      await _continue(tester);

      for (var q = 2; q <= HiLoDaily.questions; q++) {
        await _dealUntilAsked(tester);
        await _enter(tester, q.isEven ? _truth(tester) : _truth(tester) + 7);
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('DAILY #3 · OFFICIAL'), findsOneWidget);
      expect(find.text('REPLAY THIS SHOE'), findsOneWidget);
      final official =
          (await HiLoTrainingProgress.loadProfile()).dailyScores[3];
      expect(official, greaterThan(0));

      await _tap(tester, find.text('DONE'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(_key('hilo-daily-score'), findsOneWidget);

      await _tap(tester, _key('hilo-daily-replay'));
      for (var q = 1; q <= HiLoDaily.questions; q++) {
        await _dealUntilAsked(tester);
        await _enter(tester, _truth(tester));
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('DAILY #3 · REPLAY'), findsOneWidget);
      expect(find.text('no XP'), findsOneWidget);
      expect(
          (await HiLoTrainingProgress.loadProfile()).dailyScores[3], official,
          reason: 'a perfect replay does not replace it');
      await _close(tester);
    });
  });

  group('Survival', () {
    testWidgets('three misses and it is over', (tester) async {
      await _open(tester, _small);
      await _tap(tester, _key('hilo-mode-survival'));
      expect(find.text('SURVIVAL'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNWidgets(3));
      for (var miss = 1; miss <= 3; miss++) {
        await _dealUntilAsked(tester);
        await _enter(tester, 99);
        expect(find.text('NOT QUITE'), findsOneWidget);
        expect(find.byIcon(Icons.heart_broken), findsWidgets);
        if (miss < 3) {
          expect(find.text('KEEP DEALING'), findsOneWidget);
        } else {
          expect(find.text('SEE RESULTS'), findsOneWidget);
        }
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('GAME OVER · LEVEL 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });

    testWidgets('a new best mid-run, then the dealer levels up',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'hilo_training_profile': jsonEncode(
            const HiLoProfile(survivalTop: [150], survivalBestLevel: 1)
                .toJson()),
      });
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-mode-survival'));
      expect(find.text('BEST 150'), findsOneWidget);
      for (var q = 1; q <= 5; q++) {
        await _dealUntilAsked(tester);
        await _enter(tester, _truth(tester));
        await _continue(tester);
        if (q == 1) {
          expect(find.textContaining('NEW BEST!'), findsOneWidget,
              reason: 'flashed the moment the old best is passed');
          expect(find.text('NEW BEST'), findsOneWidget);
        }
      }
      // The level-up note was on the fifth verdict; the flash follows it.
      expect(find.text('LEVEL 2'), findsOneWidget);
      expect(find.textContaining('Level 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await _tap(tester, find.text('FINISH'));
      expect(find.text('End this game?'), findsOneWidget,
          reason: 'answers are at stake');
      await _tap(tester, _key('hilo-end-game'));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('GAME OVER · LEVEL 2'), findsOneWidget);
      await _close(tester);
    });
  });

  group('Duel', () {
    testWidgets('secret answers, the reveal and a winner', (tester) async {
      await _open(tester, _small);
      await _tap(tester, _key('hilo-mode-duel'));
      await tester.enterText(_key('hilo-duel-name-0'), 'Ann');
      await tester.enterText(_key('hilo-duel-name-1'), 'Bo');
      await tester.pump();
      await _tap(tester, find.text('START THE DUEL'));
      expect(find.text('BOTH OF YOU KEEP THE COUNT'), findsOneWidget);

      for (var q = 1; q <= 5; q++) {
        await _dealUntilAsked(tester);
        for (var turn = 0; turn < 2; turn++) {
          final annsTurn = find.text('ANN\'S COUNT').evaluate().isNotEmpty;
          expect(find.text(annsTurn ? 'ANN\'S COUNT' : 'BO\'S COUNT'),
              findsOneWidget);
          final truth = _truth(tester);
          await _enter(tester, annsTurn ? truth : truth + 9);
          if (turn == 0) {
            expect(find.text('PASS THE PHONE'), findsOneWidget);
            expect(_key('hilo-answer'), findsNothing,
                reason: 'the first answer stays hidden');
            await _tap(tester, _key('hilo-ready'));
          }
        }
        expect(find.text('THE REVEAL'), findsOneWidget);
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('ANN WINS'), findsOneWidget);
      expect(find.text('REMATCH'), findsOneWidget);
      expect(find.text('CHALLENGE A FRIEND'), findsNothing);
      expect(tester.takeException(), isNull);
      expect((await HiLoTrainingProgress.loadProfile()).duels, 1);
      expect(await HiLoTrainingProgress.loadDuelNames(), ['Ann', 'Bo']);
      await _close(tester);
    });
  });

  group('Challenge codes', () {
    testWidgets('a friend\'s code deals their shoe and sets the target',
        (tester) async {
      final code = const HiLoChallenge(
        seed: 31337,
        config: HiLoTrainingConfig(
          players: 2,
          pace: HiLoPace.brisk,
          frequency: HiLoQuizFrequency.often,
          questions: 5,
        ),
        survival: false,
        score: 100,
      ).encode();
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-enter-code'));
      await tester.enterText(_key('hilo-code-field'), 'ABCD-EFGH-JKM');
      await tester.pump();
      expect(_key('hilo-code-error'), findsOneWidget);
      await tester.enterText(_key('hilo-code-field'), code.toLowerCase());
      await tester.pump();
      expect(find.text('SCORE TO BEAT: 100'), findsOneWidget);
      await _tap(tester, _key('hilo-code-play'));
      expect(find.text('CHALLENGE'), findsOneWidget);
      expect(find.text('TO BEAT 100'), findsOneWidget);

      for (var q = 1; q <= 5; q++) {
        await _dealUntilAsked(tester);
        await _enter(tester, _truth(tester));
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('CHALLENGE WON'), findsOneWidget);
      expect(find.text('Challenge Accepted'), findsOneWidget);
      expect(find.text('TRY THIS SHOE AGAIN'), findsOneWidget);
      await _close(tester);
    });
  });

  testWidgets('the lobby opens Hi-Lo Training', (tester) async {
    TablePrefs.resetForTest();
    RulesStore.resetForTest();
    StrategyCoach.resetForTest();
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: buildAppTheme(), home: const LobbyScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 1200));

    final button = find.text('HI-LO  TRAINING');
    await tester.scrollUntilVisible(button, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(button);
    // A pushed route spends its first frame offstage.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('HI-LO TRAINING'), findsOneWidget);
    expect(find.textContaining('DAILY CHALLENGE #'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });
  group('Fixed', () {
    testWidgets('a double tap on SEE RESULTS scores the game once',
        (tester) async {
      await _open(tester, _phone, home: const HiLoPracticeSetupScreen(seed: 5));
      await _tap(tester, find.text('Often'));
      await _tap(tester, find.text('5').last);
      await _tap(tester, find.text('DEAL'));
      for (var q = 1; q <= 5; q++) {
        await _dealUntilAsked(tester);
        await _enter(tester, _truth(tester));
        if (q < 5) await _continue(tester);
      }
      await tester.tap(_key('hilo-continue'));
      await tester.tap(_key('hilo-continue'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 1500));
      final profile = await HiLoTrainingProgress.loadProfile();
      expect(profile.games, 1);
      expect(profile.questions, 5);
      await _close(tester);
    });

    testWidgets('the answer clock stops while the app is away', (tester) async {
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-daily-play'));
      await _dealUntilAsked(tester);
      await tester.pump(const Duration(seconds: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('TIME\'S UP'), findsNothing,
          reason: 'a phone call does not cost the question');
      expect(_key('hilo-check'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // The time left is measured on a real Stopwatch, which the test's fake
      // clock does not move, so the whole limit is the bound here.
      await tester.pump(HiLoGameSpec.rankedAnswerLimit);
      expect(find.text('TIME\'S UP'), findsOneWidget,
          reason: 'the clock runs again once the app is back');
      await _close(tester);
    });

    testWidgets('backing out of the ranked Daily asks first', (tester) async {
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-daily-play'));
      await tester.binding.handlePopRoute(); // Android back
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('End this game?'), findsOneWidget);
      expect(find.textContaining('counts from the first card'), findsOneWidget);
      await _tap(tester, _key('hilo-keep-playing'));
      expect(find.text('End this game?'), findsNothing);
      expect(find.text('DAILY #3'), findsOneWidget, reason: 'still playing');

      await _tap(tester, find.byTooltip('Back'));
      expect(find.text('End this game?'), findsOneWidget);
      await _tap(tester, _key('hilo-end-game'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_key('hilo-daily-replay'), findsOneWidget,
          reason: 'back at the hub, the try used');
      expect(find.text('0 pts'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('a replayed Daily does not chase a best it cannot set',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'hilo_training_profile': jsonEncode(const HiLoProfile(
          games: 1,
          dailyLastPlayed: 3,
          dailyStreak: 1,
          dailyScores: {3: 2450},
        ).toJson()),
      });
      await _open(tester, _phone);
      await _tap(tester, _key('hilo-daily-replay'));
      expect(find.text('DAILY #3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('BEST'), findsNothing);
      await _close(tester);
    });

    testWidgets('the hub fits at 200% text on a 320dp phone', (tester) async {
      await tester.binding.setSurfaceSize(_small);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const HiLoTrainingScreen(now: _now),
      ));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  });

  group('Completing the section', () {
    testWidgets('practice asks for the true count after the running count',
        (tester) async {
      await _open(tester, _small, home: const HiLoPracticeSetupScreen(seed: 9));
      await _tap(tester, find.text('+ True count'));
      await _tap(tester, find.text('Often'));
      await _tap(tester, find.text('5').last);
      await _tap(tester, find.text('DEAL'));
      for (var q = 1; q <= 5; q++) {
        await _dealUntilAsked(tester);
        final question = _question(tester);
        await _enter(tester, question.answer);
        expect(find.text('TRUE COUNT'), findsOneWidget);
        expect(find.byType(DecksLeftHint), findsOneWidget);
        await _enter(
            tester, question.acceptedTrueCounts(question.answer).first);
        expect(_key('hilo-true-count'), findsOneWidget);
        expect(find.textContaining('+ 50 true count'), findsOneWidget);
        await _continue(tester);
      }
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('TRUE COUNT'), findsOneWidget, reason: 'the stat');
      expect(find.text('5/5'), findsWidgets);
      final profile = await HiLoTrainingProgress.loadProfile();
      expect(profile.trueCountsRight, 5);
      expect(tester.takeException(), isNull);
      await _close(tester);
    });

    testWidgets('a hardware keyboard answers too', (tester) async {
      await _open(tester, _phone, home: const HiLoPracticeSetupScreen(seed: 2));
      await _tap(tester, find.text('Often'));
      await _tap(tester, find.text('DEAL'));
      await _dealUntilAsked(tester);
      final truth = _truth(tester);
      if (truth < 0) await tester.sendKeyEvent(LogicalKeyboardKey.minus);
      for (final d in truth.abs().toString().split('')) {
        await tester.sendKeyEvent(
            LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + int.parse(d)));
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SPOT ON'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SPOT ON'), findsNothing, reason: 'Enter deals on');
      await _close(tester);
    });

    testWidgets('a first visit shows where to start; habits show later',
        (tester) async {
      await _open(tester, _phone);
      expect(_key('hilo-new-here'), findsOneWidget);
      await _close(tester);

      SharedPreferences.setMockInitialValues({
        'hilo_training_profile': jsonEncode(const HiLoProfile(
          games: 4,
          questions: 30,
          correct: 23,
          trueCountsAsked: 10,
          trueCountsRight: 7,
          slips: {HiLoSlip.countedHoleCard: 5, HiLoSlip.drift: 2},
        ).toJson()),
      });
      await _open(tester, _phone);
      expect(_key('hilo-new-here'), findsNothing);
      await tester.ensureVisible(_key('hilo-common-slip'));
      expect(find.text('Counting the face-down card · 5×'), findsOneWidget);
      expect(find.text('True counts 7/10 right'), findsOneWidget);
      await _close(tester);
    });
  });
}

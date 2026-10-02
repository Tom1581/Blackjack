// The home screen and the UX pass of 2026-10: the brand lockup, Today's next
// step, the player's name, Practice Setup, the session report, next-unlock
// goals and next drills — and, at 320, 360, 390 and 412 dp, that no text
// breaks mid-word, nothing is cut off and no controls overlap.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/progress/player_stats.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/rules/rules_store.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game.dart';
import 'package:blackjack_app/features/hilo_training/hilo_goals.dart';
import 'package:blackjack_app/features/hilo_training/hilo_text.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_progress.dart';
import 'package:blackjack_app/features/hilo_training/hilo_setup_screens.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_screen.dart';
import 'package:blackjack_app/features/hilo_training/widgets/hilo_table_view.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_session.dart';
import 'package:blackjack_app/features/lobby/lobby_screen.dart';
import 'package:blackjack_app/features/lobby/next_step.dart';
import 'package:blackjack_app/features/lobby/session_report.dart';
import 'package:blackjack_app/features/lobby/widgets/session_report_sheet.dart';
import 'package:blackjack_app/features/online/online_providers.dart';
import 'package:blackjack_app/features/profile/player_identity.dart';
import 'package:blackjack_app/features/training/drills.dart';
import 'package:blackjack_app/features/training/strategy_drill_screen.dart';
import 'package:blackjack_app/theme/app_theme.dart';

import 'support/layout_checks.dart';
import 'support/quiet_plugins.dart';
import 'support/real_fonts.dart';

Finder _key(String k) => find.byKey(ValueKey(k));

/// A record with some play behind it, so the home screen has something to
/// say — today's Daily already played, so the next step is a drill.
Map<String, Object> _played() {
  final today = HiLoDaily.numberFor(DateTime.now());
  return {
    'online_player_name': 'Alex',
    'hands_played': 40,
    'strategy_total': 40,
    'strategy_correct': 33,
    'strategy_hard_total': 30,
    'strategy_hard_correct': 26,
    'strategy_misses': jsonEncode({'Hard 16 vs 10': 4, 'Soft 18 vs 9': 2}),
    'hilo_training_profile': jsonEncode(HiLoProfile(
      games: 3,
      questions: 30,
      correct: 25,
      dailyLastPlayed: today,
      dailyStreak: 1,
      dailyScores: {today: 1800},
    ).toJson()),
  };
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablePrefs.resetForTest();
    RulesStore.resetForTest();
    StrategyCoach.resetForTest();
  });

  group('Today\'s next step', () {
    PlayerStats stats({int hands = 40, int checks = 0, int right = 0}) =>
        PlayerStats(
            hands: hands, countChecks: checks, countChecksCorrect: right);
    StrategyMastery mastery({
      List<StrategyMiss> misses = const [],
      Map<StrategyCategory, StrategyRecord> by = const {},
    }) =>
        StrategyMastery(byCategory: by, topMisses: misses);
    HiLoProfile hilo({bool played = true, int games = 1}) => HiLoProfile(
          games: games,
          dailyScores: played ? const {4: 100} : const {},
        );
    NextStep pick({
      PlayerStats? s,
      StrategyMastery? m,
      HiLoProfile? h,
    }) =>
        pickNextStep(NextStepInputs(
          stats: s ?? stats(),
          mastery: m ?? mastery(),
          hilo: h ?? hilo(),
          today: 4,
        ));

    test('someone new plays a first hand', () {
      final step = pick(s: stats(hands: 0), h: const HiLoProfile());
      expect(step.action, NextStepAction.playTable);
      expect(step.title, 'Play your first hand');
    });

    test('an unplayed Daily comes next', () {
      final step = pick(h: hilo(played: false));
      expect(step.action, NextStepAction.playDaily);
      expect(step.dailyNumber, 4);
      expect(step.detail, contains('Daily #4'));
    });

    test('then the hand they keep missing', () {
      final step =
          pick(m: mastery(misses: const [StrategyMiss('Hard 16 vs 10', 4)]));
      expect(step.action, NextStepAction.drillMistakes);
      expect(step.title, 'Improve 16 vs 10');
      expect(step.focus, StrategyDrillFocus.mistakes);
      expect(
          pick(m: mastery(misses: const [StrategyMiss('Soft 18 vs 9', 3)]))
              .title,
          'Improve Soft 18 vs 9',
          reason: 'only "Hard" is implied');
      expect(
          pick(m: mastery(misses: const [StrategyMiss('Hard 12 vs 2', 2)]))
              .action,
          isNot(NextStepAction.drillMistakes),
          reason: 'twice is not yet a habit');
    });

    test('then their weakest part of the chart', () {
      final step = pick(
        m: mastery(by: const {
          StrategyCategory.hard: StrategyRecord(correct: 19, total: 20),
          StrategyCategory.soft: StrategyRecord(correct: 15, total: 20),
          StrategyCategory.pair: StrategyRecord(correct: 17, total: 20),
        }),
      );
      expect(step.action, NextStepAction.drillCategory);
      expect(step.title, 'Practice soft totals');
      expect(step.focus, StrategyDrillFocus.soft);
      expect(step.detail, startsWith('75% right'));
      expect(
          pick(
              m: mastery(by: const {
            StrategyCategory.pair: StrategyRecord(correct: 5, total: 10),
          })).action,
          isNot(NextStepAction.drillCategory),
          reason: 'ten decisions are too few to judge');
    });

    test('then the running count, then more pressure', () {
      expect(pick(s: stats(checks: 10, right: 6)).action,
          NextStepAction.speedCount);
      expect(
          pick(s: stats(checks: 10, right: 9)).action, NextStepAction.survival);
    });
  });

  group('The session report', () {
    TableSnapshot snap({
      int hands = 0,
      int net = 0,
      int checks = 0,
      int checksRight = 0,
      int decisions = 0,
      int right = 0,
      Map<String, int> misses = const {},
    }) =>
        TableSnapshot(
          stats: PlayerStats(
            hands: hands,
            tableNet: net,
            countChecks: checks,
            countChecksCorrect: checksRight,
          ),
          strategy: StrategyRecord(correct: right, total: decisions),
          misses: misses,
        );

    test('counts only this session, and finds the mistake that grew', () {
      final r = SessionReport.between(
        snap(
            hands: 10,
            net: 500,
            checks: 4,
            checksRight: 3,
            decisions: 30,
            right: 28,
            misses: {'Hard 16 vs 10': 5, 'Soft 18 vs 9': 1}),
        snap(
            hands: 22,
            net: 350,
            checks: 6,
            checksRight: 4,
            decisions: 44,
            right: 40,
            misses: {'Hard 16 vs 10': 6, 'Soft 18 vs 9': 3}),
      );
      expect(r.hands, 12);
      expect(r.net, -150);
      expect(r.strategy.total, 14);
      expect(r.strategy.correct, 12);
      expect(r.countChecks.total, 2);
      expect(r.biggestMistake?.spot, 'Soft 18 vs 9',
          reason: 'missed twice this session, against once for 16 vs 10');
      expect(r.biggestMistake?.count, 2);
      expect(r.nextDrill, NextDrill.mistakes);
      expect(r.worthShowing, isTrue);
    });

    test('a tie goes to the more stubborn habit', () {
      final r = SessionReport.between(
        snap(misses: {'A': 1, 'B': 9}),
        snap(misses: {'A': 2, 'B': 10}),
      );
      expect(r.biggestMistake?.spot, 'B');
    });

    test('picks the drill that fits a clean session', () {
      expect(
          SessionReport.between(
                  snap(), snap(hands: 5, checks: 5, checksRight: 2))
              .nextDrill,
          NextDrill.speedCount);
      expect(
          SessionReport.between(snap(), snap(hands: 5, decisions: 10, right: 8))
              .nextDrill,
          NextDrill.strategy);
      expect(
          SessionReport.between(
                  snap(), snap(hands: 5, decisions: 10, right: 10))
              .nextDrill,
          NextDrill.hiLoTraining);
    });

    test('a quick look at the table is not a session', () {
      expect(
          SessionReport.between(snap(), snap(hands: 2)).worthShowing, isFalse);
      expect(SessionReport.between(snap(), snap(decisions: 5)).worthShowing,
          isTrue);
    });
  });

  group('The player\'s name and look', () {
    test('cleaned to the 12 characters tables and boards allow', () {
      expect(PlayerIdentity.clean('  Alex   the  Great  '), 'Alex the Gre');
      expect(PlayerIdentity.clean(''), '');
      expect(PlayerIdentity.initial(''), '?');
      expect(PlayerIdentity.initial('alex'), 'A');
    });

    test('the same colour for the same name, everywhere', () {
      expect(PlayerIdentity.colorFor('Alex'), PlayerIdentity.colorFor('alex'),
          reason: 'case does not matter');
      expect(
          PlayerIdentity.colorFor(' Alex '), PlayerIdentity.colorFor('Alex'));
      final colours = {
        for (final n in ['Alex', 'Sam', 'Jo', 'Priya', 'Ken', 'Mia', 'Lee'])
          PlayerIdentity.colorFor(n),
      };
      expect(colours.length, greaterThan(3), reason: 'names spread out');
      expect(colours, isNot(contains(AppColors.gold)),
          reason: 'gold means "you"');
    });

    test('saved where online tables and leaderboards read it', () async {
      await PlayerIdentity.save('  Sam  ');
      expect(await loadPlayerName(), 'Sam');
      expect(await PlayerIdentity.load(), 'Sam');
    });

    test('shared challenges say who they are from', () {
      expect(dailyShareText(4, 900, playerName: 'Alex'),
          startsWith('Alex · Hi-Lo Daily #4 — 900 pts'));
      expect(dailyShareText(4, 900), startsWith('Hi-Lo Daily #4'));
    });
  });

  group('Next unlock', () {
    test('a new player is pointed at their first count', () {
      final g = nextGoal(const HiLoProfile(), today: 4)!;
      expect(g.achievement, HiLoAchievement.firstCount);
      expect(g.action, HiLoGoalAction.practice);
      expect(g.progress, 0);
    });

    test('the goal closest to done comes first', () {
      final g = nextGoal(
        const HiLoProfile(
          correct: 40,
          holeCardReads: 8,
          achievements: {HiLoAchievement.firstCount},
        ),
        today: 4,
      )!;
      expect(g.achievement, HiLoAchievement.pokerFace);
      expect(g.progressLabel, '8 / 10');
      expect(g.progress, 0.8);
    });

    test('streaks count only while alive; feats have no count', () {
      final lapsed = lockedGoals(
          const HiLoProfile(dailyLastPlayed: 1, dailyStreak: 2),
          today: 4);
      expect(
          lapsed
              .firstWhere((g) => g.achievement == HiLoAchievement.regular)
              .current,
          0);
      expect(
          lapsed
              .firstWhere((g) => g.achievement == HiLoAchievement.quickDraw)
              .progressLabel,
          isNull);
    });

    test('nothing left once everything is unlocked', () {
      expect(
          nextGoal(HiLoProfile(achievements: HiLoAchievement.values.toSet()),
              today: 4),
          isNull);
    });
  });

  group('Next drill after a Hi-Lo game', () {
    HiLoAnswer a(int answer, int? given,
            {CardModel? hole, CardModel? last, int? tc}) =>
        HiLoAnswer(
          question: HiLoQuestion(
              answer: answer,
              round: 1,
              holeCardDown: hole,
              lastCard: last,
              decksLeft: 2),
          given: given,
          trueCountAsked: tc != null,
          trueCountGiven: tc,
        );

    test('points at the drill for the habit', () {
      const five = CardModel(suit: Suit.clubs, rank: Rank.five);
      expect(nextDrillFor([a(3, 4, hole: five), a(1, 1)]),
          HiLoNextDrill.relaxedPractice);
      expect(nextDrillFor([a(4, -4), a(2, -2)]), HiLoNextDrill.tagDrill);
      expect(nextDrillFor([a(3, 9), a(2, null)]), HiLoNextDrill.speedCount);
      expect(nextDrillFor([a(4, 4, tc: 9), a(4, 4, tc: 9)]),
          HiLoNextDrill.trueCount);
      expect(nextDrillFor([a(1, 1)]), HiLoNextDrill.survival,
          reason: 'a clean game raises the stakes');
      expect(nextDrillFor([a(1, 1)], survival: true), HiLoNextDrill.speedCount);
    });
  });

  group('The layout checks themselves', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await loadRealFonts(), isTrue);
    });

    testWidgets('catch a word broken, a line cut off, controls overlapping',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(
                width: 60,
                child: Text('BLACKJACK', style: TextStyle(fontSize: 30)),
              ),
              const SizedBox(
                width: 60,
                child:
                    Text('a line far too long', maxLines: 1, softWrap: false),
              ),
              SizedBox(
                height: 100,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      child: TextButton(
                          onPressed: () {}, child: const Text('one')),
                    ),
                    Positioned(
                      left: 20,
                      top: 10,
                      child: TextButton(
                          onPressed: () {}, child: const Text('two')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
      final breaks = midWordBreaks(tester);
      expect(breaks, isNotEmpty);
      expect(breaks, everyElement(startsWith('BLACKJACK|')),
          reason: 'every break inside the word is reported');
      expect(clippedTexts(tester).single, startsWith('a line far too long'));
      expect(overlappingControls(tester), hasLength(1));
    });
  });

  group('On a phone', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await loadRealFonts(), isTrue, reason: 'layout needs real fonts');
    });

    Future<ProviderContainer> pumpHome(WidgetTester tester, double width,
        {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      quietAdsPlugin(tester);
      await tester.binding.setSurfaceSize(Size(width, phoneHeight(width)));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const LobbyScreen()),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      return container;
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }

    for (final width in phoneWidths) {
      testWidgets('the home screen at ${width.toInt()} dp', (tester) async {
        await pumpHome(tester, width, prefs: _played());
        expect(lineCount(tester, _key('brand-wordmark')), 1,
            reason: 'BLACKJACK never wraps');
        expect(find.text('HI-LO'), findsOneWidget);
        expect(find.text('TRAINER'), findsOneWidget);

        // Above the fold: who you are, the next step and PLAY.
        final screen = phoneHeight(width);
        expect(tester.getRect(_key('home-next-step')).bottom,
            lessThanOrEqualTo(screen));
        expect(tester.getRect(find.text('PLAY A HAND')).bottom,
            lessThanOrEqualTo(screen));
        expect(find.text('Alex'), findsOneWidget);
        expect(find.text('Improve 16 vs 10'), findsOneWidget);
        expectCleanLayout(tester, where: 'home top');

        await tester.scrollUntilVisible(_key('home-practice-setup'), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump(const Duration(milliseconds: 300));
        expectCleanLayout(tester, where: 'home bottom');
        expect(tester.takeException(), isNull);

        // Practice Setup, top to bottom.
        await tester.tap(_key('home-practice-setup'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expectCleanLayout(tester, where: 'setup top');

        // The table-rule picker over it.
        await tester.tap(find.text('Table rules'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('TABLE RULES'), findsOneWidget);
        expectCleanLayout(tester, where: 'rule picker');
        Navigator.of(tester.element(find.text('TABLE RULES'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        await tester.drag(_key('practice-setup-sheet'), const Offset(0, -500));
        await tester.pump(const Duration(milliseconds: 400));
        expectCleanLayout(tester, where: 'setup middle');
        await tester.drag(_key('practice-setup-sheet'), const Offset(0, -900));
        await tester.pump(const Duration(milliseconds: 400));
        expectCleanLayout(tester, where: 'setup bottom');
        expect(tester.takeException(), isNull);
        await close(tester);
      });
    }

    testWidgets('a long name shortens instead of breaking the row',
        (tester) async {
      await pumpHome(tester, 320,
          prefs: {'online_player_name': 'Maximiliana X'});
      expect(clippedTexts(tester, allowEllipsis: true), isEmpty);
      expect(midWordBreaks(tester), isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('the next step opens what it suggests', (tester) async {
      await pumpHome(tester, 360, prefs: _played());
      expect(find.text('Improve 16 vs 10'), findsOneWidget);
      await tester.tap(_key('home-next-step'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      final drill =
          tester.widget<StrategyDrillScreen>(find.byType(StrategyDrillScreen));
      expect(drill.initialFocus, StrategyDrillFocus.mistakes);
      await close(tester);
    });

    testWidgets('an unplayed Daily is the next step, one tap away',
        (tester) async {
      final prefs = _played()..remove('hilo_training_profile');
      await pumpHome(tester, 360, prefs: prefs);
      expect(find.text('Play today\'s Daily Challenge'), findsOneWidget);
      await tester.tap(_key('home-next-step'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.textContaining('DAILY #'), findsOneWidget);
      // Leaving asks first — it is the day's ranked try.
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('End this game?'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the name is set once and shows on the home screen',
        (tester) async {
      await pumpHome(tester, 360);
      expect(find.text('Add your name'), findsOneWidget);
      await tester.tap(_key('home-profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<FilledButton>(_key('profile-name-save')).onPressed,
          isNull,
          reason: 'nothing to save yet');
      await tester.enterText(_key('profile-name-field'), '  Jordan  ');
      await tester.pump();
      await tester.tap(_key('profile-name-save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Jordan'), findsOneWidget);
      expect(await loadPlayerName(), 'Jordan',
          reason: 'online tables and leaderboards read this');
      await close(tester);
    });

    testWidgets('after a table session, a report and its next drill',
        (tester) async {
      await pumpHome(tester, 360, prefs: _played());
      await tester.tap(find.text('PLAY A HAND'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      // A session happens: hands, decisions, one mistake.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('hands_played', 52);
      await prefs.setInt('strategy_total', 52);
      await prefs.setInt('strategy_correct', 43);
      await prefs.setString('strategy_misses',
          jsonEncode({'Hard 16 vs 10': 6, 'Soft 18 vs 9': 2}));
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.text('SESSION REPORT'), findsOneWidget);
      expect(find.text('Biggest mistake: 16 vs 10'), findsOneWidget);
      expect(find.textContaining('The chart says Hit'), findsOneWidget);
      expect(find.text('83%'), findsOneWidget, reason: '10 of 12 this session');
      expectCleanLayout(tester, where: 'session report');
      await tester.tap(_key('session-next-drill'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(
          tester
              .widget<StrategyDrillScreen>(find.byType(StrategyDrillScreen))
              .initialFocus,
          StrategyDrillFocus.mistakes);
      await close(tester);
    });

    for (final width in phoneWidths) {
      testWidgets('the session report at ${width.toInt()} dp', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, phoneHeight(width)));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final report = SessionReport.between(
          const TableSnapshot(
              stats: PlayerStats(), strategy: StrategyRecord.empty, misses: {}),
          const TableSnapshot(
            stats: PlayerStats(
                hands: 14,
                tableNet: 150,
                countChecks: 3,
                countChecksCorrect: 2),
            strategy: StrategyRecord(correct: 11, total: 13),
            misses: {'Soft 18 vs 9': 2},
          ),
        );
        NextDrill? chosen;
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => chosen = await showSessionReportSheet(
                      c,
                      report: report,
                      rules: RuleSet.sixDeckH17,
                      decks: 6),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.text('Biggest mistake: Soft 18 vs 9'), findsOneWidget);
        expectCleanLayout(tester, where: 'report');
        await tester.tap(_key('session-done'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(chosen, isNull, reason: 'DONE chooses no drill');
      });
    }

    for (final width in phoneWidths) {
      testWidgets('the Hi-Lo hub at ${width.toInt()} dp', (tester) async {
        SharedPreferences.setMockInitialValues({
          'online_player_name': 'Alex',
          'hilo_training_profile': jsonEncode(const HiLoProfile(
            games: 2,
            correct: 14,
            questions: 20,
            holeCardReads: 6,
            achievements: {HiLoAchievement.firstCount},
          ).toJson()),
        });
        await tester.binding.setSurfaceSize(Size(width, phoneHeight(width)));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: HiLoTrainingScreen(now: () => DateTime(2026, 10, 3, 18)),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.text('ALEX · RANK'), findsOneWidget);
        expectCleanLayout(tester, where: 'hub top');
        await tester.scrollUntilVisible(_key('hilo-next-goal'), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.text('Poker Face'), findsOneWidget);
        expect(find.text('6 / 10'), findsOneWidget);
        expectCleanLayout(tester, where: 'hub goals');
        await tester.scrollUntilVisible(
            _key('hilo-records-survival-empty'), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('START A RUN'), findsOneWidget);
        expectCleanLayout(tester, where: 'hub records');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 2));
      });
    }

    testWidgets('a next-unlock button goes where the goal is earned',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: HiLoTrainingScreen(now: () => DateTime(2026, 10, 3, 18)),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.scrollUntilVisible(_key('hilo-next-goal-go'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('First Count'), findsOneWidget);
      await tester.tap(_key('hilo-next-goal-go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('PRACTICE'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    });

    for (final width in phoneWidths) {
      testWidgets('Hi-Lo results, with the next drill, at ${width.toInt()} dp',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, phoneHeight(width)));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: const HiLoPracticeSetupScreen(seed: 3),
        ));
        await tester.pump(const Duration(milliseconds: 200));
        Future<void> tap(Finder f) async {
          await tester.ensureVisible(f);
          await tester.pump();
          await tester.tap(f);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 900));
        }

        await tap(find.text('Often'));
        await tap(find.text('5').last);
        await tap(find.text('DEAL'));
        for (var q = 0; q < 5; q++) {
          for (var i = 0; i < 300; i++) {
            await tester.pump(const Duration(milliseconds: 300));
            if (_key('hilo-check').evaluate().isNotEmpty) break;
          }
          final truth = tester
              .widget<HiLoTableView>(find.byType(HiLoTableView))
              .session
              .openQuestion!
              .answer;
          // Two wrong (sign flipped where it can be), three right.
          final given = q < 2 && truth != 0 ? -truth : truth + (q < 2 ? 7 : 0);
          if (given < 0) await tester.tap(_key('hilo-key-sign'));
          for (final d in given.abs().toString().split('')) {
            await tester.tap(_key('hilo-key-$d'));
          }
          await tester.tap(_key('hilo-check'));
          await tester.pump(const Duration(milliseconds: 200));
          if (q == 0) expectCleanLayout(tester, where: 'verdict');
          await tester.tap(_key('hilo-continue'));
          await tester.pump(const Duration(milliseconds: 100));
        }
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(_key('hilo-next-drill'), findsOneWidget);
        expectCleanLayout(tester, where: 'results top');
        await tester.scrollUntilVisible(_key('hilo-next-drill'), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump(const Duration(milliseconds: 300));
        expectCleanLayout(tester, where: 'results next drill');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    }

    for (final width in phoneWidths) {
      testWidgets('the name sheet at ${width.toInt()} dp', (tester) async {
        await tester.binding.setSurfaceSize(Size(width, phoneHeight(width)));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showEditNameSheet(c, current: 'Alex'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('YOUR NAME'), findsOneWidget);
        expectCleanLayout(tester, where: 'name sheet');
      });
    }
  });
}

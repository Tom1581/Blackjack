// Hi-Lo Training, the finishing pieces: finding a challenge code in a pasted
// message, challenge links, the opt-in Daily reminder, keeping the screen on
// during a game, and the Training Center's way in.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/app.dart';
import 'package:blackjack_app/features/hilo_training/daily_reminder.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game.dart';
import 'package:blackjack_app/features/hilo_training/hilo_links.dart';
import 'package:blackjack_app/features/hilo_training/hilo_setup_screens.dart';
import 'package:blackjack_app/features/hilo_training/hilo_text.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_progress.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_screen.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_session.dart';
import 'package:blackjack_app/features/hilo_training/screen_awake.dart';
import 'package:blackjack_app/features/training/training_center_screen.dart';
import 'package:blackjack_app/theme/app_theme.dart';

import 'support/real_fonts.dart';

const _challenge = HiLoChallenge(
  seed: 4242,
  config: HiLoTrainingConfig(players: 4, pace: HiLoPace.brisk, questions: 5),
  survival: false,
  score: 2450,
);

/// Records what the reminder would have scheduled.
class _FakeScheduler implements ReminderScheduler {
  bool allow = true;
  bool launched = false;
  bool fail = false;
  int inits = 0;
  final scheduled = <({DateTime when, String title, String body})>[];
  int cancels = 0;

  @override
  Future<void> init(VoidCallback onTap) async => inits++;

  @override
  Future<bool> requestPermission() async => allow;

  @override
  Future<void> scheduleAt(DateTime when, String title, String body) async {
    if (fail) throw StateError('no plugin');
    scheduled.add((when: when, title: title, body: body));
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<bool> launchedFromReminder() async => launched;
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  late _FakeScheduler fake;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fake = _FakeScheduler();
    DailyReminder.resetForTest(fake);
    ScreenAwake.resetForTest();
    HiLoLinks.sourceOverride = null;
  });

  group('Finding a code in a message', () {
    test('the whole shared message works', () {
      final code = _challenge.encode();
      final message = 'Hi-Lo Training — 2,450 pts\n🟩🟩🟥🟩🟩\n'
          'Same shoe, your turn — challenge code $code\n'
          '(Hi-Lo Training → Enter a friend\'s code → Paste)\n'
          'https://play.google.com/store/apps/details?id='
          'io.github.a15817348.hiloblackjacktrainer';
      expect(HiLoChallenge.findIn(message)?.score, 2450);
    });

    test('lowercase, without dashes, or inside a link', () {
      final code = _challenge.encode();
      expect(HiLoChallenge.findIn('try ${code.toLowerCase()} now')?.seed, 4242);
      expect(HiLoChallenge.findIn(code.replaceAll('-', ''))?.seed, 4242);
      expect(HiLoChallenge.findIn('hilobj://challenge/$code')?.seed, 4242);
    });

    test('nothing that merely looks like one', () {
      expect(HiLoChallenge.findIn(''), isNull);
      expect(
          HiLoChallenge.findIn('https://play.google.com/store/apps/details?'
              'id=io.github.a15817348.hiloblackjacktrainer'),
          isNull,
          reason: 'runs of letters inside a URL are not codes');
      expect(HiLoChallenge.findIn('ABCD-EFGH-JKM'), isNull);
    });

    test('skips a code-shaped typo for the real one after it', () {
      final code = _challenge.encode();
      expect(HiLoChallenge.findIn('ABCD-EFGH-JKM then $code')?.score, 2450);
    });
  });

  group('Challenge links', () {
    test('carry the code in the path, never a "code" parameter', () {
      final link = HiLoLinks.appLink(_challenge.encode().toLowerCase());
      expect(link.scheme, 'hilobj');
      expect(link.host, 'challenge');
      expect(link.queryParameters, isEmpty,
          reason: 'supabase_flutter treats ?code= as a sign-in callback');
      expect(HiLoLinks.fromUri(link)?.score, 2450);
    });

    test('anything else is not a challenge', () {
      expect(HiLoLinks.fromUri(Uri.parse('hilobj://challenge/')), isNull);
      expect(HiLoLinks.fromUri(Uri.parse('hilobj://table/ABCD')), isNull);
      expect(HiLoLinks.fromUri(Uri.parse('https://x.io/?code=abc')), isNull);
      final page = Uri.parse('https://tom1581.github.io/Blackjack/challenge/'
          '?c=${_challenge.encode()}');
      expect(HiLoLinks.fromUri(page)?.seed, 4242);
    });

    test('no page link until the page is published', () {
      expect(HiLoLinks.pageBase, isEmpty);
      expect(HiLoLinks.pageLink('ABCD-EFGH-JKM'), isNull);
      final text = dailyShareText(4, 900);
      expect(text, isNot(contains('Tap to play')));
      expect(text, contains('Paste'));
    });

    test('each link is handled once, and only challenges', () async {
      final links = StreamController<Uri>();
      HiLoLinks.sourceOverride = () => links.stream;
      final got = <HiLoChallenge>[];
      final sub = HiLoLinks.listen(got.add)!;
      final link = HiLoLinks.appLink(_challenge.encode());
      links
        ..add(link)
        ..add(link) // the launch link, delivered twice
        ..add(Uri.parse('https://example.com'));
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(1));
      await sub.cancel();
      await links.close();
    });

    test('without a platform under test, nothing is listened to', () {
      expect(HiLoLinks.listen((_) {}), isNull);
    });
  });

  group('The Daily reminder', () {
    test('fires today while the shoe is unplayed and the hour ahead', () {
      final morning = DateTime(2026, 10, 2, 9, 30);
      expect(DailyReminder.nextAt(morning, 18, playedToday: false),
          DateTime(2026, 10, 2, 18));
      expect(DailyReminder.nextAt(morning, 18, playedToday: true),
          DateTime(2026, 10, 3, 18),
          reason: 'already played today');
      expect(
          DailyReminder.nextAt(DateTime(2026, 10, 2, 19), 18,
              playedToday: false),
          DateTime(2026, 10, 3, 18),
          reason: 'the hour has passed');
      expect(
          DailyReminder.nextAt(DateTime(2026, 10, 31, 22), 9,
              playedToday: false),
          DateTime(2026, 11, 1, 9),
          reason: 'across a month end');
    });

    test('hour labels', () {
      expect(DailyReminder.hours.map(DailyReminder.hourLabel).toList(),
          ['9 AM', 'Noon', '6 PM', '8 PM']);
    });

    test('is off until switched on, and stays off if refused', () async {
      await DailyReminder.refresh();
      expect(fake.scheduled, isEmpty);
      fake.allow = false;
      expect(await DailyReminder.enable(18), isFalse);
      expect((await DailyReminder.load()).on, isFalse);
      expect(fake.scheduled, isEmpty);
    });

    test('schedules the next unplayed shoe, then moves on', () async {
      DailyReminder.now = () => DateTime(2026, 10, 2, 9);
      expect(await DailyReminder.enable(18), isTrue);
      expect(fake.scheduled.single.when, DateTime(2026, 10, 2, 18));
      expect(fake.scheduled.single.title, 'Daily Challenge #4 is ready');
      expect(fake.scheduled.single.body,
          contains(tableLabel(HiLoDaily.configFor(4))));

      // Today's Daily is played: the reminder moves to tomorrow's shoe.
      await HiLoTrainingProgress.startDailyAttempt(4);
      await DailyReminder.refresh();
      expect(fake.scheduled.last.when, DateTime(2026, 10, 3, 18));
      expect(fake.scheduled.last.title, 'Daily Challenge #5 is ready');

      await DailyReminder.setHour(9);
      expect(fake.scheduled.last.when, DateTime(2026, 10, 3, 9));
      expect(fake.inits, 1, reason: 'the plugin is set up once');

      await DailyReminder.disable();
      expect(fake.cancels, 1);
      final count = fake.scheduled.length;
      await DailyReminder.refresh();
      expect(fake.scheduled, hasLength(count), reason: 'off means off');
    });

    test('a tapped reminder opens Hi-Lo Training at launch', () async {
      SharedPreferences.setMockInitialValues({'hilo_reminder_on': true});
      fake.launched = true;
      var opened = 0;
      DailyReminder.onOpen = () => opened++;
      await DailyReminder.start();
      expect(opened, 1);
      expect(fake.scheduled, hasLength(1));
    });

    test('never throws when the plugin fails', () async {
      SharedPreferences.setMockInitialValues({'hilo_reminder_on': true});
      fake.fail = true;
      await DailyReminder.refresh();
      await DailyReminder.start();
    });
  });

  group('On a phone', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(await loadRealFonts(), isTrue);
    });

    Future<void> open(WidgetTester tester, Widget home) async {
      await tester.binding.setSurfaceSize(const Size(360, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
    }

    testWidgets('the screen stays on while dealing, and only then',
        (tester) async {
      final calls = <bool>[];
      ScreenAwake.override = calls.add;
      await open(tester, const HiLoPracticeSetupScreen(seed: 3));
      await tap(tester, find.text('DEAL'));
      expect(ScreenAwake.isOn, isTrue, reason: 'dealing');

      await tap(tester, find.text('PAUSE'));
      expect(ScreenAwake.isOn, isFalse, reason: 'paused');
      await tap(tester, find.text('RESUME'));
      expect(ScreenAwake.isOn, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(ScreenAwake.isOn, isFalse, reason: 'not on screen');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ScreenAwake.isOn, isFalse, reason: 'still paused from going away');
      await tap(tester, find.text('RESUME'));
      expect(ScreenAwake.isOn, isTrue);

      // Leaving the game lets the screen sleep again.
      await tap(tester, find.byTooltip('Back'));
      expect(ScreenAwake.isOn, isFalse);
      expect(calls, [true, false, true, false, true, false]);
      await close(tester);
    });

    testWidgets('a challenge link opens the code sheet on the friend\'s shoe',
        (tester) async {
      final links = StreamController<Uri>();
      HiLoLinks.sourceOverride = () => links.stream;
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ProviderScope(child: BlackjackApp()));
      await tester.pump(const Duration(milliseconds: 300));

      links.add(HiLoLinks.appLink(_challenge.encode()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('HI-LO TRAINING'), findsOneWidget);
      expect(find.text('SCORE TO BEAT: 2,450'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(_key('hilo-code-play'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('CHALLENGE'), findsOneWidget);
      expect(find.text('TO BEAT 2,450'), findsOneWidget);

      await links.close();
      await close(tester);
    });

    testWidgets('PASTE pulls the code out of a whole message', (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return clipboard == null ? null : {'text': clipboard};
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await open(tester, const HiLoTrainingScreen());
      await tap(tester, _key('hilo-enter-code'));

      await tester.tap(_key('hilo-code-paste'));
      await tester.pump();
      expect(_key('hilo-code-paste-note'), findsOneWidget,
          reason: 'nothing on the clipboard');

      clipboard = 'Hi-Lo Daily #4 — 2,450 pts\nSame shoe, your turn — '
          'challenge code ${_challenge.encode()}\nhttps://play.google.com/x';
      await tester.tap(_key('hilo-code-paste'));
      await tester.pump();
      expect(find.text(_challenge.encode()), findsOneWidget);
      expect(find.text('SCORE TO BEAT: 2,450'), findsOneWidget);
      expect(_key('hilo-code-paste-note'), findsNothing);

      // Pasting the message straight into the field works too.
      await tester.enterText(
          _key('hilo-code-field'), 'beat me: ${_challenge.encode()} !!');
      await tester.pump();
      expect(find.text(_challenge.encode()), findsOneWidget);
      await close(tester);
    });

    testWidgets('the reminder switch asks, then offers the hour',
        (tester) async {
      await open(
          tester, HiLoTrainingScreen(now: () => DateTime(2026, 10, 2, 9)));
      DailyReminder.now = () => DateTime(2026, 10, 2, 9);
      // The row reads its own setting once the hub's content is up.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(_key('hilo-reminder'));
      expect(find.text('Remind me about the Daily'), findsOneWidget);

      fake.allow = false;
      await tester.tap(_key('hilo-reminder-switch'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Notifications are off'), findsOneWidget);
      expect(find.text('Remind me about the Daily'), findsOneWidget);

      fake.allow = true;
      await tester.tap(_key('hilo-reminder-switch'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Reminder at 6 PM'), findsOneWidget);
      expect(fake.scheduled.last.when, DateTime(2026, 10, 2, 18));

      await tester.tap(find.text('8 PM'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Reminder at 8 PM'), findsOneWidget);
      expect(fake.scheduled.last.when, DateTime(2026, 10, 2, 20));
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('the Training Center leads to Hi-Lo Training', (tester) async {
      await open(tester, const TrainingCenterScreen());
      await tester.scrollUntilVisible(find.text('Hi-Lo Training'), 200);
      await tap(tester, find.text('Hi-Lo Training'));
      expect(find.text('HI-LO TRAINING'), findsOneWidget);
      await close(tester);
    });
  });
}

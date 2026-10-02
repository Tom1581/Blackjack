// Stages the Google Play screenshots on a real device or emulator.
//
// Run through tool/capture_store_screenshots.py, which watches for the
// `STORE_SHOT <name>` lines this prints, grabs the screen with
// `adb exec-out screencap`, and then lets the test carry on. Every picture
// is the release UI running for real: nothing here draws on the screen, it
// only seeds a believable player record and plays the app to the moment
// worth showing.
import 'dart:async';
import 'dart:io';

import 'package:blackjack_app/app.dart';
import 'package:blackjack_app/core/ads/ad_service.dart';
import 'package:blackjack_app/core/audio/sound_service.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/progress/daily_streak.dart';
import 'package:blackjack_app/core/rules/rules_store.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/basic_strategy.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game_screen.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_progress.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_screen.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_session.dart';
import 'package:blackjack_app/features/hilo_training/widgets/hilo_table_view.dart';
import 'package:blackjack_app/features/online/online_controller.dart';
import 'package:blackjack_app/features/online/online_state.dart';
import 'package:blackjack_app/features/online/online_table_screen.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/in_memory_transport.dart';

const _package = 'io.github.a15817348.hiloblackjacktrainer';
const _ackDir = '/data/user/0/$_package/cache';

/// No ads in a store picture: nothing is fetched and nothing interrupts.
class _NoAds extends AdService {
  @override
  Future<void> initialize() async {}

  @override
  void showInterstitialAfterHand() {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('store screenshots', (tester) async {
    final today = HiLoDaily.numberFor(DateTime.now());
    await _seedPlayer(today);
    await Future.wait<void>([
      SoundService.load(),
      StrategyCoach.load(),
      RulesStore.load(),
      TablePrefs.load(),
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    await tester.pumpWidget(ProviderScope(
      overrides: [adServiceProvider.overrideWith((ref) => _NoAds())],
      child: const BlackjackApp(),
    ));
    final s = _Stage(tester);
    await s.wait(2500);
    await s.shot('00-home');

    // 7 · The table-rule picker, over Practice Setup.
    await s.tap(find.byKey(const ValueKey('home-practice-setup')));
    await s.wait(900);
    await s.tap(find.text('Table rules'));
    await s.wait(1100);
    await s.shot('07-table-rules');
    await s.popAll();

    // 5 · The coach naming a misplay at the practice table.
    await s.coachCorrection();
    await s.popAll();

    // 4 · The Hi-Lo hub, with today's Daily Challenge still to play.
    await _seedHiLo(today, xp: 2140);
    s.push(const HiLoTrainingScreen());
    await s.wait(1800);
    await s.shot('04-hilo-hub');
    await s.popAll();

    // 1 · A Hi-Lo Training table mid-round.
    await _seedHiLo(today, xp: 2140);
    s.push(HiLoGameScreen(
      spec: HiLoGameSpec.practice(
        const HiLoTrainingConfig(
          players: 5,
          pace: HiLoPace.relaxed,
          frequency: HiLoQuizFrequency.often,
          questions: 20,
        ),
        seed: 4417,
      ),
    ));
    await s.hiLoMidRound();
    await s.popAll();

    // 2 · The count keypad in Survival.
    await _seedHiLo(today, xp: 2140);
    s.push(HiLoGameScreen(spec: HiLoGameSpec.survival(seed: 90210)));
    await s.survivalKeypad();
    await s.popAll();

    // 3 · Results: a perfect game, its combos, and a rank gained.
    await _seedHiLo(today, xp: 900, practiceBest: 3600);
    s.push(HiLoGameScreen(
      spec: HiLoGameSpec.practice(
        const HiLoTrainingConfig(
          players: 3,
          pace: HiLoPace.casino,
          frequency: HiLoQuizFrequency.often,
          questions: 10,
        ),
        seed: 777,
      ),
    ));
    await s.perfectGameResults();
    await s.popAll();

    // 6 · Five players at one online table.
    await s.onlineTable();
    await s.popAll();

    debugPrint('STORE_SHOTS_DONE');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

/// A player a few weeks in: a bankroll, a record at the table and the coach,
/// and a name.
Future<void> _seedPlayer(int dailyToday) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final day = DailyStreak.today();
  await prefs.setBool('onboarding_seen_v1', true);
  await prefs.setString('online_player_name', 'Alex');
  await prefs.setBool('sfx_enabled', false);
  await prefs.setInt('bankroll', 2450);
  await prefs.setInt('streak_last_claim_day', day - 1);
  await prefs.setInt('streak_days', 5);
  await prefs.setInt('streak_best', 9);
  await prefs.setInt('hands_played', 186);
  await prefs.setInt('wins', 84);
  await prefs.setInt('losses', 80);
  await prefs.setInt('pushes', 17);
  await prefs.setInt('blackjacks', 9);
  await prefs.setInt('table_net', 1450);
  await prefs.setInt('count_checks', 24);
  await prefs.setInt('count_checks_correct', 21);
  await prefs.setInt('strategy_total', 412);
  await prefs.setInt('strategy_correct', 377);
  await prefs.setInt('strategy_hard_total', 268);
  await prefs.setInt('strategy_hard_correct', 249);
  await prefs.setInt('strategy_soft_total', 88);
  await prefs.setInt('strategy_soft_correct', 75);
  await prefs.setInt('strategy_pair_total', 56);
  await prefs.setInt('strategy_pair_correct', 53);
  await prefs.setString(
      'strategy_misses', '{"Soft 18 vs 9":4,"Hard 12 vs 3":3,"9 vs 2":2}');
  // The coach's hint would give the answer away in the coach picture.
  await prefs.setBool('strategy_hints_enabled', false);
  await prefs.setBool('table_show_count', true);
  await prefs.setBool('table_count_check', false);
  await prefs.setInt('table_spot_count', 1);
  await _seedHiLo(dailyToday, xp: 2140);
}

/// A Hi-Lo record with a run of Daily Challenges behind it and today's still
/// to play.
Future<void> _seedHiLo(int today, {required int xp, int practiceBest = 3600}) {
  return HiLoTrainingProgress.saveProfile(HiLoProfile(
    xp: xp,
    games: 31,
    questions: 342,
    correct: 309,
    bestStreak: 23,
    holeCardReads: 8,
    practiceBest: practiceBest,
    survivalTop: const [6400, 5100, 4300],
    survivalBestLevel: 5,
    dailyLastPlayed: today - 1,
    dailyStreak: 4,
    dailyScores: {
      today - 1: 3900,
      today - 2: 3100,
      today - 3: 4200,
      today - 4: 2600,
    },
    duels: 3,
    challengesWon: 1,
    achievements: const {
      HiLoAchievement.firstCount,
      HiLoAchievement.quickDraw,
      HiLoAchievement.regular,
      HiLoAchievement.duelist,
      HiLoAchievement.challengeAccepted,
    },
    trueCountsAsked: 14,
    trueCountsRight: 9,
  ));
}

class _Stage {
  final WidgetTester tester;
  _Stage(this.tester);

  NavigatorState get _nav => appNavigatorKey.currentState!;

  Future<void> wait(int ms) => tester.pump(Duration(milliseconds: ms));

  Future<void> tap(Finder f) async {
    await tester.ensureVisible(f.first);
    await wait(300);
    await tester.tap(f.first);
    await wait(200);
  }

  void push(Widget screen) =>
      unawaited(_nav.push(MaterialPageRoute<void>(builder: (_) => screen)));

  Future<void> popAll() async {
    _nav.popUntil((r) => r.isFirst);
    await wait(1200);
  }

  /// Polls [done] while frames keep running; false if it never came true.
  Future<bool> until(bool Function() done, {int seconds = 60}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      if (done()) return true;
      await wait(60);
    }
    return done();
  }

  /// Ask the host script for a capture and hold still until it is taken.
  Future<void> shot(String name) async {
    final dir = Directory(_ackDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ack = File('$_ackDir/ack_$name');
    if (ack.existsSync()) ack.deleteSync();
    debugPrint('STORE_SHOT $name');
    final ok = await until(ack.existsSync, seconds: 30);
    if (!ok) debugPrint('STORE_SHOT_TIMEOUT $name');
  }

  ProviderContainer _container(Type screen) =>
      ProviderScope.containerOf(tester.element(find.byType(screen)));

  // ─── The coach ──────────────────────────────────────────────────────────

  /// Deal until a hand comes up where hitting is a mistake that keeps the
  /// hand alive — a double or split taken as a hit, or a hit on soft 18
  /// where the chart stands — then hit, so the coach names the right play
  /// mid-hand.
  Future<void> coachCorrection() async {
    push(const TableScreen());
    await wait(1500);
    final c = _container(TableScreen);
    final table = c.read(tableProvider.notifier);
    GameState state() => c.read(tableProvider);

    for (var hand = 0; hand < 60; hand++) {
      await until(() => state().phase == GamePhase.betting, seconds: 15);
      await wait(400);
      table.addChip(50);
      await wait(250);
      table.deal();
      await until(
        () =>
            state().phase == GamePhase.playerTurn ||
            state().phase == GamePhase.result,
        seconds: 15,
      );
      await wait(700);
      if (state().insuranceState == InsuranceState.offered) {
        table.takeInsurance(false);
        await wait(500);
      }
      while (state().phase == GamePhase.playerTurn) {
        final best = c.read(strategyHintProvider);
        final hand = state().activeHand;
        if (best == null) {
          await wait(200);
          continue;
        }
        final wrongButAlive = hand.cards.length == 2 &&
            (best == StrategyMove.double ||
                best == StrategyMove.split ||
                (hand.isSoft &&
                    best == StrategyMove.stand &&
                    hand.value <= 18));
        if (wrongButAlive) {
          table.hit();
          await wait(1400);
          if (state().phase == GamePhase.playerTurn &&
              c.read(strategyFeedbackProvider) != null) {
            await shot('05-coach');
            return;
          }
          break;
        }
        switch (best) {
          case StrategyMove.hit:
            table.hit();
          case StrategyMove.stand:
            table.stand();
          case StrategyMove.double:
            table.doubleDown();
          case StrategyMove.split:
            table.split();
          case StrategyMove.surrender:
            table.surrender();
        }
        await wait(700);
      }
      await until(() => state().phase == GamePhase.result, seconds: 20);
      await wait(900);
      table.nextHand();
    }
    debugPrint('STORE_SHOT_MISSING 05-coach');
  }

  // ─── Hi-Lo Training ─────────────────────────────────────────────────────

  HiLoTrainingSession? _session() {
    final view = find.byType(HiLoTableView);
    if (view.evaluate().isEmpty) return null;
    return tester.widget<HiLoTableView>(view).session;
  }

  bool _asking() =>
      find.byKey(const ValueKey('hilo-check')).evaluate().isNotEmpty;

  /// Key in the right running count, as a quick player would.
  Future<void> _enter(int count, {bool submit = true}) async {
    if (count < 0) {
      await tester.tap(find.byKey(const ValueKey('hilo-key-sign')));
    }
    for (final d in count.abs().toString().split('')) {
      await tester.tap(find.byKey(ValueKey('hilo-key-$d')));
      await wait(120);
    }
    if (submit) await tester.tap(find.byKey(const ValueKey('hilo-check')));
  }

  /// Answer the open question right and deal on. [verdictShot] captures the
  /// verdict before dealing on.
  Future<void> _answerRight({String? verdictShot}) async {
    await wait(350);
    await _enter(_session()!.openQuestion!.answer);
    await wait(900);
    final next = find.byKey(const ValueKey('hilo-continue'));
    await until(() => next.evaluate().isNotEmpty, seconds: 5);
    if (verdictShot != null) {
      await wait(1200);
      await shot(verdictShot);
    }
    await tester.tap(next);
    await wait(300);
  }

  int _cardsOut(HiLoTrainingSession s) =>
      s.dealer.cards.length +
      s.seats.fold<int>(0, (n, h) => n + h.cards.length);

  /// A few right answers in, then the moment just after a card lands on a
  /// round that is well under way.
  Future<void> hiLoMidRound() async {
    await wait(1500);
    var answered = 0;
    var lastCards = -1;
    for (var i = 0; i < 4000; i++) {
      final s = _session();
      if (s == null) {
        await wait(100);
        continue;
      }
      if (_asking()) {
        await _answerRight();
        answered++;
        lastCards = -1;
        continue;
      }
      final cards = _cardsOut(s);
      final landed = lastCards >= 0 && cards == lastCards + 1;
      lastCards = cards;
      // Players still acting, so the dealer's hole card is face down.
      final dealt = s.activeSeat != null &&
          s.seats.every((h) => h.cards.length >= 2) &&
          s.dealer.cards.length >= 2 &&
          s.seats.where((h) => h.cards.length >= 3).length >= 2;
      if (answered >= 3 && landed && dealt && !s.roundFinished) {
        await wait(420);
        if (!_asking()) {
          await shot('01-hilo-table');
          return;
        }
      }
      await wait(50);
    }
    debugPrint('STORE_SHOT_MISSING 01-hilo-table');
  }

  /// Through level 1 on a run of right answers, then the keypad mid-entry.
  Future<void> survivalKeypad() async {
    await wait(1500);
    var answered = 0;
    while (answered < 6) {
      await until(_asking, seconds: 40);
      await _answerRight();
      answered++;
    }
    // A count worth showing on the display: not 0 or ±1.
    while (true) {
      await until(_asking, seconds: 40);
      if (_session()!.openQuestion!.answer.abs() >= 2) break;
      await _answerRight();
    }
    await wait(500);
    final truth = _session()!.openQuestion!.answer;
    await _enter(truth, submit: false);
    await wait(700);
    await shot('02-survival-keypad');
  }

  /// Ten right answers at speed, to the results.
  Future<void> perfectGameResults() async {
    await wait(1500);
    for (var q = 0; q < 10; q++) {
      final ok = await until(_asking, seconds: 60);
      if (!ok) break;
      // The sixth right answer in a row lifts the combo to x3.
      await _answerRight(verdictShot: q == 5 ? '03b-verdict-combo' : null);
    }
    await until(
      () =>
          find.byKey(const ValueKey('hilo-final-score')).evaluate().isNotEmpty,
      seconds: 10,
    );
    // The score counts up, the XP bar fills, the confetti falls away.
    await wait(5200);
    await shot('03-results');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await wait(1200);
    await shot('03-results-scrolled');
  }

  // ─── Online ─────────────────────────────────────────────────────────────

  /// Alex hosts; four friends join, bet and are dealt in. Captured on Alex's
  /// turn, with every seat holding cards.
  Future<void> onlineTable() async {
    final broker = InMemoryBroker();
    const room = 'K7MQ2XPR9D';
    OnlineController seat(String id, String name, {bool host = false}) =>
        OnlineController(
          transport: broker.createClient(id),
          isHost: host,
          roomCode: room,
          playerName: name,
          hostProbe: Duration.zero,
        );

    final me = seat('alex', 'Alex', host: true);
    push(OnlineTableScreen(controller: me));
    await until(() => me.table != null, seconds: 10);
    await wait(500);

    final friends = [
      seat('maya', 'Maya'),
      seat('jordan', 'Jordan'),
      seat('priya', 'Priya'),
      seat('diego', 'Diego'),
    ];
    for (final f in friends) {
      await f.start();
      await wait(250);
    }
    await until(() => me.table!.seats.length == 5, seconds: 10);

    const bets = {'maya': 50, 'jordan': 25, 'priya': 100, 'diego': 25};
    for (final f in friends) {
      f.placeBet(bets[f.clientId]!);
    }
    me.placeBet(50);
    await until(
      () => me.table!.seats.every((s) => s.bet > 0),
      seconds: 10,
    );
    for (final f in friends) {
      f.setReady(true);
    }
    await wait(600);
    me.deal();
    await until(() => me.table!.phase != OnlinePhase.betting, seconds: 10);
    if (me.table!.phase == OnlinePhase.insurance) {
      for (final c in [me, ...friends]) {
        c.takeInsurance(false);
      }
    }
    // Friends ahead of Alex stand; stop on Alex's turn.
    final ready = await until(() {
      final t = me.table!;
      if (t.phase != OnlinePhase.playerTurns) return false;
      final active = t.activeSeatOrNull?.id;
      if (active == me.clientId) return true;
      for (final f in friends) {
        if (f.clientId == active && f.isMyTurn) f.stand();
      }
      return false;
    }, seconds: 20);
    await wait(1600);
    if (ready) {
      await shot('06-online-table');
    } else {
      debugPrint('STORE_SHOT_MISSING 06-online-table');
    }
    for (final f in friends) {
      f.dispose();
    }
  }
}

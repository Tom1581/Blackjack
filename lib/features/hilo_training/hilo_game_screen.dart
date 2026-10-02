import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/audio/sound_service.dart';
import '../../theme/app_theme.dart';
import '../online/widgets/felt_background.dart';
import '../table/widgets/discard_tray.dart';
import '../drill/daily_count_drill_screen.dart';
import '../training/speed_count_screen.dart';
import '../training/training_widgets.dart';
import '../training/true_count_drill_screen.dart';
import '../profile/player_identity.dart';
import 'daily_reminder.dart';
import 'hilo_boards_service.dart';
import 'hilo_game.dart';
import 'hilo_text.dart';
import 'hilo_training_progress.dart';
import 'hilo_training_session.dart';
import 'screen_awake.dart';
import 'widgets/confetti.dart';
import 'widgets/count_quiz_panel.dart';
import 'widgets/hilo_results_view.dart';
import 'widgets/hilo_table_view.dart';

enum _Quiz { none, answering, trueCount, handoff, verdict }

/// One game of Hi-Lo Training in any mode: the dealer deals, stops at a
/// random card, takes the answer (or both answers, in a duel), scores it,
/// and deals on until the game ends — then the results.
class HiLoGameScreen extends StatefulWidget {
  final HiLoGameSpec spec;

  const HiLoGameScreen({super.key, required this.spec});

  @override
  State<HiLoGameScreen> createState() => _HiLoGameScreenState();
}

class _HiLoGameScreenState extends State<HiLoGameScreen>
    with WidgetsBindingObserver {
  late HiLoGame _game;
  HiLoEvent? _lastEvent;
  Timer? _dealTimer;
  Timer? _answerTimer;
  Timer? _flashTimer;
  bool _paused = false;
  _Quiz _quiz = _Quiz.none;
  int _panel = 0;

  /// Times the current answer, for the speed bonus and the answer clock.
  final _clock = Stopwatch();

  /// What happens when the answer clock runs out on the current step.
  VoidCallback? _onTimeout;

  /// The answer clock is stopped while the app is away or the leave dialog
  /// is up, and picks up where it left off.
  bool _clockSuspended = false;
  bool _leaveDialogOpen = false;

  /// A line flashed across the felt: a level reached, a new shoe.
  String? _flash;

  bool _finished = false;
  HiLoGameReward? _reward;

  /// The player's best in this mode, shown in the HUD and flashed when
  /// passed. Null where there is none to chase.
  int? _best;
  bool _bestPassed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _begin(widget.spec);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dealTimer?.cancel();
    _answerTimer?.cancel();
    _flashTimer?.cancel();
    unawaited(ScreenAwake.set(false));
    super.dispose();
  }

  /// The app is on screen. The wake lock only matters while it is.
  bool _foreground = true;

  /// Hold the screen on while cards are being dealt or a question is up —
  /// the player watches without touching the phone — and let it sleep when
  /// the game is paused, over, or not on screen.
  void _syncWake() {
    unawaited(
        ScreenAwake.set(mounted && _foreground && !_finished && !_paused));
  }

  /// Leaving the app pauses the dealer rather than dealing on unseen, and
  /// stops the answer clock — a phone call should not cost a question.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncWake();
    if (_finished) return;
    if (state != AppLifecycleState.resumed) {
      if (!_paused && _quiz == _Quiz.none) _togglePause();
      _suspendClock();
    } else if (!_leaveDialogOpen) {
      _resumeClock();
    }
  }

  void _begin(HiLoGameSpec spec) {
    _dealTimer?.cancel();
    _answerTimer?.cancel();
    _flashTimer?.cancel();
    _clockSuspended = false;
    _onTimeout = null;
    _game = HiLoGame(spec);
    _lastEvent = null;
    _paused = false;
    _quiz = _Quiz.none;
    _finished = false;
    _reward = null;
    _flash = null;
    _best = null;
    _bestPassed = false;
    unawaited(_loadBest(spec));
    if (spec.mode == HiLoMode.daily && spec.ranked) {
      unawaited(HiLoTrainingProgress.startDailyAttempt(spec.dailyNumber!));
    }
    // Long enough for the page to finish sliding in and the opening banner
    // to be read before the first card.
    _scheduleTick(const Duration(milliseconds: 1800));
    _syncWake();
  }

  Future<void> _loadBest(HiLoGameSpec spec) async {
    // Only a game that can set a record has one to chase.
    if (spec.isDuel || spec.isChallenge || !spec.ranked) return;
    final profile = await HiLoTrainingProgress.loadProfile();
    final best = switch (spec.mode) {
      HiLoMode.survival => profile.survivalBest,
      HiLoMode.practice => profile.practiceBest,
      HiLoMode.daily => profile.dailyBest,
      _ => 0,
    };
    if (mounted && best > 0 && identical(spec, _game.spec)) {
      setState(() => _best = best);
    }
  }

  void _playAgain() {
    HapticFeedback.mediumImpact();
    setState(() => _begin(_game.spec.again()));
  }

  // ─── The dealer's clock ─────────────────────────────────────────────────

  void _scheduleTick(Duration delay) {
    _dealTimer?.cancel();
    _dealTimer = Timer(delay, _tick);
  }

  void _tick() {
    if (!mounted || _finished || _paused || _quiz != _Quiz.none) return;
    if (_game.quizDue) {
      _game.ask();
      HapticFeedback.mediumImpact();
      _startTurn();
      return;
    }
    final event = _game.session.advance();
    switch (event.kind) {
      case HiLoEventKind.card:
      case HiLoEventKind.holeCard:
      case HiLoEventKind.reveal:
        SoundService.play(Sfx.card);
      case HiLoEventKind.shuffle:
        HapticFeedback.lightImpact();
        _showFlash('NEW SHOE — THE COUNT STARTS AGAIN AT 0',
            const Duration(milliseconds: 2400));
      case HiLoEventKind.roundOver:
      case HiLoEventKind.sweep:
        break;
    }
    setState(() => _lastEvent = event);
    _scheduleTick(_delayAfter(event));
  }

  Duration _delayAfter(HiLoEvent event) {
    final ms = _game.pace.inMilliseconds;
    return Duration(
      milliseconds: switch (event.kind) {
        HiLoEventKind.roundOver => (ms * 1.8).round(),
        HiLoEventKind.sweep => (ms * 0.7).round(),
        HiLoEventKind.shuffle => max(2400, ms * 2),
        _ => ms,
      },
    );
  }

  void _showFlash(String text, Duration howLong) {
    _flashTimer?.cancel();
    setState(() => _flash = text);
    _flashTimer = Timer(howLong, () {
      if (mounted) setState(() => _flash = null);
    });
  }

  // ─── Questions ──────────────────────────────────────────────────────────

  void _startTurn() => _openStep(_Quiz.answering, () => _submit(null));

  /// Show a question step and start its answer clock.
  void _openStep(_Quiz step, VoidCallback onTimeout) {
    setState(() {
      _quiz = step;
      _panel++;
      _clockSuspended = false;
    });
    _clock
      ..reset()
      ..start();
    _onTimeout = onTimeout;
    _answerTimer?.cancel();
    final limit = _game.spec.answerLimit;
    if (limit != null) _answerTimer = Timer(limit, onTimeout);
  }

  void _suspendClock() {
    if (_clockSuspended ||
        (_quiz != _Quiz.answering && _quiz != _Quiz.trueCount)) {
      return;
    }
    _answerTimer?.cancel();
    _clock.stop();
    setState(() => _clockSuspended = true);
  }

  void _resumeClock() {
    if (!_clockSuspended) return;
    setState(() => _clockSuspended = false);
    _clock.start();
    final limit = _game.spec.answerLimit;
    final onTimeout = _onTimeout;
    if (limit == null || onTimeout == null) return;
    final left = limit - _clock.elapsed;
    _answerTimer = Timer(left.isNegative ? Duration.zero : left, onTimeout);
  }

  void _submit(int? given) {
    if (!mounted || _quiz != _Quiz.answering) return;
    _answerTimer?.cancel();
    _clock.stop();
    final answer = _game.submit(given, took: _clock.elapsed);
    if (_game.awaitingTrueCount) {
      HapticFeedback.selectionClick();
      _openStep(_Quiz.trueCount, () => _submitTrueCount(null));
      return;
    }
    _afterAnswer(answer);
  }

  void _submitTrueCount(int? trueCount) {
    if (!mounted || _quiz != _Quiz.trueCount) return;
    _answerTimer?.cancel();
    _clock.stop();
    _afterAnswer(_game.submitTrueCount(trueCount));
  }

  void _afterAnswer(HiLoAnswer? answer) {
    if (_game.midQuestion) {
      // Duel: hide this answer and hand over.
      HapticFeedback.mediumImpact();
      setState(() {
        _quiz = _Quiz.handoff;
        _panel++;
      });
      return;
    }
    final resolution = _game.lastResolution!;
    if (resolution.newLevel != null) {
      SoundService.play(Sfx.blackjack);
      HapticFeedback.heavyImpact();
    } else if (_game.spec.isDuel || answer == null) {
      SoundService.play(Sfx.chip);
    } else if (answer.correct) {
      SoundService.play(Sfx.win);
      HapticFeedback.lightImpact();
    } else {
      SoundService.play(answer.timedOut ? Sfx.push : Sfx.lose);
      HapticFeedback.heavyImpact();
    }
    setState(() {
      _quiz = _Quiz.verdict;
      _panel++;
    });
  }

  void _continue() {
    if (_game.isOver) {
      _finish();
      return;
    }
    final level = _game.lastResolution?.newLevel;
    setState(() => _quiz = _Quiz.none);
    final best = _best;
    if (!_bestPassed && best != null && _game.players.first.score > best) {
      _bestPassed = true;
      SoundService.play(Sfx.blackjack);
      _showFlash('NEW BEST!  ${points(_game.players.first.score)}',
          const Duration(milliseconds: 1800));
    } else if (level != null) {
      _showFlash('LEVEL $level', const Duration(milliseconds: 1800));
    }
    _scheduleTick(Duration(milliseconds: min(700, _game.pace.inMilliseconds)));
  }

  void _togglePause() {
    if (_paused) {
      setState(() => _paused = false);
      _scheduleTick(const Duration(milliseconds: 500));
    } else {
      _dealTimer?.cancel();
      setState(() => _paused = true);
    }
    _syncWake();
  }

  int get _answersGiven => _game.players.fold(0, (n, p) => n + p.answered);

  /// Leaving would cost something: answers already given, or the day's one
  /// ranked Daily try, which counts from the first card.
  bool get _hasStakes =>
      !_finished &&
      (_answersGiven > 0 ||
          (_game.spec.mode == HiLoMode.daily && _game.spec.ranked));

  /// FINISH, the back arrow or the system back: ask first when leaving
  /// would cost something, then end the game.
  Future<void> _requestLeave() async {
    if (_leaveDialogOpen) return;
    if (!_hasStakes) {
      _endEarly();
      return;
    }
    final wasPaused = _paused;
    if (!_paused && _quiz == _Quiz.none) _togglePause();
    _leaveDialogOpen = true;
    _suspendClock();
    final daily = _game.spec.mode == HiLoMode.daily && _game.spec.ranked;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('End this game?'),
        content: Text(
          daily
              ? 'Today\'s ranked try counts from the first card. End now and '
                  'it scores what you have so far.'
              : 'Your game so far will be scored.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('hilo-keep-playing'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('KEEP PLAYING'),
          ),
          TextButton(
            key: const ValueKey('hilo-end-game'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('END GAME'),
          ),
        ],
      ),
    );
    _leaveDialogOpen = false;
    if (!mounted || _finished) return;
    if (leave == true) {
      _endEarly();
    } else {
      _resumeClock();
      if (!wasPaused && _paused) _togglePause();
    }
  }

  /// End here. With nothing answered there is nothing to score.
  void _endEarly() {
    if (_answersGiven == 0) {
      Navigator.of(context).pop();
      return;
    }
    _game.quit();
    _finish();
  }

  Future<void> _finish() async {
    // Once per game: a double tap on SEE RESULTS must not score it twice.
    if (_finished) return;
    final game = _game;
    _dealTimer?.cancel();
    _answerTimer?.cancel();
    setState(() {
      _finished = true;
      _quiz = _Quiz.none;
    });
    _syncWake();
    HiLoGameReward reward;
    try {
      reward = await HiLoTrainingProgress.recordGame(game);
    } catch (error) {
      // The results still show; only the saved record is missing.
      debugPrint('Hi-Lo Training: could not save the game: $error');
      reward = applyGame(const HiLoProfile(), game);
    }
    // Shared-board failures must never delay or hide the local result.
    unawaited(HiLoBoardsService.submitGame(game));
    // Today's shoe is played: the pending reminder moves to tomorrow.
    if (game.spec.mode == HiLoMode.daily) {
      unawaited(DailyReminder.refresh());
    }
    // PLAY AGAIN may already have started the next game.
    if (!mounted || !identical(game, _game)) return;
    if (reward.newBest ||
        reward.unlocked.isNotEmpty ||
        reward.rankUp != null ||
        game.challengeWon) {
      SoundService.play(Sfx.blackjack);
      HapticFeedback.heavyImpact();
    }
    setState(() => _reward = reward);
  }

  /// The drill the results recommend, opened over the results.
  void _openNextDrill(HiLoNextDrill drill) {
    HapticFeedback.lightImpact();
    final Widget screen = switch (drill) {
      HiLoNextDrill.speedCount => const SpeedCountScreen(),
      HiLoNextDrill.tagDrill => const DailyCountDrillScreen(),
      HiLoNextDrill.trueCount => const TrueCountDrillScreen(),
      HiLoNextDrill.relaxedPractice => HiLoGameScreen(
          spec: HiLoGameSpec.practice(const HiLoTrainingConfig(
            players: 2,
            pace: HiLoPace.relaxed,
            frequency: HiLoQuizFrequency.often,
            questions: 10,
          )),
        ),
      HiLoNextDrill.survival => HiLoGameScreen(spec: HiLoGameSpec.survival()),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _share(BuildContext shareContext) async {
    final box = shareContext.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final name = await PlayerIdentity.load();
    await Share.share(
      shareText(_game, playerName: name),
      subject: 'Beat my Hi-Lo count',
      sharePositionOrigin: origin,
    );
  }

  // ─── Screens ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasStakes,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestLeave();
      },
      child: _finished ? _results() : _live(),
    );
  }

  Widget _live() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FeltBackground(
        child: Stack(
          children: [
            SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      _header(),
                      _hud(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                          // Screen readers skip the dimmed table while a
                          // question is up.
                          child: ExcludeSemantics(
                            excluding: _quiz != _Quiz.none,
                            child: HiLoTableView(session: _game.session),
                          ),
                        ),
                      ),
                      _controls(),
                    ],
                  ),
                  // On the open felt between the dealer and the seats, so it
                  // never hides a card.
                  if (_bannerText() case final text?)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: const Alignment(0, -0.02),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: _Banner(text: text),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The dim reaches under the status bar too, so the whole screen
            // steps back behind the question.
            if (_quiz != _Quiz.none)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.72),
                  alignment: Alignment.center,
                  child: SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: KeyedSubtree(
                        key: ValueKey('hilo-panel-$_panel'),
                        child: _panelFor(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _bannerText() {
    if (_quiz != _Quiz.none) return null;
    if (_paused) return 'PAUSED';
    if (_flash != null) return _flash;
    if (_lastEvent == null) {
      return _game.spec.isDuel
          ? 'BOTH OF YOU KEEP THE COUNT'
          : 'KEEP THE COUNT — THE DEALER WILL ASK';
    }
    return null;
  }

  String? get _progress {
    final count = _game.questionCount;
    return count == null
        ? 'Q${_game.questionNumber}'
        : '${_game.questionNumber} / $count';
  }

  Widget _panelFor() {
    final game = _game;
    switch (_quiz) {
      case _Quiz.none:
        return const SizedBox.shrink();
      case _Quiz.answering:
        final duel = game.spec.isDuel;
        return CountKeypadPanel(
          title: duel
              ? '${game.turnPlayer.name.toUpperCase()}\'S COUNT'
              : 'COUNT CHECK',
          progress: _progress,
          accent: duel ? duelColors[game.turn] : AppColors.gold,
          prompt: duel
              ? 'The dealer stops. Enter your running count — '
                  'keep it secret.'
              : 'The dealer stops. What is the running count?',
          limit: game.spec.answerLimit,
          clockRunning: !_clockSuspended,
          onSubmit: _submit,
        );
      case _Quiz.trueCount:
        final running = game.pendingRunningCount ?? 0;
        final session = game.session;
        return CountKeypadPanel(
          title: 'TRUE COUNT',
          progress: _progress,
          prompt: 'Your running count: ${signedCount(running)}. Divide it by '
              'the decks left in the shoe.',
          limit: game.spec.answerLimit,
          clockRunning: !_clockSuspended,
          extra: DecksLeftHint(
            penetration: session.discardFill,
            decks: session.config.decks,
          ),
          onSubmit: _submitTrueCount,
        );
      case _Quiz.handoff:
        final from = game.players[(game.turn + 1) % game.players.length];
        return HandoffPanel(
          from: from.name,
          to: game.turnPlayer.name,
          toColor: duelColors[game.turn],
          onReady: _startTurn,
        );
      case _Quiz.verdict:
        final resolution = game.lastResolution!;
        final label = game.isOver ? 'SEE RESULTS' : 'KEEP DEALING';
        if (game.spec.isDuel) {
          return DuelRevealPanel(
            resolution: resolution,
            players: game.players,
            progress: _progress,
            continueLabel: label,
            onContinue: _continue,
          );
        }
        return VerdictPanel(
          answer: resolution.answers.first,
          streak: game.players.first.streak,
          progress: _progress,
          lives: game.spec.isSurvival ? game.lives : null,
          lifeLost: resolution.lifeLost,
          newLevel: resolution.newLevel,
          continueLabel: label,
          onContinue: _continue,
        );
    }
  }

  Widget _header() {
    final spec = _game.spec;
    final title = switch (spec.mode) {
      HiLoMode.daily => 'DAILY #${spec.dailyNumber}',
      HiLoMode.survival => spec.isChallenge ? 'SURVIVAL CHALLENGE' : 'SURVIVAL',
      _ => spec.mode.label.toUpperCase(),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
          if (spec.isSurvival)
            LivesRow(lives: _game.lives, size: 20)
          else
            TrainingBadge(
              '${_game.session.questionsClosed}/${_game.questionCount}',
            ),
        ],
      ),
    );
  }

  Widget _hud() {
    final game = _game;
    final session = game.session;
    final detail = [
      'Round ${max(1, session.round)}',
      'Shoe ${session.shoeNumber}',
      '${session.players} player${session.players == 1 ? '' : 's'}',
      if (game.spec.isSurvival)
        'Level ${game.level}'
      else
        game.spec.config.pace.label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (game.spec.isDuel)
                  _DuelScores(players: game.players)
                else
                  _ScoreLine(game: game, best: _best),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          DiscardTray(
            penetration: session.discardFill,
            decks: session.config.decks,
            height: 40,
          ),
        ],
      ),
    );
  }

  /// Tighter than the theme's padding so both labels stay whole on a 320 dp
  /// phone.
  static final _controlStyle = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12),
  );

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _togglePause,
                style: _controlStyle,
                icon: Icon(
                  _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 20,
                ),
                label: _ControlLabel(_paused ? 'RESUME' : 'PAUSE'),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _requestLeave,
                style: _controlStyle,
                icon: const Icon(Icons.flag_outlined, size: 20),
                label: const _ControlLabel('FINISH'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results() {
    final reward = _reward;
    final game = _game;
    final celebrate = reward != null &&
        (reward.newBest ||
            reward.rankUp != null ||
            game.challengeWon ||
            (game.spec.isDuel && game.winner != null) ||
            (!game.spec.isDuel &&
                game.players.first.answered >= 5 &&
                game.players.first.perfect));
    return Stack(
      children: [
        TrainingScaffold(
          title: 'RESULTS',
          child: HiLoResultsView(
            game: game,
            reward: reward,
            onPlayAgain: _playAgain,
            onDone: () => Navigator.of(context).pop(),
            onShare: game.spec.isDuel ? null : _share,
            onNextDrill: game.spec.isDuel ? null : _openNextDrill,
          ),
        ),
        if (celebrate) const Positioned.fill(child: Confetti()),
      ],
    );
  }
}

/// Score, combo and — in a challenge — the friend's score to beat.
class _ScoreLine extends StatelessWidget {
  final HiLoGame game;
  final int? best;

  const _ScoreLine({required this.game, this.best});

  @override
  Widget build(BuildContext context) {
    final player = game.players.first;
    final target = game.spec.targetScore;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        _AnimatedScore(score: player.score),
        if (player.streak >= 3) ComboChip(combo: player.combo),
        if (best != null && target == null)
          Text(
            player.score > best! ? 'NEW BEST' : 'BEST ${points(best!)}',
            style: TextStyle(
              color: player.score > best!
                  ? AppColors.success
                  : Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        if (target != null)
          Text(
            'TO BEAT ${points(target)}',
            style: TextStyle(
              color: player.score > target
                  ? AppColors.success
                  : Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
      ],
    );
  }
}

class _AnimatedScore extends StatelessWidget {
  final int score;
  final Color color;

  const _AnimatedScore({required this.score, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: score, end: score),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (_, value, __) => Text(
        points(value),
        key: const ValueKey('hilo-score'),
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _DuelScores extends StatelessWidget {
  final List<HiLoPlayer> players;

  const _DuelScores({required this.players});

  @override
  Widget build(BuildContext context) {
    Widget side(int i) => Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  players[i].name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: duelColors[i],
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              _AnimatedScore(score: players[i].score, color: duelColors[i]),
            ],
          ),
        );
    return Row(
      children: [
        side(0),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'vs',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        side(1),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(text),
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutBack,
        builder: (_, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.wood.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.25),
                blurRadius: 16,
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A control button's label: one line, shrunk rather than broken mid-word.
class _ControlLabel extends StatelessWidget {
  final String text;
  const _ControlLabel(this.text);

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      );
}

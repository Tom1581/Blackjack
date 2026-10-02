import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ads/ad_service.dart';
import '../../core/models/card_model.dart';
import '../../core/audio/sound_service.dart';
import '../../core/progress/daily_streak.dart';
import '../../core/strategy/strategy_coach.dart';
import '../../theme/app_theme.dart';
import '../leaderboard/leaderboard_providers.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../leaderboard/leaderboard_service.dart';
import '../leaderboard/weekly_board_service.dart';
import '../leaderboard/widgets/crown_icon.dart';
import '../drill/daily_count_drill_screen.dart';
import '../hilo_training/hilo_training_screen.dart';
import '../online/online_entry_screen.dart';
import '../stats/stats_screen.dart';
import '../table/table_provider.dart';
import '../table/table_screen.dart';
import '../table/widgets/card_widget.dart';
import '../training/drills.dart' show StrategyDrillFocus;
import '../training/speed_count_screen.dart';
import '../training/strategy_drill_screen.dart';
import '../training/training_center_screen.dart';
import '../hilo_training/hilo_game.dart';
import '../hilo_training/hilo_game_screen.dart';
import '../hilo_training/hilo_training_progress.dart';
import '../profile/player_identity.dart';
import '../../core/progress/player_stats.dart';
import 'next_step.dart';
import 'practice_setup.dart';
import 'session_report.dart';
import 'widgets/brand_lockup.dart';
import 'widgets/home_cards.dart';
import 'widgets/session_report_sheet.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<Offset> _heroSlide;

  late final AnimationController _shimmerCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    );
    _entranceFade =
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
    ));
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
    ));
    _entranceCtrl.forward();

    _shimmerCtrl = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _floatCtrl = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);

    ref.read(tableProvider.notifier).init();
    unawaited(ref.read(adServiceProvider).initialize());
    _refreshHome();
  }

  /// The player's name, for the profile row ('' until they set one).
  String _name = '';

  /// Today's next step; null while the player's record loads.
  NextStep? _nextStep;

  /// Re-read what the home screen shows from the player's record — after
  /// any screen it opened, since a game or a drill changes the suggestion.
  void _refreshHome() {
    unawaited(_loadName());
    unawaited(_loadNextStep());
  }

  Future<void> _loadName() async {
    final name = await PlayerIdentity.load();
    if (mounted) setState(() => _name = name);
  }

  Future<void> _loadNextStep() async {
    final inputs = NextStepInputs(
      stats: await PlayerStatsStore.read(),
      mastery: await StrategyCoach.readMastery(),
      hilo: await HiLoTrainingProgress.loadProfile(),
      today: HiLoDaily.numberFor(DateTime.now()),
    );
    if (mounted) setState(() => _nextStep = pickNextStep(inputs));
  }

  /// Open [screen]; refresh the home screen when the player comes back.
  Future<void> _go(Widget screen, {bool strong = false}) async {
    strong ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refreshHome();
  }

  /// PLAY: the table, then — after a session worth summing up — a short
  /// report with the one mistake that mattered and the drill to do next.
  Future<void> _playTable() async {
    HapticFeedback.mediumImpact();
    final before = await TableSnapshot.take();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const TableScreen()));
    if (!mounted) return;
    _refreshHome();
    final report = SessionReport.between(before, await TableSnapshot.take());
    if (!mounted || !report.worthShowing) return;
    final drill = await showSessionReportSheet(
      context,
      report: report,
      rules: ref.read(rulesProvider),
      decks: ref.read(shoeModeProvider).numDecks,
    );
    if (drill != null && mounted) unawaited(_go(_drillScreen(drill)));
  }

  Widget _drillScreen(NextDrill drill) => switch (drill) {
        NextDrill.mistakes =>
          const StrategyDrillScreen(initialFocus: StrategyDrillFocus.mistakes),
        NextDrill.strategy => const StrategyDrillScreen(),
        NextDrill.speedCount => const SpeedCountScreen(),
        NextDrill.hiLoTraining => const HiLoTrainingScreen(),
      };

  Future<void> _editName() async {
    final saved = await showEditNameSheet(context, current: _name);
    if (saved != null && mounted) setState(() => _name = saved);
  }

  void _openNextStep(NextStep step) {
    switch (step.action) {
      case NextStepAction.playTable:
        unawaited(_playTable());
      case NextStepAction.playDaily:
        unawaited(_go(
            HiLoGameScreen(spec: HiLoGameSpec.daily(step.dailyNumber!)),
            strong: true));
      case NextStepAction.drillMistakes:
      case NextStepAction.drillCategory:
        unawaited(_go(StrategyDrillScreen(
            initialFocus: step.focus ?? StrategyDrillFocus.all)));
      case NextStepAction.speedCount:
        unawaited(_go(const SpeedCountScreen()));
      case NextStepAction.survival:
        unawaited(
            _go(HiLoGameScreen(spec: HiLoGameSpec.survival()), strong: true));
    }
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _shimmerCtrl.dispose();
    _floatCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tableProvider);
    final step = _nextStep;

    return Scaffold(
      body: Stack(
        children: [
          // Layer 1 — radial casino-floor background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.35),
                radius: 1.2,
                colors: [
                  Color(0xFF1A4828),
                  Color(0xFF0B2116),
                  Color(0xFF050E08),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // Layer 2 — scattered suit watermarks
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _SuitWatermarkPainter()),
            ),
          ),

          // Layer 3 — content. Above the fold on any phone: who you are,
          // what to do next, and PLAY.
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: FadeTransition(
                opacity: _entranceFade,
                child: Column(
                  children: [
                    SlideTransition(
                      position: _titleSlide,
                      child: BrandLockup(shimmer: _shimmerCtrl),
                    ),
                    const SizedBox(height: 8),
                    SlideTransition(
                      position: _heroSlide,
                      child: _HeroCards(float: _floatCtrl),
                    ),
                    const SizedBox(height: 10),
                    ProfileBankrollRow(
                      name: _name,
                      bankroll: state.bankroll,
                      onEditName: _editName,
                    ),
                    const SizedBox(height: 12),
                    NextStepCard(
                      step: step,
                      onTap: step == null ? null : () => _openNextStep(step),
                    ),
                    const SizedBox(height: 14),
                    _GlowingPlayButton(
                      pulse: _pulseCtrl,
                      enabled: state.bankroll > 0,
                      onTap: _playTable,
                    ),
                    const SizedBox(height: 14),
                    const _DailyStreakCard(),
                    const SizedBox(height: 14),
                    _SecondaryButton(
                      icon: Icons.style_outlined,
                      label: 'HI-LO  TRAINING',
                      accent: AppColors.drill,
                      onTap: () => _go(const HiLoTrainingScreen()),
                    ),
                    const SizedBox(height: 12),
                    _SecondaryButton(
                      icon: Icons.timer_outlined,
                      label: 'DAILY  COUNT  DRILL',
                      accent: AppColors.drill,
                      onTap: () => _go(const DailyCountDrillScreen()),
                    ),
                    const SizedBox(height: 12),
                    _SecondaryButton(
                      icon: Icons.school_outlined,
                      label: 'TRAINING  CENTER',
                      accent: AppColors.drill,
                      onTap: () => _go(const TrainingCenterScreen()),
                    ),
                    const SizedBox(height: 12),
                    _SecondaryButton(
                      icon: Icons.groups,
                      label: 'PLAY  ONLINE  WITH  FRIENDS',
                      accent: AppColors.social,
                      onTap: () => _go(const OnlineEntryScreen(), strong: true),
                    ),
                    const SizedBox(height: 14),
                    const _WeeklyTop3Card(),
                    const SizedBox(height: 10),
                    _SecondaryButton(
                      icon: Icons.bar_chart,
                      label: 'STATS  &  HISTORY',
                      onTap: () => _go(const StatsScreen()),
                    ),
                    const SizedBox(height: 18),
                    const PracticeSetupCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Hero — Ace of Spades + King of Hearts, tilted, gently floating.
// ─────────────────────────────────────────────────────────────────────────

class _HeroCards extends StatelessWidget {
  final Animation<double> float;
  const _HeroCards({required this.float});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: AnimatedBuilder(
        animation: float,
        builder: (_, __) {
          final t = float.value;
          // Two cards float in opposite phases for life.
          final dy1 = math.sin(t * math.pi) * 4;
          final dy2 = math.sin((t + 0.5) * math.pi) * 4;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Soft golden halo behind the pair
              Container(
                width: 190,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(80),
                  gradient: RadialGradient(
                    colors: [
                      AppColors.gold.withValues(alpha: 0.18),
                      AppColors.gold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              // Left card — Ace of Spades, tilted left, slightly down
              Transform.translate(
                offset: Offset(-32, dy1),
                child: Transform.rotate(
                  angle: -8 * math.pi / 180,
                  child: const CardWidget(
                    card: CardModel(
                        suit: Suit.spades, rank: Rank.ace, faceUp: true),
                    width: 78,
                    animate: false,
                  ),
                ),
              ),
              // Right card — King of Hearts, tilted right
              Transform.translate(
                offset: Offset(32, dy2),
                child: Transform.rotate(
                  angle: 6 * math.pi / 180,
                  child: const CardWidget(
                    card: CardModel(
                        suit: Suit.hearts, rank: Rank.king, faceUp: true),
                    width: 78,
                    animate: false,
                  ),
                ),
              ),
              // "BLACKJACK!" tag floating above
              Positioned(
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.gold.withValues(alpha: 0.55),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    'BLACKJACK · 21',
                    style: TextStyle(
                      color: AppColors.wood,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Glowing PLAY button with pulsing halo.
// ─────────────────────────────────────────────────────────────────────────

class _GlowingPlayButton extends StatelessWidget {
  final Animation<double> pulse;
  final bool enabled;
  final VoidCallback onTap;

  const _GlowingPlayButton({
    required this.pulse,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) {
        final glow = enabled ? 0.35 + pulse.value * 0.35 : 0.0;
        return GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: double.infinity,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: enabled
                    ? const [
                        Color(0xFFFFE680),
                        Color(0xFFD4AF37),
                        Color(0xFFB8860B)
                      ]
                    : [
                        AppColors.goldDim.withValues(alpha: 0.6),
                        AppColors.goldDim.withValues(alpha: 0.4),
                      ],
                stops: enabled ? const [0.0, 0.5, 1.0] : null,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: enabled
                    ? const Color(0xFFFFE680)
                    : Colors.white.withValues(alpha: 0.2),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: glow),
                  blurRadius: 28,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.wood,
                  size: 30,
                ),
                const SizedBox(width: 6),
                Text(
                  'PLAY A HAND',
                  style: TextStyle(
                    color: AppColors.wood,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    shadows: [
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Secondary buttons (Leaderboard / Stats)
// ─────────────────────────────────────────────────────────────────────────

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The mode accent: blue for drills, violet for playing with friends, gold
  /// for everything else.
  final Color accent;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: accent),
        label: Text(
          label,
          style: const TextStyle(
            letterSpacing: 1.5,
            fontSize: 12,
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.25),
          side: BorderSide(color: accent.withValues(alpha: 0.4)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Settings panel & Hi-Lo explainer (kept compact below the fold).
// ─────────────────────────────────────────────────────────────────────────

/// Sound is a device preference rather than game state, so it keeps its own
/// little bit of state instead of living in a provider.
/// The reason to open the app tomorrow. Deliberately low-pressure: no
/// countdown, no warning that a streak is about to lapse — just a reward that
/// grows across a week and quietly starts over if a day is missed.
class _DailyStreakCard extends ConsumerStatefulWidget {
  const _DailyStreakCard();

  @override
  ConsumerState<_DailyStreakCard> createState() => _DailyStreakCardState();
}

class _DailyStreakCardState extends ConsumerState<_DailyStreakCard> {
  StreakState? _state;
  bool _claiming = false;
  bool _doubling = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final next = await DailyStreak.read();
    if (mounted) setState(() => _state = next);
  }

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final chips = await DailyStreak.claim();
    if (chips > 0) {
      HapticFeedback.mediumImpact();
      SoundService.play(Sfx.chip);
      ref.read(tableProvider.notifier).addReward(chips);
    }
    if (!mounted) return;
    setState(() => _claiming = false);
    await _refresh();
    if (!mounted || chips <= 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Daily bonus claimed — \$$chips chips'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Opt-in ad: the player chooses to watch it, and only gets the extra chips
  /// if they actually finish it.
  Future<void> _watchToDouble() async {
    if (_doubling) return;
    setState(() => _doubling = true);
    final earned = await ref.read(adServiceProvider).showRewarded();
    if (!mounted) return;

    var bonus = 0;
    if (earned) {
      bonus = await DailyStreak.claimDouble();
      if (bonus > 0) {
        HapticFeedback.heavyImpact();
        SoundService.play(Sfx.chip);
        ref.read(tableProvider.notifier).addReward(bonus);
      }
    }
    if (!mounted) return;
    setState(() => _doubling = false);
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bonus > 0
              ? 'Bonus doubled — another \$$bonus chips'
              : 'No chips added — the ad was not finished',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) return const SizedBox(height: 84);
    final ready = !state.claimedToday;
    // Only offer the ad when one is genuinely loaded and ready to play.
    final rewardedReady = ref.watch(
      adServiceProvider.select((service) => service.rewardedReady),
    );
    final canDouble = state.canDouble && rewardedReady;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ready
              ? [const Color(0xFF3A2606), const Color(0xFF1C1204)]
              : [const Color(0xFF16200F), const Color(0xFF0D1608)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: ready ? 0.55 : 0.2),
          width: ready ? 1.5 : 1,
        ),
        boxShadow: ready
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.18),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.card_giftcard : Icons.check_circle_outline,
                size: 16,
                color: AppColors.gold.withValues(alpha: ready ? 1 : 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                ready ? 'DAILY BONUS' : 'CLAIMED TODAY',
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: ready ? 1 : 0.6),
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                state.streak > 0
                    ? '${state.streak} day streak'
                    : 'start a streak',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var day = 1; day <= DailyStreak.cycleLength; day++)
                _StreakPip(
                  day: day,
                  reward: DailyStreak.rewards[day - 1],
                  filled: state.pipFilled(day),
                  isToday: state.pipIsToday(day),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (ready)
            GestureDetector(
              onTap: _claiming ? null : _claim,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFE680),
                      AppColors.gold,
                      Color(0xFFB8860B),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.4),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: Text(
                  _claiming ? 'CLAIMING…' : 'CLAIM \$${state.todayReward}',
                  style: const TextStyle(
                    color: AppColors.wood,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            )
          else if (canDouble)
            GestureDetector(
              onTap: _doubling ? null : _watchToDouble,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.7), width: 1.5),
                  color: AppColors.gold.withValues(alpha: 0.12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.play_circle_outline,
                        size: 18, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Text(
                      _doubling
                          ? 'LOADING…'
                          : 'WATCH AD TO DOUBLE  +\$${state.todayReward}',
                      style: const TextStyle(
                        color: AppColors.gold,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              state.doubledToday
                  ? 'Doubled today — back tomorrow for \$${state.tomorrowReward}'
                  : 'Back tomorrow for \$${state.tomorrowReward}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _StreakPip extends StatelessWidget {
  final int day;
  final int reward;
  final bool filled;
  final bool isToday;

  const _StreakPip({
    required this.day,
    required this.reward,
    required this.filled,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final active = filled || isToday;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                filled ? AppColors.gold : Colors.black.withValues(alpha: 0.35),
            border: Border.all(
              color: isToday
                  ? AppColors.gold
                  : AppColors.gold.withValues(alpha: filled ? 0.9 : 0.25),
              width: isToday ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: filled
              ? const Icon(Icons.check, size: 14, color: AppColors.wood)
              : Text(
                  '$day',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: active ? 0.9 : 0.4),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(height: 3),
        Text(
          reward >= 1000
              ? '${(reward / 1000).toStringAsFixed(reward % 1000 == 0 ? 0 : 1)}k'
              : '$reward',
          style: TextStyle(
            color: Colors.white.withValues(alpha: active ? 0.65 : 0.3),
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Background suit watermarks (deterministic positions seeded by hash).
// ─────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────
//  Top-3 weekly leaderboard preview — visible on the first page so the
//  player can see the current standings at a glance. Tap to open the full
//  leaderboard.
// ─────────────────────────────────────────────────────────────────────────

class _WeeklyTop3Card extends ConsumerWidget {
  const _WeeklyTop3Card();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(weeklyBoardProvider);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const LeaderboardScreen(),
        ));
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF301606), Color(0xFF1A0A02)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.1),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                CrownIcon(color: AppColors.gold, size: 18),
                const SizedBox(width: 8),
                Text(
                  'TOP THIS WEEK',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                _ResetCountdownChip(),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0),
                    AppColors.gold.withValues(alpha: 0.35),
                    AppColors.gold.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Top-3 rows
            boardAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ),
                ),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Leaderboard unavailable',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
              data: (board) {
                final entries = board.entries;
                // A real board starts empty and fills up, so show whatever is
                // there rather than hiding the card until three people exist.
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      board.isLive
                          ? 'Nobody has posted a score this week — the top '
                              'spot is open.'
                          : 'Play a hand to start your week.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                const crowns = [
                  AppColors.gold,
                  Color(0xFFB9C4CD),
                  Color(0xFFCD7F32),
                ];
                final top3 = entries.take(3).toList();
                final me = board.me;
                final onBoard = entries.any((e) => e.isCurrentUser);
                final myRank = me?.rank ?? 0;
                final gap = board.gapToNextRank;

                final String status;
                if (!onBoard || myRank == 0) {
                  status = 'Play a hand to join the board';
                } else if (myRank == 1) {
                  status = "You're #1 this week — hold it";
                } else if (gap != null && gap > 0) {
                  status = "You're #$myRank — \$$gap to move up";
                } else {
                  status = "You're #$myRank this week";
                }

                return Column(
                  children: [
                    for (var i = 0; i < top3.length; i++) ...[
                      if (i > 0) const SizedBox(height: 4),
                      _Top3Row(
                        rank: top3[i].rank,
                        crownColor: crowns[i],
                        entry: top3[i],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.gold.withValues(alpha: 0),
                            AppColors.gold.withValues(alpha: 0.35),
                            AppColors.gold.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            status,
                            style: TextStyle(
                              color: myRank == 1
                                  ? AppColors.gold
                                  : Colors.white.withValues(alpha: 0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Text(
                          'View full board',
                          style: TextStyle(
                            color: AppColors.gold.withValues(alpha: 0.85),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 11,
                          color: AppColors.gold.withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Top3Row extends StatelessWidget {
  final int rank;
  final Color crownColor;
  final LeaderboardEntry entry;

  const _Top3Row({
    required this.rank,
    required this.crownColor,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = entry.isCurrentUser;
    final profitColor = entry.profit > 0
        ? AppColors.favorable
        : entry.profit < 0
            ? AppColors.unfavorable
            : AppColors.neutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.gold.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isUser
            ? Border.all(color: AppColors.gold.withValues(alpha: 0.5))
            : null,
      ),
      child: Row(
        children: [
          CrownIcon(color: crownColor, size: 22),
          const SizedBox(width: 10),
          // Initial avatar
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isUser ? AppColors.gold : AppColors.surface,
              border: Border.all(
                color: crownColor.withValues(alpha: 0.7),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: isUser ? AppColors.wood : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name + (isUser ? '  ★' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isUser ? AppColors.gold : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            _formatProfit(entry.profit),
            style: TextStyle(
              color: profitColor,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  String _formatProfit(int v) {
    final sign = v >= 0 ? '+' : '−';
    final abs = v.abs();
    if (abs >= 1000) {
      final k = abs / 1000;
      return '$sign\$${k.toStringAsFixed(k.truncateToDouble() == k ? 0 : 1)}k';
    }
    return '$sign\$$abs';
  }
}

class _ResetCountdownChip extends StatefulWidget {
  @override
  State<_ResetCountdownChip> createState() => _ResetCountdownChipState();
}

class _ResetCountdownChipState extends State<_ResetCountdownChip> {
  late Duration _untilReset;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _untilReset = LeaderboardService.timeUntilReset();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _untilReset = LeaderboardService.timeUntilReset());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    if (d.isNegative) return 'Resetting…';
    final days = d.inDays;
    final hours = d.inHours % 24;
    if (days > 0) return '${days}d ${hours}h';
    final minutes = d.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule,
              color: AppColors.gold.withValues(alpha: 0.85), size: 11),
          const SizedBox(width: 4),
          Text(
            _format(_untilReset),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuitWatermarkPainter extends CustomPainter {
  static const _suits = ['♠', '♥', '♦', '♣'];

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(2026);
    for (var i = 0; i < 18; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final fontSize = 22 + rng.nextDouble() * 38;
      final suitIdx = rng.nextInt(4);
      final isRed = suitIdx == 1 || suitIdx == 2;
      final color = (isRed ? AppColors.hearts : Colors.white)
          .withValues(alpha: 0.025 + rng.nextDouble() * 0.025);

      final tp = TextPainter(
        text: TextSpan(
          text: _suits[suitIdx],
          style: TextStyle(color: color, fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_SuitWatermarkPainter old) => false;
}

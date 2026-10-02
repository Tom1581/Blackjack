import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_theme.dart';
import '../training/training_widgets.dart';
import 'daily_reminder.dart';
import 'hilo_boards_service.dart';
import 'widgets/hilo_button.dart';
import 'hilo_game.dart';
import 'hilo_game_screen.dart';
import 'hilo_scoring.dart';
import 'hilo_setup_screens.dart';
import 'hilo_text.dart';
import 'hilo_training_progress.dart';
import 'widgets/challenge_code_sheet.dart';
import 'widgets/hilo_badges.dart';
import 'widgets/hilo_boards_sheet.dart';

/// Hi-Lo Training: the hub. Your rank, today's Daily Challenge, Survival,
/// Duel, Practice, friend challenge codes, achievements and records.
///
/// Every mode is the same drill underneath — a dealer deals real rounds and,
/// at a card you cannot see coming, asks for the running count — dressed as
/// a game worth coming back to.
class HiLoTrainingScreen extends StatefulWidget {
  /// The clock, for tests.
  final DateTime Function() now;

  /// A friend's challenge from a link that opened the app: the code sheet
  /// opens on it.
  final HiLoChallenge? initialChallenge;

  const HiLoTrainingScreen({
    super.key,
    this.now = DateTime.now,
    this.initialChallenge,
  });

  @override
  State<HiLoTrainingScreen> createState() => _HiLoTrainingScreenState();
}

class _HiLoTrainingScreenState extends State<HiLoTrainingScreen> {
  HiLoProfile? _profile;
  HiLoDailyBoard? _dailyBoard;
  int? _dailyBoardDay;
  Timer? _minuteTimer;

  @override
  void initState() {
    super.initState();
    _reload();
    final linked = widget.initialChallenge;
    if (linked != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enterCode(initial: linked);
      });
    }
    // Keeps "next shoe in …" honest and rolls over at midnight.
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (_dailyBoardDay != _today) unawaited(_loadDailyBoard());
      setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final profile = await HiLoTrainingProgress.loadProfile();
    if (mounted) setState(() => _profile = profile);
    unawaited(_loadDailyBoard());
    // Every visit moves the one pending reminder to the next unplayed shoe.
    unawaited(DailyReminder.refresh());
  }

  Future<void> _loadDailyBoard() async {
    final day = _today;
    final board = await HiLoBoardsService.fetchDaily(day: day);
    if (!mounted || day != _today) return;
    setState(() {
      _dailyBoard = board;
      _dailyBoardDay = day;
    });
  }

  int get _today => HiLoDaily.numberFor(widget.now());

  Future<void> _open(Widget screen) async {
    HapticFeedback.lightImpact();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    await _reload();
  }

  void _playDaily() {
    final day = _today;
    final ranked = !(_profile?.playedDaily(day) ?? false);
    _open(HiLoGameScreen(spec: HiLoGameSpec.daily(day, ranked: ranked)));
  }

  void _openDailyBoard() {
    showHiLoDailyBoardSheet(context, day: _today);
  }

  void _openSurvivalBoard() {
    showHiLoSurvivalBoardSheet(context);
  }

  Future<void> _enterCode({HiLoChallenge? initial}) async {
    final challenge = await showChallengeCodeSheet(context, initial: initial);
    if (challenge == null || !mounted) return;
    await _open(HiLoGameScreen(spec: HiLoGameSpec.fromChallenge(challenge)));
  }

  Future<void> _shareDaily(BuildContext shareContext, int score) async {
    final box = shareContext.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await Share.share(
      dailyShareText(_today, score),
      subject: 'Beat my Hi-Lo Daily',
      sharePositionOrigin: origin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return TrainingScaffold(
      title: 'HI-LO TRAINING',
      child: profile == null
          ? const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.gold),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (profile.games == 0 && profile.duels == 0) ...[
                  const _NewHereCard(),
                  const SizedBox(height: 14),
                ],
                _RankCard(profile: profile),
                const SizedBox(height: 14),
                _DailyCard(
                  profile: profile,
                  day: _today,
                  now: widget.now(),
                  board: _dailyBoardDay == _today ? _dailyBoard : null,
                  onPlay: _playDaily,
                  onBoard: _openDailyBoard,
                  onShare: _shareDaily,
                ),
                const SizedBox(height: 8),
                const _ReminderRow(),
                const SizedBox(height: 14),
                _ModeTile(
                  key: const ValueKey('hilo-mode-survival'),
                  icon: Icons.favorite,
                  iconColor: AppColors.hearts,
                  title: 'Survival',
                  blurb: '3 lives. Every 5 right counts the dealer speeds up '
                      'and another player sits down.',
                  stat: profile.survivalBest > 0
                      ? 'BEST ${points(profile.survivalBest)} · '
                          'LEVEL ${profile.survivalBestLevel}'
                      : 'THIS WEEK',
                  onTap: () =>
                      _open(HiLoGameScreen(spec: HiLoGameSpec.survival())),
                  onBoard: _openSurvivalBoard,
                  boardTooltip: 'Weekly Survival leaderboard',
                ),
                _ModeTile(
                  key: const ValueKey('hilo-mode-duel'),
                  icon: Icons.people_alt,
                  iconColor: const Color(0xFF5AB0FF),
                  title: 'Duel',
                  blurb: 'Two players, one phone. Same cards, secret '
                      'answers, one winner.',
                  stat: profile.duels > 0
                      ? '${profile.duels} DUEL${profile.duels == 1 ? '' : 'S'} PLAYED'
                      : null,
                  onTap: () => _open(const HiLoDuelSetupScreen()),
                ),
                _ModeTile(
                  key: const ValueKey('hilo-mode-practice'),
                  icon: Icons.tune,
                  iconColor: AppColors.favorable,
                  title: 'Practice',
                  blurb: 'Choose the table and the pace. No clock on the '
                      'answers.',
                  stat: profile.practiceBest > 0
                      ? 'BEST ${points(profile.practiceBest)}'
                      : null,
                  onTap: () => _open(const HiLoPracticeSetupScreen()),
                ),
                const SizedBox(height: 4),
                _CodeRow(onTap: _enterCode),
                const SizedBox(height: 18),
                _AchievementsStrip(profile: profile),
                const SizedBox(height: 18),
                _RecordsCard(profile: profile, today: _today),
                const SizedBox(height: 18),
                const _ScoringCard(),
              ],
            ),
    );
  }
}

/// "Remind me": an opt-in nudge when the day's shoe is still unplayed.
class _ReminderRow extends StatefulWidget {
  const _ReminderRow();

  @override
  State<_ReminderRow> createState() => _ReminderRowState();
}

class _ReminderRowState extends State<_ReminderRow> {
  bool? _on;
  int _hour = DailyReminder.defaultHour;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    DailyReminder.load().then((s) {
      if (mounted) {
        setState(() {
          _on = s.on;
          _hour = s.hour;
        });
      }
    });
  }

  Future<void> _toggle(bool on) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    var allowed = true;
    try {
      if (on) {
        allowed = await DailyReminder.enable(_hour);
      } else {
        await DailyReminder.disable();
      }
    } catch (error) {
      debugPrint('Daily reminder: $error');
      allowed = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _on = on && allowed;
    });
    if (on && !allowed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Notifications are off for this app. Allow them in '
            'your phone\'s settings to get the reminder.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _setHour(int hour) async {
    HapticFeedback.selectionClick();
    setState(() => _hour = hour);
    await DailyReminder.setHour(hour);
  }

  @override
  Widget build(BuildContext context) {
    final on = _on;
    if (on == null) return const SizedBox(height: 48);
    return Container(
      key: const ValueKey('hilo-reminder'),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                on
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
                size: 18,
                color: AppColors.gold.withValues(alpha: on ? 1 : 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  on
                      ? 'Reminder at ${DailyReminder.hourLabel(_hour)} if '
                          'the day\'s shoe is unplayed'
                      : 'Remind me about the Daily',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                key: const ValueKey('hilo-reminder-switch'),
                value: on,
                onChanged: _busy ? null : _toggle,
              ),
            ],
          ),
          if (on)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final h in DailyReminder.hours)
                    ChoiceChip(
                      label: Text(DailyReminder.hourLabel(h)),
                      selected: h == _hour,
                      onSelected: (_) => _setHour(h),
                      selectedColor: AppColors.gold,
                      labelStyle: TextStyle(
                        color: h == _hour ? AppColors.wood : Colors.white70,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                      backgroundColor: Colors.black.withValues(alpha: 0.25),
                      side: BorderSide(
                          color: AppColors.gold.withValues(alpha: 0.35)),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// For someone who has never played: the three tags and where to start.
class _NewHereCard extends StatelessWidget {
  const _NewHereCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('hilo-new-here'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.favorable.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.favorable.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'NEW TO COUNTING?',
            style: TextStyle(
              color: AppColors.favorable,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          const HiLoTagLegend(),
          const SizedBox(height: 10),
          Text(
            'Add each card\'s tag as it lands and keep the total in your '
            'head. The dealer\'s face-down card waits until it is turned '
            'over. Start in Practice at a Relaxed pace, then take on the '
            'Daily.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  final HiLoProfile profile;

  const _RankCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final rank = profile.rank;
    final next = rank.next;
    final color = rankColor(rank);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.16), AppColors.surface],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          RankEmblem(rank: rank),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR RANK',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  rank.title,
                  key: const ValueKey('hilo-rank'),
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                HiLoProgressBar(
                    progress: rank.progress(profile.xp), color: color),
                const SizedBox(height: 4),
                Text(
                  next == null
                      ? '${points(profile.xp)} XP · the top rank'
                      : '${points(profile.xp)} XP · ${points(next.xp - profile.xp)} to ${next.title}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (profile.questions > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${profile.accuracy}% right · best streak '
                    '${profile.bestStreak} · ${profile.games} games',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  final HiLoProfile profile;
  final int day;
  final DateTime now;
  final HiLoDailyBoard? board;
  final VoidCallback onPlay;
  final VoidCallback onBoard;
  final Future<void> Function(BuildContext, int) onShare;

  const _DailyCard({
    required this.profile,
    required this.day,
    required this.now,
    required this.board,
    required this.onPlay,
    required this.onBoard,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final played = profile.playedDaily(day);
    final score = profile.dailyScores[day] ?? 0;
    final streak = profile.dailyStreakOn(day);
    final config = HiLoDaily.configFor(day);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A2606), Color(0xFF1C1204)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: played ? 0.35 : 0.7),
          width: played ? 1 : 1.5,
        ),
        boxShadow: played
            ? null
            : [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.2),
                  blurRadius: 20,
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.today, color: AppColors.gold, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'DAILY CHALLENGE #$day',
                  style: const TextStyle(
                    color: AppColors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              if (streak > 0)
                Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        color: Color(0xFFFF7A59), size: 16),
                    Text(
                      '$streak',
                      style: const TextStyle(
                        color: Color(0xFFFF7A59),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Everyone gets the same shoe today: ${tableLabel(config)}. '
            '${HiLoDaily.questions} counts, 15 seconds each.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          if (!played)
            HiLoButton(
              key: const ValueKey('hilo-daily-play'),
              label: 'PLAY TODAY\'S SHOE',
              icon: Icons.play_arrow_rounded,
              onPressed: onPlay,
            )
          else ...[
            Row(
              children: [
                Text(
                  'TODAY  ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  '${points(score)} pts',
                  key: const ValueKey('hilo-daily-score'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (shareContext) => HiLoButton(
                      label: 'SHARE',
                      icon: Icons.ios_share,
                      onPressed: () => onShare(shareContext, score),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HiLoButton(
                    key: const ValueKey('hilo-daily-replay'),
                    label: 'REPLAY',
                    outlined: true,
                    onPressed: onPlay,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  board?.isLive == true && board?.standing != null
                      ? '#${board!.standing!.rank} OF '
                          '${board!.standing!.players} TODAY'
                      : board?.status == HiLoBoardStatus.notConfigured
                          ? 'RANKINGS ARE BEING SET UP'
                          : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: 0.86),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('hilo-daily-board'),
                onPressed: onBoard,
                icon: const Icon(Icons.leaderboard_outlined, size: 17),
                label: const Text('TOP 100'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            played
                ? 'Next shoe in ${countdown(HiLoDaily.untilNext(now))} · '
                    'replays are practice'
                : 'One ranked try a day — it counts from the first card.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String blurb;
  final String? stat;
  final VoidCallback onTap;
  final VoidCallback? onBoard;
  final String? boardTooltip;

  const _ModeTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.blurb,
    required this.onTap,
    this.stat,
    this.onBoard,
    this.boardTooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: iconColor.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withValues(alpha: 0.14),
                    border: Border.all(color: iconColor.withValues(alpha: 0.6)),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        blurb,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      if (stat != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          stat!,
                          style: TextStyle(
                            color: iconColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onBoard != null)
                  IconButton(
                    key: const ValueKey('hilo-survival-board'),
                    tooltip: boardTooltip,
                    onPressed: onBoard,
                    visualDensity: VisualDensity.compact,
                    color: iconColor,
                    icon: const Icon(Icons.leaderboard_outlined, size: 21),
                  ),
                const Icon(Icons.chevron_right, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final VoidCallback onTap;

  const _CodeRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const ValueKey('hilo-enter-code'),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: Colors.black.withValues(alpha: 0.2),
        side: BorderSide(color: AppColors.gold.withValues(alpha: 0.45)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 20),
          SizedBox(width: 8),
          Flexible(
            child: Text(
              'ENTER A FRIEND\'S CODE',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementsStrip extends StatelessWidget {
  final HiLoProfile profile;

  const _AchievementsStrip({required this.profile});

  @override
  Widget build(BuildContext context) {
    final got = profile.achievements;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showAchievementsSheet(context, got),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ACHIEVEMENTS  ${got.length}/${HiLoAchievement.values.length}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Text(
                  'SEE ALL',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 16, color: Colors.white.withValues(alpha: 0.55)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in HiLoAchievement.values)
                  AchievementBadge(
                    achievement: a,
                    unlocked: got.contains(a),
                    size: 34,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordsCard extends StatelessWidget {
  final HiLoProfile profile;
  final int today;

  const _RecordsCard({required this.profile, required this.today});

  @override
  Widget build(BuildContext context) {
    final header = TextStyle(
      color: Colors.white.withValues(alpha: 0.5),
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.8,
    );
    // The last seven days, but never before Daily #1.
    final week = [
      for (var d = today - 6; d <= today; d++)
        if (d >= 1) d,
    ];
    final weekScores = [for (final d in week) profile.dailyScores[d]];
    final peak = weekScores.whereType<int>().fold(1, max);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RECORDS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 12),
          Text('SURVIVAL — TOP RUNS', style: header),
          const SizedBox(height: 6),
          if (profile.survivalTop.isEmpty)
            Text(
              'No runs yet. How long can you keep the count?',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            )
          else
            for (var i = 0; i < profile.survivalTop.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '#${i + 1}',
                        style: TextStyle(
                          color: i == 0 ? AppColors.gold : Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      points(profile.survivalTop[i]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          Text('DAILY — THIS WEEK', style: header),
          const SizedBox(height: 8),
          SizedBox(
            height: 74,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < week.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DayBar(
                        label: '#${week[i]}',
                        score: weekScores[i],
                        fraction: (weekScores[i] ?? 0) / peak,
                        today: week[i] == today,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (profile.commonSlip case final slip?) ...[
            const SizedBox(height: 14),
            Text('YOUR MOST COMMON MISS', style: header),
            const SizedBox(height: 4),
            Text(
              '${slipName(slip)} · ${profile.slips[slip]}×',
              key: const ValueKey('hilo-common-slip'),
              style: const TextStyle(
                color: AppColors.unfavorable,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (profile.trueCountsAsked > 0)
            Text(
              'True counts ${profile.trueCountsRight}/'
              '${profile.trueCountsAsked} right',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11.5,
              ),
            ),
          Text(
            'Best daily ${points(profile.dailyBest)} · '
            '${profile.challengesWon} challenge${profile.challengesWon == 1 ? '' : 's'} won',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final String label;
  final int? score;
  final double fraction;
  final bool today;

  const _DayBar({
    required this.label,
    required this.score,
    required this.fraction,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final played = score != null;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: played ? max(0.06, fraction) : 0.06,
              child: Container(
                decoration: BoxDecoration(
                  color: played
                      ? (today ? AppColors.goldLight : AppColors.gold)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            color: today ? AppColors.gold : Colors.white38,
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ScoringCard extends StatelessWidget {
  const _ScoringCard();

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(
      color: Colors.white.withValues(alpha: 0.65),
      fontSize: 12,
      height: 1.5,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOW SCORING WORKS',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${HiLoScoring.base} for a right count, plus up to '
            '${HiLoScoring.maxSpeedBonus} for answering within '
            '${HiLoScoring.fullSpeedWithin.inSeconds} seconds. Right answers '
            'in a row multiply it: ×2 from the 3rd, ×3 from the 6th, ×4 from '
            'the 10th. One wrong count and the combo starts again.',
            style: body,
          ),
          const SizedBox(height: 6),
          Text(
            'Every 10 points is 1 XP toward your rank. The dealer\'s '
            'face-down card never counts until it is turned over.',
            style: body,
          ),
        ],
      ),
    );
  }
}

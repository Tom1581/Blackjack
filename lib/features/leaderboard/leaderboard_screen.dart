import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../profile/player_identity.dart';
import 'leaderboard_providers.dart';
import 'leaderboard_service.dart';
import 'weekly_board_service.dart';
import 'widgets/crown_icon.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  Timer? _ticker;
  Duration _untilReset = Duration.zero;

  /// Profit league or accuracy league.
  bool _accuracy = false;

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

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref
        .watch(_accuracy ? weeklyAccuracyBoardProvider : weeklyBoardProvider);
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(untilReset: _untilReset, accuracy: _accuracy),
        _MetricToggle(
          accuracy: _accuracy,
          onChanged: (v) => setState(() => _accuracy = v),
        ),
      ],
    );
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF061410), Color(0xFF0B2116), Color(0xFF0A1E12)],
          ),
        ),
        child: SafeArea(
          child: boardAsync.when(
            loading: () => Column(
              children: [
                header,
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(AppColors.gold),
                    ),
                  ),
                ),
              ],
            ),
            error: (e, _) => Center(
              child: Text('$e', style: const TextStyle(color: Colors.white70)),
            ),
            data: (board) {
              final entries = board.entries;
              if (entries.isEmpty) {
                return Column(
                  children: [
                    header,
                    if (!board.isLive) _BoardNotice(status: board.status),
                    Expanded(
                      child: _EmptyBoard(
                          status: board.status, accuracy: _accuracy),
                    ),
                    if (_accuracy &&
                        board.me != null &&
                        board.me!.decisions > 0)
                      _UserPinnedRow(rank: 0, entry: board.me!, accuracy: true),
                  ],
                );
              }

              final userIndex = entries.indexWhere((e) => e.isCurrentUser);
              final me = board.me;
              final top3 = entries.take(3).toList();
              final rest = entries.skip(3).toList();
              final gap = board.gapToNextRank;

              return Column(
                children: [
                  header,
                  if (!board.isLive) _BoardNotice(status: board.status),
                  if (!_accuracy && gap != null && gap > 0)
                    _ChaseBanner(gap: gap),
                  const SizedBox(height: 4),
                  _Podium(entries: top3, accuracy: _accuracy),
                  const SizedBox(height: 16),
                  _SectionLabel(
                    label: _accuracy
                        ? '${board.playerCount} PLAYER'
                            '${board.playerCount == 1 ? '' : 'S'} · '
                            '${WeeklyBoardService.minAccuracyDecisions}+ '
                            'DECISIONS'
                        : board.playerCount == 1
                            ? 'THIS WEEK'
                            : '${board.playerCount} PLAYERS THIS WEEK',
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: rest.isEmpty
                        ? const SizedBox.shrink()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            itemCount: rest.length,
                            itemBuilder: (_, i) => _RankRow(
                              rank: rest[i].rank,
                              entry: rest[i],
                              accuracy: _accuracy,
                            ),
                          ),
                  ),
                  // Pin the player when they are nowhere on the visible board.
                  if (userIndex < 0 &&
                      me != null &&
                      (_accuracy ? me.decisions > 0 : me.handsPlayed > 0))
                    _UserPinnedRow(
                        rank: me.rank, entry: me, accuracy: _accuracy),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Shown when the shared board could not be reached. The player still sees
/// their own week, so this explains the missing competition rather than
/// pretending there is none.
class _BoardNotice extends StatelessWidget {
  final BoardStatus status;
  const _BoardNotice({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off,
              size: 15, color: AppColors.gold.withValues(alpha: 0.8)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              status == BoardStatus.offline
                  ? "Can't reach the rankings — showing your week only."
                  : 'Rankings are being set up. Your score is saved and will '
                      'appear once they are live.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The number that actually makes someone play one more round.
class _ChaseBanner extends StatelessWidget {
  final int gap;
  const _ChaseBanner({required this.gap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.gold.withValues(alpha: 0.22),
            AppColors.gold.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.trending_up, size: 17, color: AppColors.gold),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: '\$$gap',
                    style: TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const TextSpan(text: ' to pass the player above you'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Profit | Accuracy.
class _MetricToggle extends StatelessWidget {
  final bool accuracy;
  final ValueChanged<bool> onChanged;

  const _MetricToggle({required this.accuracy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) {
      final selected = accuracy == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.gold : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.wood : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [tab('PROFIT', false), tab('ACCURACY', true)],
      ),
    );
  }
}

/// Nobody has a score yet this week — including you.
class _EmptyBoard extends StatelessWidget {
  final BoardStatus status;
  final bool accuracy;
  const _EmptyBoard({required this.status, this.accuracy = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CrownIcon(color: AppColors.gold.withValues(alpha: 0.8), size: 40),
            const SizedBox(height: 18),
            Text(
              accuracy
                  ? 'Nobody has qualified yet'
                  : status == BoardStatus.live
                      ? 'The board is wide open'
                      : 'No score yet this week',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              accuracy
                  ? 'Make ${WeeklyBoardService.minAccuracyDecisions} decisions '
                      'at the table this week — every hit, stand, double, '
                      'split and surrender the coach grades — to join the '
                      'accuracy league.'
                  : status == BoardStatus.live
                      ? 'Nobody has posted a score this week. Play a few hands '
                          'and the top spot is yours.'
                      : 'Play a few hands and your weekly profit shows up '
                          'here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Duration untilReset;
  final bool accuracy;
  const _Header({required this.untilReset, this.accuracy = false});

  String _format(Duration d) {
    if (d.isNegative) return 'Resetting…';
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.gold),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'WEEKLY LEADERBOARD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  accuracy
                      ? 'Best decisions this week'
                      : 'Top earners this week',
                  style: const TextStyle(
                    color: AppColors.neutral,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Countdown pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.wood,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, color: AppColors.gold, size: 14),
                const SizedBox(width: 6),
                Text(
                  _format(untilReset),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final bool accuracy;
  const _Podium({required this.entries, this.accuracy = false});

  @override
  Widget build(BuildContext context) {
    if (entries.length < 3) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: _PodiumColumn(
              rank: 2,
              entry: entries[1],
              accuracy: accuracy,
              crownColor: const Color(0xFFB9C4CD), // silver
              height: 130,
            ),
          ),
          Expanded(
            child: _PodiumColumn(
              rank: 1,
              entry: entries[0],
              accuracy: accuracy,
              crownColor: AppColors.gold,
              height: 165,
            ),
          ),
          Expanded(
            child: _PodiumColumn(
              rank: 3,
              entry: entries[2],
              accuracy: accuracy,
              crownColor: const Color(0xFFCD7F32), // copper
              height: 110,
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final Color crownColor;
  final double height;
  final bool accuracy;

  const _PodiumColumn({
    required this.rank,
    required this.entry,
    required this.crownColor,
    required this.height,
    this.accuracy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = entry.isCurrentUser;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CrownIcon(color: crownColor, size: rank == 1 ? 36 : 28),
        const SizedBox(height: 6),
        // The player's own avatar, in its crown's glow.
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: crownColor.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: PlayerAvatar(
            name: entry.name,
            size: rank == 1 ? 54 : 46,
            isMe: isUser,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isUser ? AppColors.gold : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _metricText(entry, accuracy),
          style: TextStyle(
            color: _metricColor(entry, accuracy),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        // Pedestal
        Container(
          width: double.infinity,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                crownColor.withValues(alpha: 0.7),
                crownColor.withValues(alpha: 0.25),
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: Border.all(color: crownColor.withValues(alpha: 0.6)),
          ),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '$rank',
              style: TextStyle(
                color: Colors.white,
                fontSize: rank == 1 ? 32 : 26,
                fontWeight: FontWeight.w900,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0),
                    AppColors.gold.withValues(alpha: 0.4),
                  ],
                ),
              ),
            ),
          ),
          // The label wins over the rules either side; on a narrow phone it
          // scales down rather than overflowing.
          Flexible(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: 0.7),
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gold.withValues(alpha: 0.4),
                    AppColors.gold.withValues(alpha: 0),
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

class _RankRow extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool accuracy;
  const _RankRow({
    required this.rank,
    required this.entry,
    this.accuracy = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = entry.isCurrentUser;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.gold.withValues(alpha: 0.18)
            : AppColors.wood.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUser
              ? AppColors.gold.withValues(alpha: 0.6)
              : AppColors.gold.withValues(alpha: 0.1),
          width: isUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              // Rank 0 means "played, but outside the fetched board".
              rank > 0 ? '$rank' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isUser ? AppColors.gold : Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          PlayerAvatar(name: entry.name, size: 28, isMe: isUser),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isUser ? AppColors.gold : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isUser) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: AppColors.gold, size: 14),
                ],
              ],
            ),
          ),
          if (accuracy)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${entry.decisions}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            _metricText(entry, accuracy),
            style: TextStyle(
              color: _metricColor(entry, accuracy),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _UserPinnedRow extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool accuracy;
  const _UserPinnedRow({
    required this.rank,
    required this.entry,
    this.accuracy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withValues(alpha: 0.25),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // Subtle "your rank" tab
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: const Text(
              'YOUR RANK',
              style: TextStyle(
                color: AppColors.wood,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
          _RankRow(rank: rank, entry: entry, accuracy: accuracy),
        ],
      ),
    );
  }
}

/// The number a row is ranked on: profit, or accuracy.
String _metricText(LeaderboardEntry e, bool accuracy) =>
    accuracy ? '${e.accuracyPercent}%' : _formatProfit(e.profit);

Color _metricColor(LeaderboardEntry e, bool accuracy) {
  if (!accuracy) return _profitColor(e.profit);
  final pct = e.accuracyPercent;
  if (pct >= 95) return AppColors.favorable;
  if (pct >= 85) return AppColors.gold;
  return AppColors.unfavorable;
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

Color _profitColor(int v) {
  if (v > 0) return AppColors.favorable;
  if (v < 0) return AppColors.unfavorable;
  return AppColors.neutral;
}

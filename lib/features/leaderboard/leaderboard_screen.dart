import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import 'leaderboard_providers.dart';
import 'leaderboard_service.dart';
import 'widgets/crown_icon.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  Timer? _ticker;
  Duration _untilReset = Duration.zero;

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
    final boardAsync = ref.watch(weeklyBoardProvider);
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
            loading: () => const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.gold),
              ),
            ),
            error: (e, _) => Center(
              child: Text('$e',
                  style: const TextStyle(color: Colors.white70)),
            ),
            data: (entries) {
              final userIndex =
                  entries.indexWhere((e) => e.isCurrentUser);
              final top3 = entries.take(3).toList();
              final next7 = entries.skip(3).take(7).toList();
              final userInTop10 = userIndex >= 0 && userIndex < 10;
              final userEntry = entries[userIndex];

              return Column(
                children: [
                  _Header(untilReset: _untilReset),
                  const SizedBox(height: 4),
                  _Podium(entries: top3),
                  const SizedBox(height: 16),
                  _SectionLabel(label: 'TOP 10'),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: next7.length,
                      itemBuilder: (_, i) {
                        final rank = i + 4;
                        final e = next7[i];
                        return _RankRow(rank: rank, entry: e);
                      },
                    ),
                  ),
                  if (!userInTop10)
                    _UserPinnedRow(
                      rank: userIndex + 1,
                      entry: userEntry,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Duration untilReset;
  const _Header({required this.untilReset});

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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WEEKLY LEADERBOARD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Top earners this week',
                  style: TextStyle(
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
  const _Podium({required this.entries});

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
              crownColor: const Color(0xFFB9C4CD), // silver
              height: 130,
            ),
          ),
          Expanded(
            child: _PodiumColumn(
              rank: 1,
              entry: entries[0],
              crownColor: AppColors.gold,
              height: 165,
            ),
          ),
          Expanded(
            child: _PodiumColumn(
              rank: 3,
              entry: entries[2],
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

  const _PodiumColumn({
    required this.rank,
    required this.entry,
    required this.crownColor,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = entry.isCurrentUser;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CrownIcon(color: crownColor, size: rank == 1 ? 36 : 28),
        const SizedBox(height: 6),
        // Avatar circle
        Container(
          width: rank == 1 ? 54 : 46,
          height: rank == 1 ? 54 : 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isUser ? AppColors.gold : AppColors.wood,
            border: Border.all(color: crownColor, width: 2),
            boxShadow: [
              BoxShadow(
                color: crownColor.withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            entry.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: isUser ? AppColors.wood : Colors.white,
              fontSize: rank == 1 ? 22 : 18,
              fontWeight: FontWeight.w900,
            ),
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
          _formatProfit(entry.profit),
          style: TextStyle(
            color: _profitColor(entry.profit),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
  const _RankRow({required this.rank, required this.entry});

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
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isUser ? AppColors.gold : Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Initial avatar
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isUser ? AppColors.gold : AppColors.surface,
            ),
            alignment: Alignment.center,
            child: Text(
              entry.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: isUser ? AppColors.wood : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Text(
                  entry.name,
                  style: TextStyle(
                    color: isUser ? AppColors.gold : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isUser) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: AppColors.gold, size: 14),
                ],
              ],
            ),
          ),
          Text(
            _formatProfit(entry.profit),
            style: TextStyle(
              color: _profitColor(entry.profit),
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
  const _UserPinnedRow({required this.rank, required this.entry});

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
          _RankRow(rank: rank, entry: entry),
        ],
      ),
    );
  }
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

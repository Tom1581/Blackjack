import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../profile/player_identity.dart';
import '../hilo_boards_service.dart';
import '../hilo_text.dart';

Future<void> showHiLoDailyBoardSheet(
  BuildContext context, {
  required int day,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DailyBoardSheet(day: day),
  );
}

Future<void> showHiLoSurvivalBoardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _SurvivalBoardSheet(),
  );
}

class _DailyBoardSheet extends StatefulWidget {
  final int day;

  const _DailyBoardSheet({required this.day});

  @override
  State<_DailyBoardSheet> createState() => _DailyBoardSheetState();
}

class _DailyBoardSheetState extends State<_DailyBoardSheet> {
  late Future<HiLoDailyBoard> _board;

  @override
  void initState() {
    super.initState();
    _board = HiLoBoardsService.fetchDaily(day: widget.day);
  }

  void _refresh() {
    setState(() => _board = HiLoBoardsService.fetchDaily(day: widget.day));
  }

  @override
  Widget build(BuildContext context) {
    return _BoardSheetFrame(
      title: 'TODAY\'S TOP 100',
      subtitle: 'DAILY CHALLENGE #${widget.day}',
      refreshKey: 'hilo-daily-board-refresh',
      onRefresh: _refresh,
      child: FutureBuilder<HiLoDailyBoard>(
        future: _board,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _BoardLoading();
          final board = snapshot.requireData;
          return _BoardBody(
            status: board.status,
            entries: board.entries,
            metric: (entry) => '${points(entry.score)} pts',
            footer: board.standing == null
                ? null
                : '#${board.standing!.rank} OF ${board.standing!.players} TODAY',
          );
        },
      ),
    );
  }
}

class _SurvivalBoardSheet extends StatefulWidget {
  const _SurvivalBoardSheet();

  @override
  State<_SurvivalBoardSheet> createState() => _SurvivalBoardSheetState();
}

class _SurvivalBoardSheetState extends State<_SurvivalBoardSheet> {
  late Future<HiLoSurvivalBoard> _board;

  @override
  void initState() {
    super.initState();
    _board = HiLoBoardsService.fetchSurvival();
  }

  void _refresh() {
    setState(() => _board = HiLoBoardsService.fetchSurvival());
  }

  @override
  Widget build(BuildContext context) {
    return _BoardSheetFrame(
      title: 'SURVIVAL',
      subtitle: 'THIS WEEK',
      refreshKey: 'hilo-survival-board-refresh',
      onRefresh: _refresh,
      child: FutureBuilder<HiLoSurvivalBoard>(
        future: _board,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const _BoardLoading();
          final board = snapshot.requireData;
          return _BoardBody(
            status: board.status,
            entries: board.entries,
            metric: (entry) => entry.level == null
                ? '${points(entry.score)} pts'
                : '${points(entry.score)} pts · LV ${entry.level}',
          );
        },
      ),
    );
  }
}

class _BoardSheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final String refreshKey;
  final VoidCallback onRefresh;
  final Widget child;

  const _BoardSheetFrame({
    required this.title,
    required this.subtitle,
    required this.refreshKey,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.94,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.gold,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey(refreshKey),
                  tooltip: 'Refresh rankings',
                  onPressed: onRefresh,
                  color: AppColors.gold,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [child],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardLoading extends StatelessWidget {
  const _BoardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.gold),
    );
  }
}

class _BoardBody extends StatelessWidget {
  final HiLoBoardStatus status;
  final List<HiLoBoardEntry> entries;
  final String Function(HiLoBoardEntry) metric;
  final String? footer;

  const _BoardBody({
    required this.status,
    required this.entries,
    required this.metric,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    if (status != HiLoBoardStatus.live) {
      final setup = status == HiLoBoardStatus.notConfigured;
      return Padding(
        padding: const EdgeInsets.only(top: 46),
        child: Column(
          children: [
            Icon(
              setup ? Icons.hourglass_top_outlined : Icons.cloud_off_outlined,
              color: AppColors.gold.withValues(alpha: 0.78),
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              setup ? 'RANKINGS ARE BEING SET UP' : 'CAN\'T REACH RANKINGS',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
    }
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 46),
        child: Center(
          child: Text(
            'NO SCORES YET',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final entry in entries) _RankRow(entry: entry, metric: metric),
        if (footer != null) ...[
          const SizedBox(height: 12),
          Text(
            footer!,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  final HiLoBoardEntry entry;
  final String Function(HiLoBoardEntry) metric;

  const _RankRow({required this.entry, required this.metric});

  @override
  Widget build(BuildContext context) {
    final current = entry.isCurrentUser;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: current
            ? AppColors.gold.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: current
              ? AppColors.gold.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#${entry.rank}',
              style: TextStyle(
                color: current ? AppColors.gold : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          PlayerAvatar(name: entry.name, size: 26, isMe: current),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: current ? AppColors.gold : Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            metric(entry),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

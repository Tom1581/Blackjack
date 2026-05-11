import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';

// Simple in-memory session stats (persisted via shared_preferences in production)
final _statsProvider = FutureProvider<_SessionStats>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return _SessionStats(
    handsPlayed: prefs.getInt('hands_played') ?? 0,
    wins: prefs.getInt('wins') ?? 0,
    losses: prefs.getInt('losses') ?? 0,
    pushes: prefs.getInt('pushes') ?? 0,
    blackjacks: prefs.getInt('blackjacks') ?? 0,
    startBankroll: prefs.getInt('start_bankroll') ?? 1000,
    currentBankroll: prefs.getInt('bankroll') ?? 1000,
    countHistory: (prefs.getStringList('count_history') ?? [])
        .map(int.parse)
        .toList(),
  );
});

class _SessionStats {
  final int handsPlayed;
  final int wins;
  final int losses;
  final int pushes;
  final int blackjacks;
  final int startBankroll;
  final int currentBankroll;
  final List<int> countHistory;

  const _SessionStats({
    required this.handsPlayed,
    required this.wins,
    required this.losses,
    required this.pushes,
    required this.blackjacks,
    required this.startBankroll,
    required this.currentBankroll,
    required this.countHistory,
  });

  double get winRate => handsPlayed > 0 ? wins / handsPlayed : 0;
  int get netProfit => currentBankroll - startBankroll;
}

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_statsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'STATS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        centerTitle: true,
      ),
      body: statsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) =>
            Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
        data: (stats) => _StatsBody(stats: stats),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final _SessionStats stats;

  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final profit = stats.netProfit;
    final profitColor = profit >= 0 ? AppColors.favorable : AppColors.unfavorable;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profit/Loss banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: profitColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: profitColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Text(
                  profit >= 0 ? 'SESSION PROFIT' : 'SESSION LOSS',
                  style: TextStyle(
                    color: profitColor.withValues(alpha: 0.8),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${profit >= 0 ? '+' : ''}\$$profit',
                  style: TextStyle(
                    color: profitColor,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '\$${stats.startBankroll} → \$${stats.currentBankroll}',
                  style: const TextStyle(color: AppColors.neutral, fontSize: 13),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionTitle('HAND RESULTS'),
          const SizedBox(height: 12),

          // Stats grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2,
            children: [
              _statTile('Hands Played', '${stats.handsPlayed}', Colors.white),
              _statTile('Win Rate',
                  '${(stats.winRate * 100).toStringAsFixed(1)}%',
                  AppColors.favorable),
              _statTile('Wins', '${stats.wins}', AppColors.favorable),
              _statTile('Losses', '${stats.losses}', AppColors.unfavorable),
              _statTile('Pushes', '${stats.pushes}', AppColors.neutral),
              _statTile('Blackjacks', '${stats.blackjacks}',
                  const Color(0xFFfbbf24)),
            ],
          ),

          const SizedBox(height: 28),
          _sectionTitle('HI-LO COUNT HISTORY'),
          const SizedBox(height: 12),

          if (stats.countHistory.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No hands played yet.\nPlay some hands to see your count history.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.neutral),
                ),
              ),
            )
          else
            _CountChart(history: stats.countHistory),

          const SizedBox(height: 12),
          _sectionTitle('WHAT THE COUNT MEANS'),
          const SizedBox(height: 12),
          _legendCard(),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: AppColors.neutral,
          fontSize: 11,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _statTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.neutral, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendRow('True Count ≥ +2', 'FAVORABLE — Increase your bet',
              AppColors.favorable),
          const SizedBox(height: 8),
          _legendRow('True Count −1 to +1', 'NEUTRAL — Bet normally',
              AppColors.neutral),
          const SizedBox(height: 8),
          _legendRow('True Count ≤ −1', 'UNFAVORABLE — Reduce your bet',
              AppColors.unfavorable),
          const Divider(color: Colors.white10, height: 20),
          const Text(
            'Low cards (2–6) → +1  •  High cards (10,J,Q,K,A) → −1  •  Neutral (7–9) → 0',
            style: TextStyle(color: AppColors.neutral, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(String count, String meaning, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(count,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            Text(meaning,
                style: const TextStyle(color: AppColors.neutral, fontSize: 11)),
          ],
        ),
      ],
    );
  }
}

/// Simple sparkline chart for count history
class _CountChart extends StatelessWidget {
  final List<int> history;

  const _CountChart({required this.history});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: CustomPaint(
        painter: _SparklinePainter(history),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<int> data;

  _SparklinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final min = data.reduce((a, b) => a < b ? a : b).toDouble();
    final max = data.reduce((a, b) => a > b ? a : b).toDouble();
    final range = (max - min).abs();
    if (range == 0) return;

    final zeroY = size.height - ((0 - min) / range) * size.height;

    // Zero line
    final zeroPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);

    // Sparkline
    final linePaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = size.height - ((data[i] - min) / range) * size.height;
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, linePaint);

    // Dot at end
    final last = data.last;
    final lastX = size.width;
    final lastY = size.height - ((last - min) / range) * size.height;
    final color = last >= 2
        ? AppColors.favorable
        : last <= -1
            ? AppColors.unfavorable
            : AppColors.neutral;
    canvas.drawCircle(
        Offset(lastX, lastY), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.data != data;
}

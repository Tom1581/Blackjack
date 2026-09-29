import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../drill/daily_count_drill_screen.dart';
import '../strategy/strategy_chart_screen.dart';
import '../table/table_provider.dart';
import 'index_drill_screen.dart';
import 'speed_count_screen.dart';
import 'strategy_drill_screen.dart';
import 'true_count_drill_screen.dart';

/// Every drill in one place, in the order a counter learns them: the chart,
/// then card values, then keeping a running count, then converting it.
class TrainingCenterScreen extends StatelessWidget {
  const TrainingCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) {
      HapticFeedback.lightImpact();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'TRAINING CENTER',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            Text(
              'Work down the list. Each step is what the next one is built on.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            _StepTile(
              step: 1,
              icon: Icons.fact_check_outlined,
              title: 'Strategy Drill',
              blurb: 'Hard, soft and pair hands with instant feedback — or '
                  'just the ones you keep missing.',
              onTap: () => open(const StrategyDrillScreen()),
            ),
            _StepTile(
              label: 'REFERENCE',
              icon: Icons.grid_on_rounded,
              title: 'Strategy Chart',
              blurb: 'The exact chart the coach grades you on, for your '
                  'table rules.',
              onTap: () => open(const StrategyChartScreen()),
            ),
            _StepTile(
              step: 2,
              icon: Icons.timer_outlined,
              title: 'Daily Count Drill',
              blurb: 'Tag 20 cards +1, 0 or −1 against the clock. A new set '
                  'every day.',
              onTap: () => open(const DailyCountDrillScreen()),
            ),
            _StepTile(
              step: 3,
              icon: Icons.bolt_outlined,
              title: 'Speed Count',
              blurb: 'Cards flash by at table pace; keep the running count '
                  'in your head. Includes the classic deck countdown.',
              onTap: () => open(const SpeedCountScreen()),
            ),
            _StepTile(
              step: 4,
              icon: Icons.calculate_outlined,
              title: 'True Count',
              blurb: 'Divide the running count by the decks left in the '
                  'shoe — the number your bet is sized on.',
              onTap: () => open(const TrueCountDrillScreen()),
            ),
            _StepTile(
              step: 5,
              icon: Icons.insights_outlined,
              title: 'Index Plays',
              blurb: 'The Illustrious 18 and Fab 4: when the true count says '
                  'to break the chart, and by how much.',
              onTap: () => open(const IndexDrillScreen()),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Text(
                'Step 6 is the table itself: in Table Settings turn the '
                'count HUD off (the dealer quizzes your running count every '
                '$countCheckEvery hands), and turn on index plays and the bet '
                'spread coach.',
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.9),
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int? step;

  /// Shown instead of "STEP n" for a tile that is not a step.
  final String? label;
  final IconData icon;
  final String title;
  final String blurb;
  final VoidCallback onTap;

  const _StepTile({
    this.step,
    this.label,
    required this.icon,
    required this.title,
    required this.blurb,
    required this.onTap,
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.gold.withValues(alpha: 0.12),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.5)),
                  ),
                  child: Icon(icon, color: AppColors.gold, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label ?? 'STEP $step',
                        style: TextStyle(
                          color: AppColors.gold.withValues(alpha: 0.7),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                    ],
                  ),
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

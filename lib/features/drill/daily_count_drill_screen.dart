import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/growth/share_messages.dart';
import '../../theme/app_theme.dart';
import '../table/widgets/card_widget.dart';
import 'daily_count_drill.dart';
import 'daily_count_drill_progress.dart';

class DailyCountDrillScreen extends StatefulWidget {
  const DailyCountDrillScreen({super.key});

  @override
  State<DailyCountDrillScreen> createState() => _DailyCountDrillScreenState();
}

class _DailyCountDrillScreenState extends State<DailyCountDrillScreen> {
  late DailyCountDrill _drill;
  Timer? _timer;
  int _secondsRemaining = dailyCountDrillDurationSeconds;
  int _cardIndex = 0;
  int _correct = 0;
  int _streak = 0;
  int _bestStreak = 0;
  bool _finished = false;
  DailyCountDrillBest? _todayBest;

  @override
  void initState() {
    super.initState();
    _drill = DailyCountDrill.today();
    _loadBest();
    _startTimer();
  }

  Future<void> _loadBest() async {
    final best = await DailyCountDrillProgress.load(_drill.dayKey);
    if (mounted) setState(() => _todayBest = best);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _finished) return;
      if (_secondsRemaining <= 1) {
        _finish();
      } else {
        setState(() => _secondsRemaining -= 1);
      }
    });
  }

  void _answer(int contribution) {
    if (_finished || _cardIndex >= _drill.cards.length) return;

    final isCorrect =
        DailyCountDrill.contributionFor(_drill.cards[_cardIndex]) ==
            contribution;
    setState(() {
      _cardIndex += 1;
      if (isCorrect) {
        _correct += 1;
        _streak += 1;
        if (_streak > _bestStreak) _bestStreak = _streak;
      } else {
        _streak = 0;
      }
    });

    if (_cardIndex == _drill.cards.length) _finish();
  }

  Future<void> _finish() async {
    if (_finished) return;
    _timer?.cancel();
    final result = DailyCountDrillResult(
      dayKey: _drill.dayKey,
      correct: _correct,
      answered: _cardIndex,
      bestStreak: _bestStreak,
    );
    setState(() => _finished = true);

    final best = await DailyCountDrillProgress.record(result);
    if (mounted) setState(() => _todayBest = best);
  }

  void _tryAgain() {
    setState(() {
      _secondsRemaining = dailyCountDrillDurationSeconds;
      _cardIndex = 0;
      _correct = 0;
      _streak = 0;
      _bestStreak = 0;
      _finished = false;
    });
    _startTimer();
  }

  Future<void> _shareResult(BuildContext shareContext) async {
    final box = shareContext.findRenderObject() as RenderBox?;
    final origin =
        box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    await Share.share(
      GrowthShareMessages.dailyDrill(
        correct: _correct,
        total: dailyCountDrillCardCount,
        bestStreak: _bestStreak,
      ),
      subject: 'My Hi-Lo Count Drill score',
      sharePositionOrigin: origin,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                child: _finished ? _resultView() : _drillView(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.gold),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'DAILY COUNT DRILL',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.2,
              ),
            ),
          ),
          _timerBadge(),
        ],
      ),
    );
  }

  Widget _timerBadge() {
    final urgent = _secondsRemaining <= 10;
    final color = urgent ? AppColors.unfavorable : AppColors.gold;
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        '0:${_secondsRemaining.toString().padLeft(2, '0')}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _drillView() {
    final card = _drill.cards[_cardIndex];
    final progress = _cardIndex / dailyCountDrillCardCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _progressPanel(progress),
        const SizedBox(height: 26),
        Text(
          'HOW DOES THIS CARD CHANGE THE HI-LO COUNT?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 18),
        Center(
          child: CardWidget(
            key: ValueKey(_cardIndex),
            card: card,
            width: 132,
            animate: false,
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            _answerButton(
              contribution: -1,
              label: '-1',
              color: AppColors.unfavorable,
            ),
            const SizedBox(width: 10),
            _answerButton(
              contribution: 0,
              label: '0',
              color: AppColors.neutral,
            ),
            const SizedBox(width: 10),
            _answerButton(
              contribution: 1,
              label: '+1',
              color: AppColors.favorable,
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (_todayBest != null)
          Text(
            'TODAY\'S BEST  ${_todayBest!.correct}/$dailyCountDrillCardCount'
            '  |  STREAK ${_todayBest!.bestStreak}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.gold.withValues(alpha: 0.75),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
      ],
    );
  }

  Widget _progressPanel(double progress) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'CARD ${_cardIndex + 1} OF $dailyCountDrillCardCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '$_correct RIGHT',
                style: const TextStyle(
                  color: AppColors.favorable,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation(AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _answerButton({
    required int contribution,
    required String label,
    required Color color,
  }) {
    final foreground = contribution == 0 ? AppColors.wood : Colors.white;
    return Expanded(
      child: SizedBox(
        height: 58,
        child: FilledButton(
          onPressed: () => _answer(contribution),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: foreground,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultView() {
    final result = DailyCountDrillResult(
      dayKey: _drill.dayKey,
      correct: _correct,
      answered: _cardIndex,
      bestStreak: _bestStreak,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.42)),
      ),
      child: Column(
        children: [
          const Icon(Icons.bolt, color: AppColors.gold, size: 38),
          const SizedBox(height: 12),
          const Text(
            'DRILL COMPLETE',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '${result.correct}/${result.total}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 52,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          Text(
            '${result.accuracy}% ACCURACY  |  BEST STREAK ${result.bestStreak}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
          if (result.answered < result.total) ...[
            const SizedBox(height: 12),
            Text(
              '${result.answered} of $dailyCountDrillCardCount cards answered',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 26),
          Builder(
            builder: (shareContext) => SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: () => _shareResult(shareContext),
                icon: const Icon(Icons.ios_share),
                label: const Text('SHARE RESULT'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.wood,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _tryAgain,
              icon: const Icon(Icons.refresh),
              label: const Text('TRY AGAIN'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

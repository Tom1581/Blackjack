import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../table/widgets/discard_tray.dart';
import 'drills.dart';
import 'training_widgets.dart';

/// Running count to true count: divide by the decks still in the shoe.
///
/// This is the step that turns counting into a bet size, and the one players
/// skip. Each question shows the running count and the discard tray the way
/// the table does, so the division is practised on the same picture a
/// counter reads in a casino.
class TrueCountDrillScreen extends StatefulWidget {
  const TrueCountDrillScreen({super.key});

  static const questions = 10;

  @override
  State<TrueCountDrillScreen> createState() => _TrueCountDrillScreenState();
}

class _TrueCountDrillScreenState extends State<TrueCountDrillScreen> {
  late TrueCountQuestion _q;
  int _index = 0;
  int _correct = 0;
  int? _picked;
  bool _finished = false;
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    setState(() {
      _q = TrueCountQuestion.generate();
      _index = 0;
      _correct = 0;
      _picked = null;
      _finished = false;
    });
    _stopwatch
      ..reset()
      ..start();
  }

  void _pick(int option) {
    if (_picked != null) return;
    final right = option == _q.answer;
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _picked = option;
      if (right) _correct++;
    });
  }

  void _next() {
    if (_index + 1 >= TrueCountDrillScreen.questions) {
      _stopwatch.stop();
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _picked = null;
      _q = TrueCountQuestion.generate();
    });
  }

  String _signed(num v) => v > 0 ? '+$v' : '$v';

  String _decks(double d) =>
      d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return TrainingScaffold(
      title: 'TRUE COUNT',
      trailing: _finished
          ? null
          : TrainingBadge('${_index + 1}/${TrueCountDrillScreen.questions}'),
      child: _finished ? _result() : _question(),
    );
  }

  Widget _question() {
    final answered = _picked != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RUNNING COUNT',
                      style: TextStyle(
                        color: AppColors.neutral,
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _signed(_q.runningCount),
                      key: const ValueKey('tc-rc'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_decks(_q.decksLeft)} of ${_q.shoeDecks} decks left',
                      key: const ValueKey('tc-decks'),
                      style: TextStyle(
                        color: AppColors.gold.withValues(alpha: 0.9),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              DiscardTray(
                penetration: _q.penetration,
                decks: _q.shoeDecks,
                height: 110,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'TRUE COUNT, TO THE NEAREST WHOLE NUMBER',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
          children: [
            for (final o in _q.options)
              FilledButton(
                onPressed: answered ? null : () => _pick(o),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                  disabledBackgroundColor: !answered
                      ? null
                      : o == _q.answer
                          ? AppColors.favorable.withValues(alpha: 0.85)
                          : o == _picked
                              ? AppColors.unfavorable.withValues(alpha: 0.85)
                              : Colors.black.withValues(alpha: 0.2),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                        color: AppColors.gold.withValues(alpha: 0.3)),
                  ),
                ),
                child: Text(
                  _signed(o),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (answered) ...[
          Text(
            '${_signed(_q.runningCount)} ÷ ${_decks(_q.decksLeft)} = '
            '${(_q.runningCount / _q.decksLeft).toStringAsFixed(2)}'
            '  →  ${_signed(_q.answer)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _picked == _q.answer
                  ? AppColors.favorable
                  : AppColors.unfavorable,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          TrainingButton(
            label: _index + 1 >= TrueCountDrillScreen.questions
                ? 'SEE RESULT'
                : 'NEXT',
            onPressed: _next,
          ),
        ],
      ],
    );
  }

  Widget _result() {
    final seconds = _stopwatch.elapsed.inSeconds;
    return TrainingResultPanel(
      icon: Icons.calculate_outlined,
      title: 'TRUE COUNT DRILL',
      headline: '$_correct/${TrueCountDrillScreen.questions}',
      headlineColor: _correct >= 9 ? AppColors.favorable : Colors.white,
      detail: '${seconds}s in total. At the table you have about two seconds '
          'per conversion — aim for all ten in under 30s.',
      children: [
        TrainingButton(
          label: 'GO AGAIN',
          icon: Icons.refresh,
          onPressed: _restart,
        ),
      ],
    );
  }
}

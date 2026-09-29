import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strategy/basic_strategy.dart';
import '../../core/strategy/deviations.dart';
import '../../core/strategy/strategy_coach.dart' show formatTrueCount;
import '../../theme/app_theme.dart';
import '../table/table_provider.dart';
import '../table/widgets/card_widget.dart';
import 'drills.dart';
import 'training_widgets.dart';

/// Flash cards for the Illustrious 18 and the Fab 4: a hand, the dealer's card
/// and a true count; make the play the count calls for.
///
/// Counts are drawn within three of each index and shown to one decimal, so
/// the floor rule is part of the test — at +2.9 an index of +3 has not been
/// reached.
class IndexDrillScreen extends ConsumerStatefulWidget {
  const IndexDrillScreen({super.key});

  static const questions = 20;

  @override
  ConsumerState<IndexDrillScreen> createState() => _IndexDrillScreenState();
}

class _IndexDrillScreenState extends ConsumerState<IndexDrillScreen> {
  final _rng = Random();
  late IndexDrillQuestion _q;
  int _index = 0;
  int _correct = 0;
  bool _finished = false;

  /// The answer given: a move for a hand question, or true/false for
  /// insurance. Null until answered.
  Object? _given;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    _q = _next();
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  IndexDrillQuestion _next() =>
      IndexDrillQuestion.random(rules: ref.read(rulesProvider), rng: _rng);

  bool get _answered => _given != null;

  bool get _right => _q.isInsurance ? _given == _q.insure : _given == _q.answer;

  void _answer(Object value) {
    if (_answered) return;
    setState(() => _given = value);
    if (_right) {
      _correct++;
      HapticFeedback.lightImpact();
      _advance = Timer(const Duration(milliseconds: 900), _proceed);
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  void _proceed() {
    _advance?.cancel();
    if (!mounted) return;
    if (_index + 1 >= IndexDrillScreen.questions) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _given = null;
      _q = _next();
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _correct = 0;
      _given = null;
      _finished = false;
      _q = _next();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TrainingScaffold(
      title: 'INDEX PLAYS',
      trailing: _finished
          ? null
          : TrainingBadge('${_index + 1}/${IndexDrillScreen.questions}'),
      child: _finished ? _result() : _question(),
    );
  }

  String _explanation() {
    final tc = formatTrueCount(_q.trueCount);
    if (_q.isInsurance) {
      return 'Insurance at $tc — take it at '
          '+${Deviations.insuranceIndex} or higher. '
          '${_q.insure ? 'Take it.' : 'Decline.'}';
    }
    final d = _q.decision;
    final play = d?.play ?? _q.play!;
    return '${play.label} (${play.set.label}): ${play.rule}. '
        'At $tc → ${_q.answer.label}.';
  }

  Widget _question() {
    final shoe = ref.watch(shoeModeProvider);
    final moves = [
      StrategyMove.hit,
      StrategyMove.stand,
      StrategyMove.double,
      StrategyMove.split,
      if (_q.surrenderOffered) StrategyMove.surrender,
    ];

    return Column(
      children: [
        if (shoe.numDecks < Deviations.minDecks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'These are the multi-deck (4+ deck) indices. Your table is '
              'set to ${shoe.numDecks} decks, where the coach does not use '
              'them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11.5,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
          ),
          child: Text(
            'TRUE COUNT  ${formatTrueCount(_q.trueCount)}',
            key: const ValueKey('index-tc'),
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          [
            _q.rules.dealerLabel,
            if (_q.surrenderOffered) 'surrender allowed',
            '6 decks',
          ].join(' · '),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 18),
        CardWidget(
          key: ValueKey('iu$_index'),
          card: _q.dealerUp,
          width: 70,
          animate: false,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _q.hand.cards.length; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                child: CardWidget(
                  key: ValueKey('ip$_index-$i'),
                  card: _q.hand.cards[i],
                  width: 70,
                  animate: false,
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (_q.isInsurance) ...[
          Text(
            'The dealer shows an ace. Insurance?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final take in [true, false]) ...[
                if (!take) const SizedBox(width: 10),
                Expanded(
                  child: _ChoiceButton(
                    label: take ? 'INSURE' : 'NO THANKS',
                    enabled: !_answered,
                    highlight: _answered && take == _q.insure,
                    wrong: _answered && _given == take && !_right,
                    onTap: () => _answer(take),
                  ),
                ),
              ],
            ],
          ),
        ] else
          Row(
            children: [
              for (final move in moves) ...[
                if (move != moves.first) const SizedBox(width: 6),
                Expanded(
                  child: _ChoiceButton(
                    label: move.label.toUpperCase(),
                    enabled: !_answered &&
                        (move != StrategyMove.split || _q.hand.isPair),
                    highlight: _answered && move == _q.answer,
                    wrong: _answered && _given == move && !_right,
                    onTap: () => _answer(move),
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 16),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _answered ? 1 : 0,
          child: Text(
            _answered ? _explanation() : ' ',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _right ? AppColors.favorable : AppColors.unfavorable,
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (_answered && !_right) ...[
          const SizedBox(height: 14),
          TrainingButton(label: 'NEXT', onPressed: _proceed),
        ],
      ],
    );
  }

  Widget _result() {
    final pct = (_correct * 100 / IndexDrillScreen.questions).round();
    return TrainingResultPanel(
      icon: Icons.insights_outlined,
      title: 'INDEX DRILL',
      headline: '$pct%',
      headlineColor: pct >= 90 ? AppColors.favorable : Colors.white,
      detail: '$_correct of ${IndexDrillScreen.questions} right. Learn them '
          'in order: insurance and the top six are most of the value.',
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

class _ChoiceButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool highlight;
  final bool wrong;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.label,
    required this.enabled,
    required this.highlight,
    required this.wrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border = highlight
        ? AppColors.favorable
        : wrong
            ? AppColors.unfavorable
            : AppColors.gold.withValues(alpha: 0.3);
    return Opacity(
      opacity: enabled || highlight || wrong ? 1 : 0.35,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: border, width: highlight || wrong ? 2.5 : 1),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

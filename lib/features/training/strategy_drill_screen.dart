import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/card_model.dart';
import '../../core/strategy/basic_strategy.dart';
import '../../core/strategy/strategy_coach.dart';
import '../../theme/app_theme.dart';
import '../table/table_provider.dart';
import '../table/widgets/card_widget.dart';
import 'drills.dart';
import 'training_widgets.dart';

/// Flash-card basic strategy: a hand, a dealer card, one decision, instant
/// feedback. Twenty hands take about a minute, which is how the chart gets
/// learned — far more decisions per minute than playing out real rounds.
///
/// "My mistakes" deals the chart cells this player has actually got wrong at
/// the table, so practice goes where it is needed.
class StrategyDrillScreen extends ConsumerStatefulWidget {
  const StrategyDrillScreen({super.key});

  static const hands = 20;

  @override
  ConsumerState<StrategyDrillScreen> createState() =>
      _StrategyDrillScreenState();
}

class _StrategyDrillScreenState extends ConsumerState<StrategyDrillScreen> {
  final _rng = Random();
  StrategyDrillFocus _focus = StrategyDrillFocus.all;
  bool _running = false;
  bool _finished = false;
  List<String> _misses = const [];

  late StrategyDrillHand _hand;
  int _index = 0;
  int _correct = 0;
  StrategyMove? _played;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    StrategyCoach.readMastery().then((m) {
      if (mounted) {
        setState(() => _misses = [for (final x in m.topMisses) x.spot]);
      }
    });
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  StrategyDrillHand _deal() {
    if (_focus == StrategyDrillFocus.mistakes && _misses.isNotEmpty) {
      // Mostly the cells they miss, with the odd random hand so the drill
      // cannot be passed by memorising five answers.
      if (_rng.nextInt(4) != 0) {
        final spot = _misses[_rng.nextInt(_misses.length)];
        final hand = StrategyDrillHand.fromSpot(spot, rng: _rng);
        if (hand != null) return hand;
      }
    }
    return StrategyDrillHand.random(_focus, rng: _rng);
  }

  void _start() {
    HapticFeedback.mediumImpact();
    setState(() {
      _running = true;
      _finished = false;
      _index = 0;
      _correct = 0;
      _played = null;
      _hand = _deal();
    });
  }

  void _play(StrategyMove move) {
    if (_played != null) return;
    final rules = ref.read(rulesProvider);
    final decks = ref.read(shoeModeProvider).numDecks;
    final right = move == _hand.answer(rules, decks: decks);
    right ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    setState(() {
      _played = move;
      if (right) _correct++;
    });
    if (right) {
      _advance = Timer(const Duration(milliseconds: 650), _next);
    }
  }

  void _next() {
    _advance?.cancel();
    if (!mounted) return;
    if (_index + 1 >= StrategyDrillScreen.hands) {
      setState(() {
        _running = false;
        _finished = true;
      });
      return;
    }
    setState(() {
      _index++;
      _played = null;
      _hand = _deal();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TrainingScaffold(
      title: 'STRATEGY DRILL',
      trailing: _running
          ? TrainingBadge('${_index + 1}/${StrategyDrillScreen.hands}')
          : null,
      child: _running
          ? _drill()
          : _finished
              ? _result()
              : _setup(),
    );
  }

  Widget _setup() {
    final rules = ref.watch(rulesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'One decision per hand, marked instantly against the chart for '
          '${rules.name} (${rules.summary}).',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        ChoiceRow<StrategyDrillFocus>(
          label: 'FOCUS',
          value: _focus,
          options: [for (final f in StrategyDrillFocus.values) (f, f.label)],
          onChanged: (v) => setState(() => _focus = v),
        ),
        if (_focus == StrategyDrillFocus.mistakes) ...[
          const SizedBox(height: 10),
          Text(
            _misses.isEmpty
                ? 'No misses recorded yet. Play some hands at the table and '
                    'the ones you get wrong will show up here — until then '
                    'this deals random hands.'
                : 'Your most-missed: ${_misses.join(' · ')}',
            style: TextStyle(
              color: AppColors.gold.withValues(alpha: 0.8),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 30),
        TrainingButton(
          label: 'START',
          icon: Icons.play_arrow_rounded,
          onPressed: _start,
        ),
      ],
    );
  }

  Widget _drill() {
    final rules = ref.watch(rulesProvider);
    final best =
        _hand.answer(rules, decks: ref.watch(shoeModeProvider).numDecks);
    final moves = [
      StrategyMove.hit,
      StrategyMove.stand,
      StrategyMove.double,
      StrategyMove.split,
      if (rules.lateSurrender) StrategyMove.surrender,
    ];
    final answered = _played != null;
    final right = _played == best;
    final hand = _hand.hand;
    String rank(int v) => v == 11 ? 'A' : '$v';
    final pairRank = rank(hand.cards.first.rank.value);
    final label = hand.isPair
        ? '$pairRank,$pairRank'
        : hand.isSoft
            ? 'Soft ${hand.value}'
            : 'Hard ${hand.value}';
    final up = rank(_hand.dealerUp.rank.value);

    return Column(
      children: [
        const SizedBox(height: 6),
        Text(
          'DEALER',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
            letterSpacing: 2.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        CardWidget(
          key: ValueKey('up$_index'),
          card: _hand.dealerUp,
          width: 78,
          animate: false,
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < hand.cards.length; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                child: CardWidget(
                  key: ValueKey('p$_index-$i'),
                  card: hand.cards[i],
                  width: 78,
                  animate: false,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            for (final move in moves) ...[
              if (move != moves.first) const SizedBox(width: 8),
              Expanded(
                child: _MoveButton(
                  move: move,
                  enabled:
                      !answered && (move != StrategyMove.split || _hand.isPair),
                  highlight: answered && move == best,
                  wrong: answered && move == _played && !right,
                  onTap: () => _play(move),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: answered ? 1 : 0,
          child: Text(
            !answered
                ? ' '
                : right
                    ? 'Correct — ${best.label}'
                    : '$label vs $up — the chart says ${best.label}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: right ? AppColors.favorable : AppColors.unfavorable,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (answered && !right) ...[
          const SizedBox(height: 16),
          TrainingButton(label: 'NEXT HAND', onPressed: _next),
        ],
      ],
    );
  }

  Widget _result() {
    final pct = (_correct * 100 / StrategyDrillScreen.hands).round();
    return TrainingResultPanel(
      icon: Icons.fact_check_outlined,
      title: 'DRILL COMPLETE',
      headline: '$pct%',
      headlineColor: pct >= 95
          ? AppColors.favorable
          : pct >= 85
              ? AppColors.gold
              : AppColors.unfavorable,
      detail: '$_correct of ${StrategyDrillScreen.hands} right on '
          '${_focus.label.toLowerCase()}. '
          '${pct >= 95 ? 'That is casino-ready basic strategy.' : 'Aim for 95% before moving on to counting at the table.'}',
      children: [
        TrainingButton(
          label: 'GO AGAIN',
          icon: Icons.refresh,
          onPressed: _start,
        ),
        const SizedBox(height: 10),
        TrainingButton(
          label: 'CHANGE FOCUS',
          outlined: true,
          onPressed: () => setState(() => _finished = false),
        ),
      ],
    );
  }
}

class _MoveButton extends StatelessWidget {
  final StrategyMove move;
  final bool enabled;
  final bool highlight;
  final bool wrong;
  final VoidCallback onTap;

  const _MoveButton({
    required this.move,
    required this.enabled,
    required this.highlight,
    required this.wrong,
    required this.onTap,
  });

  Color get _fill {
    switch (move) {
      case StrategyMove.hit:
        return AppColors.btnHit;
      case StrategyMove.stand:
        return AppColors.btnStand;
      case StrategyMove.double:
        return AppColors.btnDouble;
      case StrategyMove.split:
        return AppColors.btnSplit;
      case StrategyMove.surrender:
        return AppColors.btnSurrender;
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = highlight
        ? AppColors.favorable
        : wrong
            ? AppColors.unfavorable
            : Colors.white.withValues(alpha: 0.15);
    return Opacity(
      opacity: enabled || highlight || wrong ? 1 : 0.35,
      child: Material(
        color: _fill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Container(
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: border, width: highlight || wrong ? 2.5 : 1),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                move.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

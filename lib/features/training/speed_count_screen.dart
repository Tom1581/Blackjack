import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../table/widgets/card_widget.dart';
import 'drills.dart';
import 'training_widgets.dart';

enum _Stage { setup, dealing, answer, result }

/// Cards flash past at table speed and the player keeps the running count in
/// their head — the one skill a casino actually tests. The Daily Count Drill
/// checks each card's tag; this checks the count that has to survive a whole
/// run of them.
class SpeedCountScreen extends StatefulWidget {
  const SpeedCountScreen({super.key});

  @override
  State<SpeedCountScreen> createState() => _SpeedCountScreenState();
}

class _SpeedCountScreenState extends State<SpeedCountScreen> {
  SpeedCountLength _length = SpeedCountLength.short;
  SpeedCountPace _pace = SpeedCountPace.brisk;
  _Stage _stage = _Stage.setup;

  SpeedCountRound? _round;
  int _shown = 0;
  int _guess = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    HapticFeedback.mediumImpact();
    _timer?.cancel();
    setState(() {
      _round = SpeedCountRound.generate(_length);
      _shown = 1;
      _guess = 0;
      _stage = _Stage.dealing;
    });
    _timer = Timer.periodic(_pace.perCard, (_) {
      if (!mounted) return;
      final round = _round!;
      if (_shown >= round.cards.length) {
        _timer?.cancel();
        setState(() => _stage = _Stage.answer);
        return;
      }
      setState(() => _shown++);
    });
  }

  void _check() {
    HapticFeedback.mediumImpact();
    setState(() => _stage = _Stage.result);
  }

  String _signed(int v) => v > 0 ? '+$v' : '$v';

  @override
  Widget build(BuildContext context) {
    return TrainingScaffold(
      title: 'SPEED COUNT',
      trailing: _stage == _Stage.dealing
          ? TrainingBadge('$_shown/${_round!.cards.length}')
          : null,
      child: switch (_stage) {
        _Stage.setup => _setup(),
        _Stage.dealing => _dealing(),
        _Stage.answer => _answer(),
        _Stage.result => _result(),
      },
    );
  }

  Widget _setup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cards are dealt one at a time. Keep the Hi-Lo running count in '
          'your head — there are no buttons to press until the end.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 22),
        ChoiceRow<SpeedCountLength>(
          label: 'LENGTH',
          value: _length,
          options: [for (final l in SpeedCountLength.values) (l, l.label)],
          onChanged: (v) => setState(() => _length = v),
        ),
        const SizedBox(height: 6),
        Text(
          _length.blurb,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 18),
        ChoiceRow<SpeedCountPace>(
          label: 'PACE',
          value: _pace,
          options: [for (final p in SpeedCountPace.values) (p, p.label)],
          onChanged: (v) => setState(() => _pace = v),
        ),
        const SizedBox(height: 30),
        TrainingButton(
          label: 'START',
          icon: Icons.play_arrow_rounded,
          onPressed: _start,
        ),
      ],
    );
  }

  Widget _dealing() {
    final round = _round!;
    final card = round.cards[_shown - 1];
    return Column(
      children: [
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: _shown / round.cards.length,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation(AppColors.gold),
          ),
        ),
        const SizedBox(height: 40),
        CardWidget(
          key: ValueKey(_shown),
          card: card,
          width: 150,
          animate: false,
        ),
        const SizedBox(height: 30),
        Text(
          'KEEP THE COUNT',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 22),
        TextButton(
          onPressed: () {
            _timer?.cancel();
            setState(() => _stage = _Stage.setup);
          },
          child: const Text('STOP'),
        ),
      ],
    );
  }

  Widget _answer() {
    final round = _round!;
    final deck = round.heldBack.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text(
          deck
              ? 'The deck is done, with ${round.heldBack.length} '
                  'card${round.heldBack.length == 1 ? '' : 's'} held back. '
                  'What is your running count?'
              : 'What is your running count?',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 26),
        CountStepper(
          value: _guess,
          onChanged: (v) => setState(() => _guess = v),
        ),
        const SizedBox(height: 32),
        TrainingButton(label: 'CHECK', onPressed: _check),
      ],
    );
  }

  Widget _result() {
    final round = _round!;
    final right = _guess == round.answer;
    return Column(
      children: [
        TrainingResultPanel(
          icon: right ? Icons.verified_outlined : Icons.replay,
          title: right ? 'PERFECT COUNT' : 'NOT QUITE',
          headline: _signed(round.answer),
          headlineColor: right ? AppColors.favorable : Colors.white,
          detail: right
              ? '${round.cards.length} cards at ${_pace.label.toLowerCase()} '
                  'pace, counted exactly.'
              : 'You said ${_signed(_guess)}. Off by '
                  '${(_guess - round.answer).abs()} — try a slower pace, or '
                  'cancel pairs (a low and a high card) as you go.',
          children: [
            if (round.heldBack.isNotEmpty) ...[
              Text(
                'HELD BACK',
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in round.heldBack)
                    CardWidget(card: c, width: 54, animate: false),
                ],
              ),
              const SizedBox(height: 20),
            ],
            TrainingButton(
              label: 'GO AGAIN',
              icon: Icons.refresh,
              onPressed: _start,
            ),
            const SizedBox(height: 10),
            TrainingButton(
              label: 'CHANGE SETTINGS',
              outlined: true,
              onPressed: () => setState(() => _stage = _Stage.setup),
            ),
          ],
        ),
      ],
    );
  }
}

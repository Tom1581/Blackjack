import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../training/training_widgets.dart';
import 'widgets/hilo_button.dart';
import 'hilo_game.dart';
import 'hilo_game_screen.dart';
import 'hilo_scoring.dart';
import 'hilo_training_progress.dart';
import 'hilo_training_session.dart';

/// Practice: pick the table and the pace, no clock on the answers.
class HiLoPracticeSetupScreen extends StatefulWidget {
  /// Fixes the shoe, for tests.
  final int? seed;

  const HiLoPracticeSetupScreen({super.key, this.seed});

  @override
  State<HiLoPracticeSetupScreen> createState() =>
      _HiLoPracticeSetupScreenState();
}

class _HiLoPracticeSetupScreenState extends State<HiLoPracticeSetupScreen> {
  HiLoTrainingConfig _config = const HiLoTrainingConfig();
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    HiLoTrainingProgress.loadConfig().then((config) {
      if (mounted && !_touched) setState(() => _config = config);
    });
  }

  void _set(HiLoTrainingConfig next) {
    HapticFeedback.selectionClick();
    setState(() {
      _config = next;
      _touched = true;
    });
  }

  void _deal() {
    HapticFeedback.mediumImpact();
    unawaited(HiLoTrainingProgress.saveConfig(_config));
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HiLoGameScreen(
        spec: HiLoGameSpec.practice(_config, seed: widget.seed),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: Colors.white.withValues(alpha: 0.45),
      fontSize: 11.5,
    );
    return TrainingScaffold(
      title: 'PRACTICE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your table, your pace, no clock. The dealer deals real rounds '
            'and stops at a random card to ask for the running count.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const HiLoTagLegend(),
          const SizedBox(height: 20),
          ChoiceRow<int>(
            label: 'PLAYERS AT THE TABLE',
            value: _config.players,
            options: [
              for (final p in HiLoTrainingConfig.playerOptions) (p, '$p'),
            ],
            onChanged: (v) => _set(_config.copyWith(players: v)),
          ),
          const SizedBox(height: 16),
          ChoiceRow<int>(
            label: 'DECKS IN THE SHOE',
            value: _config.decks,
            options: [
              for (final d in HiLoTrainingConfig.deckOptions) (d, '$d decks'),
            ],
            onChanged: (v) => _set(_config.copyWith(decks: v)),
          ),
          const SizedBox(height: 16),
          ChoiceRow<HiLoPace>(
            label: 'DEALING PACE',
            value: _config.pace,
            options: [for (final p in HiLoPace.values) (p, p.label)],
            onChanged: (v) => _set(_config.copyWith(pace: v)),
          ),
          const SizedBox(height: 16),
          ChoiceRow<HiLoQuizFrequency>(
            label: 'COUNT CHECKS',
            value: _config.frequency,
            options: [for (final f in HiLoQuizFrequency.values) (f, f.label)],
            onChanged: (v) => _set(_config.copyWith(frequency: v)),
          ),
          const SizedBox(height: 6),
          Text(_config.frequency.blurb, style: muted),
          const SizedBox(height: 16),
          ChoiceRow<int>(
            label: 'QUESTIONS',
            value: _config.questions,
            options: [
              for (final q in HiLoTrainingConfig.questionOptions) (q, '$q'),
            ],
            onChanged: (v) => _set(_config.copyWith(questions: v)),
          ),
          const SizedBox(height: 16),
          ChoiceRow<bool>(
            label: 'THE DEALER ASKS FOR',
            value: _config.trueCount,
            options: const [(false, 'Running count'), (true, '+ True count')],
            onChanged: (v) => _set(_config.copyWith(trueCount: v)),
          ),
          const SizedBox(height: 6),
          Text(
            _config.trueCount
                ? 'Then the true count: your running count ÷ the decks left, '
                    'read off the discard tray. +${HiLoScoring.trueCountBonus} '
                    'when it\'s right.'
                : 'Add the true count once the running count holds — it is '
                    'the number a counter bets on.',
            style: muted,
          ),
          const SizedBox(height: 26),
          HiLoButton(
            label: 'DEAL',
            icon: Icons.play_arrow_rounded,
            onPressed: _deal,
          ),
        ],
      ),
    );
  }
}

/// Duel: two players, one phone. Both watch the same cards and answer in
/// secret; the dealer reveals both.
class HiLoDuelSetupScreen extends StatefulWidget {
  /// Fixes the shoe, for tests.
  final int? seed;

  const HiLoDuelSetupScreen({super.key, this.seed});

  @override
  State<HiLoDuelSetupScreen> createState() => _HiLoDuelSetupScreenState();
}

class _HiLoDuelSetupScreenState extends State<HiLoDuelSetupScreen> {
  final _names = [TextEditingController(), TextEditingController()];
  int _questions = 5;
  HiLoPace _pace = HiLoPace.steady;

  static const _nameLimit = 12;

  @override
  void initState() {
    super.initState();
    HiLoTrainingProgress.loadDuelNames().then((names) {
      if (!mounted) return;
      for (var i = 0; i < 2; i++) {
        if (_names[i].text.isEmpty) _names[i].text = names[i];
      }
    });
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  void _start() {
    HapticFeedback.mediumImpact();
    final names = [
      for (var i = 0; i < 2; i++)
        _names[i].text.trim().isEmpty
            ? 'Player ${i + 1}'
            : _names[i].text.trim(),
    ];
    if (names[0].toLowerCase() == names[1].toLowerCase()) {
      names[1] = '${names[1]} 2';
    }
    unawaited(HiLoTrainingProgress.saveDuelNames(
        [for (final c in _names) c.text.trim()]));
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HiLoGameScreen(
        spec: HiLoGameSpec.duel(
          names: names,
          questions: _questions,
          pace: _pace,
          seed: widget.seed,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return TrainingScaffold(
      title: 'DUEL',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Two players, one phone. You both watch the same cards. When the '
            'dealer stops, each of you enters a count in secret, passing the '
            'phone between turns — then the dealer reveals both. Right '
            'answers score, fast ones score more, and streaks multiply.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < 2; i++) ...[
            TextField(
              key: ValueKey('hilo-duel-name-$i'),
              controller: _names[i],
              maxLength: _nameLimit,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: 'PLAYER ${i + 1}',
                hintText: 'Player ${i + 1}',
                counterText: '',
                labelStyle: TextStyle(
                  color: i == 0 ? AppColors.gold : const Color(0xFF5AB0FF),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  fontSize: 12,
                ),
                prefixIcon: Icon(
                  Icons.person_outline,
                  color: i == 0 ? AppColors.gold : const Color(0xFF5AB0FF),
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.25),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 6),
          ChoiceRow<int>(
            label: 'QUESTIONS',
            value: _questions,
            options: const [(5, '5'), (10, '10')],
            onChanged: (v) => setState(() => _questions = v),
          ),
          const SizedBox(height: 16),
          ChoiceRow<HiLoPace>(
            label: 'DEALING PACE',
            value: _pace,
            options: [for (final p in HiLoPace.values) (p, p.label)],
            onChanged: (v) => setState(() => _pace = v),
          ),
          const SizedBox(height: 26),
          HiLoButton(
            label: 'START THE DUEL',
            icon: Icons.play_arrow_rounded,
            onPressed: _start,
          ),
        ],
      ),
    );
  }
}

/// The three Hi-Lo tags, side by side.
class HiLoTagLegend extends StatelessWidget {
  const HiLoTagLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        _TagChip(cards: '2–6', tag: '+1', color: AppColors.favorable),
        SizedBox(width: 6),
        _TagChip(cards: '7–9', tag: '0', color: AppColors.neutral),
        SizedBox(width: 6),
        _TagChip(cards: '10–A', tag: '−1', color: AppColors.unfavorable),
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  final String cards;
  final String tag;
  final Color color;

  const _TagChip({required this.cards, required this.tag, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          children: [
            Text(
              tag,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              cards,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

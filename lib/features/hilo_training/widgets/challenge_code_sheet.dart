import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../hilo_game.dart';
import '../hilo_text.dart';

/// Ask for a friend's challenge code, show what it deals, and return it once
/// the player chooses to play. Null if they back out.
Future<HiLoChallenge?> showChallengeCodeSheet(BuildContext context) {
  return showModalBottomSheet<HiLoChallenge>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _CodeSheet(),
  );
}

class _CodeSheet extends StatefulWidget {
  const _CodeSheet();

  @override
  State<_CodeSheet> createState() => _CodeSheetState();
}

class _CodeSheetState extends State<_CodeSheet> {
  final _controller = TextEditingController();
  HiLoChallenge? _challenge;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    setState(() => _challenge = HiLoChallenge.decode(text));
  }

  @override
  Widget build(BuildContext context) {
    final c = _challenge;
    final typed = _controller.text.replaceAll(RegExp(r'[\s-]'), '').length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ENTER A CHALLENGE CODE',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'A friend\'s code deals you their exact shoe. Beat their score.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('hilo-code-field'),
              controller: _controller,
              autofocus: true,
              onChanged: _changed,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                LengthLimitingTextInputFormatter(16),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX-XXX',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.2),
                  letterSpacing: 3,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.goldDim),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.goldDim),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.gold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (c != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.favorable.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.favorable.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCORE TO BEAT: ${points(c.score)}',
                      style: const TextStyle(
                        color: AppColors.favorable,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.survival
                          ? 'Survival · 3 lives · the dealer speeds up'
                          : '${tableLabel(c.config)} · ${c.config.questions} '
                              'counts · 15 s clock',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              )
            else if (typed >= 11)
              const Text(
                'That code doesn\'t look right — check each character.',
                key: ValueKey('hilo-code-error'),
                style: TextStyle(color: AppColors.unfavorable, fontSize: 12.5),
              ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const ValueKey('hilo-code-play'),
                onPressed: c == null ? null : () => Navigator.pop(context, c),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.wood,
                  disabledBackgroundColor:
                      AppColors.goldDim.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                child: const Text('PLAY THIS SHOE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

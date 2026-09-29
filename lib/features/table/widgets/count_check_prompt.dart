import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../table_provider.dart';

/// "What's the running count?" — asked every few rounds while the count HUD
/// is hidden.
///
/// Playing with the HUD off is how a counter practises for a real casino,
/// where nobody shows you the count. Without this check nothing ever tells
/// them they drifted three hands ago; with it, every fifth round is a test.
class CountCheckPrompt extends ConsumerStatefulWidget {
  final CountCheck check;

  const CountCheckPrompt({super.key, required this.check});

  @override
  ConsumerState<CountCheckPrompt> createState() => _CountCheckPromptState();
}

class _CountCheckPromptState extends ConsumerState<CountCheckPrompt> {
  int _guess = 0;

  /// Null until answered, then whether the answer was right.
  bool? _correct;

  void _submit() {
    HapticFeedback.mediumImpact();
    final correct = ref.read(tableProvider.notifier).answerCountCheck(_guess);
    setState(() => _correct = correct);
  }

  void _close() => ref.read(tableProvider.notifier).dismissCountCheck();

  String _signed(int v) => v > 0 ? '+$v' : '$v';

  @override
  Widget build(BuildContext context) {
    final answered = _correct != null;
    final right = _correct == true;

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 28),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        decoration: BoxDecoration(
          color: AppColors.wood,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (answered
                    ? (right ? AppColors.favorable : AppColors.unfavorable)
                    : AppColors.gold)
                .withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology_alt_outlined,
                color: AppColors.gold, size: 32),
            const SizedBox(height: 8),
            const Text(
              'COUNT CHECK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              answered
                  ? (right
                      ? 'Spot on — keep it going.'
                      : 'The running count is ${_signed(widget.check.answer)}. '
                          'Pick it up from there.')
                  : 'What is the running count right now?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: answered
                    ? (right ? AppColors.favorable : AppColors.unfavorable)
                    : AppColors.neutral,
                fontSize: 13.5,
                fontWeight: answered ? FontWeight.w800 : FontWeight.w500,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove,
                  onTap: answered ? null : () => setState(() => _guess--),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    _signed(_guess),
                    key: const ValueKey('count-check-guess'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StepButton(
                  icon: Icons.add,
                  onTap: answered ? null : () => setState(() => _guess++),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (!answered) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _close,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      child: const Text('SKIP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: answered ? _close : _submit,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(answered ? 'BACK TO THE TABLE' : 'CHECK'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: onTap == null ? 0.1 : 0.3),
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.goldDim),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon,
              color: onTap == null ? Colors.white24 : AppColors.gold, size: 24),
        ),
      ),
    );
  }
}

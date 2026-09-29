import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

class InsurancePrompt extends ConsumerWidget {
  const InsurancePrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(tableProvider.notifier);
    final state = ref.watch(tableProvider);
    final bet = state.currentBet;
    final insuranceCost = bet ~/ 2;
    final showCount = ref.watch(showCountProvider);
    final tc = state.trueCount;
    final tcText =
        tc >= 0 ? '+${tc.toStringAsFixed(1)}' : tc.toStringAsFixed(1);

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          decoration: BoxDecoration(
            color: AppColors.wood,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, color: AppColors.gold, size: 34),
              const SizedBox(height: 10),
              const Text(
                'INSURANCE?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Dealer shows Ace\nInsurance costs \$$insuranceCost — pays 2:1 if dealer has Blackjack',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.neutral, fontSize: 13),
              ),
              const SizedBox(height: 12),
              // The first and most valuable count-based play there is. Flat
              // basic strategy says never insure; a counter insures at a true
              // count of +3 or higher. The live count is only shown when the
              // HUD is on — otherwise this would hand a hidden-count player
              // the answer.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  showCount
                      ? 'Counter\'s rule: insure at true count +3 or higher. '
                          'True count now $tcText.'
                      : 'Counter\'s rule: insure at true count +3 or higher. '
                          'What is yours?',
                  key: const ValueKey('insurance-tip'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.gold.withValues(alpha: 0.9),
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        n.takeInsurance(false);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('NO THANKS'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: state.bankroll >= insuranceCost
                          ? () {
                              HapticFeedback.mediumImpact();
                              n.takeInsurance(true);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.gold,
                        foregroundColor: AppColors.wood,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'INSURE',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ads/ad_service.dart';
import '../../../core/models/game_state.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

/// Non-blocking floating banner that briefly shows the hand result then
/// auto-deals the next hand. The user can keep playing without ever tapping
/// "Next Hand" — to leave the table they use the back arrow in the top rail.
class ResultOverlay extends ConsumerStatefulWidget {
  const ResultOverlay({super.key});

  @override
  ConsumerState<ResultOverlay> createState() => _ResultOverlayState();
}

class _ResultOverlayState extends ConsumerState<ResultOverlay>
    with SingleTickerProviderStateMixin {
  static const _visibleDuration = Duration(milliseconds: 1500);

  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    HapticFeedback.mediumImpact();

    _autoTimer = Timer(_visibleDuration, () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (!mounted) return;
      ref.read(adServiceProvider).showInterstitialAfterHand();
      ref.read(tableProvider.notifier).nextHand();
    });
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tableProvider);
    final multi = state.playerHands.length > 1;
    // With a single hand the specific outcome (blackjack/push/…) is meaningful;
    // with several hands there is no single verdict, so summarise by net chips.
    final result = state.handResults.isNotEmpty ? state.handResults[0] : null;
    final (label, color, isWin) =
        multi ? _netDisplay(state.roundNet) : _resultDisplay(result);
    final icon = multi ? _netIcon(state.roundNet) : _resultIcon(result);

    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 70),
        child: Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.wood,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: color.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      color: color,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        color: isWin ? AppColors.gold : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    Text(
                      _netText(state),
                      style: TextStyle(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _resultIcon(GameResult? r) {
    switch (r) {
      case GameResult.blackjack:
        return Icons.auto_awesome;
      case GameResult.win:
      case GameResult.dealerBust:
        return Icons.trending_up;
      case GameResult.push:
        return Icons.horizontal_rule;
      case GameResult.loss:
      case GameResult.bust:
        return Icons.trending_down;
      default:
        return Icons.casino;
    }
  }

  IconData _netIcon(int net) {
    if (net > 0) return Icons.trending_up;
    if (net < 0) return Icons.trending_down;
    return Icons.horizontal_rule;
  }

  /// Aggregate verdict for a multi-hand round, based on net chips.
  (String, Color, bool) _netDisplay(int net) {
    if (net > 0) return ('YOU WIN', AppColors.favorable, true);
    if (net < 0) return ('YOU LOSE', AppColors.unfavorable, false);
    return ('PUSH', AppColors.neutral, false);
  }

  (String, Color, bool) _resultDisplay(GameResult? result) {
    switch (result) {
      case GameResult.blackjack:
        return ('BLACKJACK!', AppColors.gold, true);
      case GameResult.win:
        return ('YOU WIN', AppColors.favorable, true);
      case GameResult.dealerBust:
        return ('DEALER BUSTS', AppColors.favorable, true);
      case GameResult.push:
        return ('PUSH', AppColors.neutral, false);
      case GameResult.loss:
        return ('YOU LOSE', AppColors.unfavorable, false);
      case GameResult.bust:
        return ('BUST', AppColors.unfavorable, false);
      default:
        return ('—', AppColors.neutral, false);
    }
  }

  String _netText(GameState state) {
    // Authoritative net for the whole round (all hands + side + insurance),
    // computed by the engine at settlement.
    final net = state.roundNet;
    if (net > 0) return '+\$$net';
    if (net < 0) return '−\$${net.abs()}';
    return '\$0';
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../theme/app_theme.dart';
import '../table_provider.dart';

/// Shown when the player can no longer afford the minimum bet.
/// Offers a rewarded-ad simulation that grants chips, or a return to lobby.
class BrokeModal extends ConsumerStatefulWidget {
  static const int rewardAmount = 500;

  const BrokeModal({super.key});

  @override
  ConsumerState<BrokeModal> createState() => _BrokeModalState();
}

enum _AdState { idle, loading, rewarded }

class _BrokeModalState extends ConsumerState<BrokeModal>
    with SingleTickerProviderStateMixin {
  _AdState _adState = _AdState.idle;
  Timer? _adTimer;
  Timer? _dismissTimer;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _adTimer?.cancel();
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _watchAd() {
    if (_adState != _AdState.idle) return;
    HapticFeedback.mediumImpact();
    setState(() => _adState = _AdState.loading);

    // Simulated rewarded-ad playback (~2s).
    _adTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _adState = _AdState.rewarded);

      // Show the reward, fade out, then credit chips.
      // Crediting last avoids the parent yanking the modal mid-animation
      // (it's only mounted while bankroll < min bet).
      _dismissTimer = Timer(const Duration(milliseconds: 900), () async {
        if (!mounted) return;
        await _ctrl.reverse();
        if (!mounted) return;
        ref.read(tableProvider.notifier).addReward(BrokeModal.rewardAmount);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: ScaleTransition(
            scale: _scale,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
              decoration: BoxDecoration(
                color: AppColors.wood,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                  ),
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.18),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _buildContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_adState) {
      case _AdState.idle:
        return _idleView();
      case _AdState.loading:
        return _loadingView();
      case _AdState.rewarded:
        return _rewardedView();
    }
  }

  Widget _idleView() {
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.unfavorable.withValues(alpha: 0.15),
            border: Border.all(
              color: AppColors.unfavorable.withValues(alpha: 0.55),
              width: 1.5,
            ),
          ),
          child: const Icon(
            Icons.money_off_rounded,
            color: AppColors.unfavorable,
            size: 30,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'OUT OF CHIPS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You\'re below the minimum bet.\nWatch a short ad to get back in the game.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _watchAd,
            icon: const Icon(Icons.play_circle_outline, size: 22),
            label: Text(
              'WATCH AD  (+\$${BrokeModal.rewardAmount})',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.wood,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'BACK TO LOBBY',
              style: TextStyle(letterSpacing: 1.5, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _loadingView() {
    return Column(
      key: const ValueKey('loading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation(AppColors.gold),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'LOADING AD…',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Reward incoming',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _rewardedView() {
    return Column(
      key: const ValueKey('rewarded'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold.withValues(alpha: 0.18),
            border: Border.all(color: AppColors.gold, width: 1.5),
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.gold,
            size: 34,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '+\$${BrokeModal.rewardAmount}',
          style: const TextStyle(
            color: AppColors.gold,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'CHIPS ADDED',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
          ),
        ),
      ],
    );
  }
}

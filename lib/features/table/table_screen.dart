import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/game_state.dart';
import '../../core/rules/rule_set.dart';
import '../../theme/app_theme.dart';
import '../online/widgets/felt_background.dart';
import '../strategy/strategy_chart_screen.dart';
import 'table_provider.dart';
import 'widgets/action_bar.dart';
import 'widgets/bet_panel.dart';
import 'widgets/broke_modal.dart';
import 'widgets/chip_stack.dart';
import 'widgets/count_check_prompt.dart';
import 'widgets/count_hud.dart';
import 'widgets/dealer_area.dart';
import 'widgets/insurance_prompt.dart';
import 'widgets/player_area.dart';
import 'widgets/result_overlay.dart';

const _minChipValue = 5;

class TableScreen extends ConsumerWidget {
  const TableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tableProvider);
    final notifier = ref.read(tableProvider.notifier);
    // A short landscape phone or the default desktop window has less vertical
    // room than a full-height phone. Keep the whole table usable there rather
    // than letting the fixed-size card rows push into the chip tray.
    final compactLayout = MediaQuery.sizeOf(context).height < 700;
    final countCheck = ref.watch(countCheckProvider);

    return Scaffold(
      backgroundColor: AppColors.table,
      body: FeltBackground(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Wood top rail
                  _TopRail(bankroll: state.bankroll),

                  // Felt play area
                  Expanded(
                    child: Column(
                      children: [
                        Flexible(
                          flex: 5,
                          child: DealerArea(compact: compactLayout),
                        ),
                        _FeltBanner(compact: compactLayout),
                        _TableChips(compact: compactLayout),
                        Flexible(
                          flex: 6,
                          child: PlayerArea(compact: compactLayout),
                        ),
                      ],
                    ),
                  ),

                  const _StrategyFeedbackBar(),

                  // Bottom controls (bet or action)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: _bottomControls(state, notifier),
                  ),
                ],
              ),
              if (state.phase == GamePhase.betting && state.freshShoe)
                const _NewShoeNotice(),
              if (state.insuranceState == InsuranceState.offered)
                const InsurancePrompt(),
              if (state.phase == GamePhase.result) const ResultOverlay(),
              if (state.phase == GamePhase.betting && countCheck != null)
                CountCheckPrompt(key: ValueKey(countCheck), check: countCheck)
              else if (state.phase == GamePhase.betting &&
                  state.bankroll < _minChipValue)
                const BrokeModal(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomControls(GameState state, TableNotifier notifier) {
    switch (state.phase) {
      case GamePhase.betting:
        return const BetPanel(key: ValueKey('bet'));
      case GamePhase.playerTurn:
        // No action bar while there is nothing to act on — every hand is a
        // natural, or the insurance question is still open. It used to build
        // regardless and throw reading a hand past the end of the list.
        if (!state.hasActiveHand ||
            state.insuranceState == InsuranceState.offered) {
          return const SizedBox.shrink(key: ValueKey('empty'));
        }
        return const ActionBar(key: ValueKey('action'));
      default:
        return const SizedBox.shrink(key: ValueKey('empty'));
    }
  }
}

/// A short note after the reshuffle. Anyone counting without the HUD needs to
/// hear that the count went back to zero, or every count after it is wrong.
class _NewShoeNotice extends StatelessWidget {
  const _NewShoeNotice();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.62),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 350),
          builder: (_, t, child) => Opacity(opacity: t, child: child),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.wood.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.autorenew, size: 15, color: AppColors.gold),
                SizedBox(width: 7),
                Text(
                  'NEW SHOE  ·  COUNT RESETS TO 0',
                  style: TextStyle(
                    color: AppColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopRail extends ConsumerWidget {
  final int bankroll;
  const _TopRail({required this.bankroll});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.wood,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border(
          bottom: BorderSide(
            color: AppColors.gold.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.arrow_back_ios,
                color: AppColors.gold, size: 20),
          ),
          const SizedBox(width: 10),
          // The HUD gives way on narrow phones rather than pushing the
          // bankroll off the rail.
          const Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: CountHud(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Strategy chart',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.grid_on_rounded,
                color: AppColors.gold, size: 20),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const StrategyChartScreen(),
            )),
          ),
          const SizedBox(width: 2),
          _BankrollPill(bankroll: bankroll),
        ],
      ),
    );
  }
}

class _BankrollPill extends StatelessWidget {
  final int bankroll;
  const _BankrollPill({required this.bankroll});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '\$ ',
            style: TextStyle(
              color: AppColors.gold,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: Text(
              _fmt(bankroll),
              key: ValueKey(bankroll),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int v) => formatChips(v);
}

/// Chips with thousands separators — "1,049", not "1.0k". A counter sizes
/// bets off this number, so it has to be exact; only past a million does it
/// abbreviate.
String formatChips(int v) {
  if (v.abs() >= 1000000) {
    return '${(v / 1000000).toStringAsFixed(2)}M';
  }
  final digits = v.abs().toString();
  final out = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// The rules printed on the felt, following the table actually being played.
///
/// This used to be fixed text — "Blackjack pays 3 to 2", "Dealer must hit on
/// soft 17" — so a player who picked the 6:5 or stand-on-soft-17 table was
/// shown the wrong rules on the felt in front of them.
class _FeltBanner extends ConsumerWidget {
  final bool compact;

  const _FeltBanner({this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(tableRulesProvider);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 2),
      child: Column(
        children: [
          SizedBox(
            height: compact ? 20 : 24,
            width: double.infinity,
            child: CustomPaint(
              painter: _ArcTextPainter(
                base: DefaultTextStyle.of(context).style,
                text: feltPayoutLine(rules),
                color: rules.isUnfavourable
                    ? AppColors.unfavorable.withValues(alpha: 0.85)
                    : AppColors.gold.withValues(alpha: 0.78),
                fontSize: compact ? 10.5 : 12,
              ),
            ),
          ),
          Text(
            feltRulesLine(rules),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 8.5,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// "BLACKJACK PAYS 3 TO 2" — or 6 TO 5, when that is the table.
String feltPayoutLine(RuleSet rules) =>
    'BLACKJACK PAYS ${rules.payoutLabel.replaceAll(':', ' TO ')}';

/// The dealer's soft-17 rule and the insurance line.
String feltRulesLine(RuleSet rules) => [
      rules.dealerHitsSoft17
          ? 'Dealer Must Hit on Soft 17'
          : 'Dealer Must Stand on All 17s',
      'Insurance Pays 2 to 1',
    ].join('   •   ');

/// Text set along a shallow arc, the way a table's payout line is printed
/// into the felt.
class _ArcTextPainter extends CustomPainter {
  /// The ambient text style, so the felt uses the app's font.
  final TextStyle base;
  final String text;
  final Color color;
  final double fontSize;

  _ArcTextPainter({
    required this.base,
    required this.text,
    required this.color,
    required this.fontSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final style = base.copyWith(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 2.2,
      decoration: TextDecoration.none,
    );
    final glyphs = [
      for (final ch in text.split(''))
        TextPainter(
          text: TextSpan(text: ch, style: style),
          textDirection: TextDirection.ltr,
        )..layout(),
    ];
    final total = glyphs.fold<double>(0, (w, g) => w + g.width);

    // A circle centred well above the text, so the line smiles gently toward
    // the player like the arc on a real layout.
    final radius = math.max(size.width * 2.2, total * 2.0);
    final centre = Offset(size.width / 2, size.height - radius - 2);
    var angle = math.pi / 2 + (total / 2) / radius;

    for (final g in glyphs) {
      final half = g.width / 2 / radius;
      angle -= half;
      final pos = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(angle - math.pi / 2);
      g.paint(canvas, Offset(-g.width / 2, -g.height));
      canvas.restore();
      angle -= half;
    }
  }

  @override
  bool shouldRepaint(_ArcTextPainter old) =>
      old.text != text || old.color != color || old.fontSize != fontSize;
}

/// On-felt betting circles — one per main betting spot plus a smaller circle
/// for the dealer-bust side bet. Always visible so the player can see *where*
/// their chips will land. Tap a circle to make it the active bet target.
class _TableChips extends ConsumerWidget {
  final bool compact;

  const _TableChips({this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotBets = ref.watch(tableProvider.select((s) => s.spotBets));
    final sideBet = ref.watch(tableProvider.select((s) => s.sideBet));
    final phase = ref.watch(tableProvider.select((s) => s.phase));
    final target = ref.watch(betTargetProvider);
    final activeSpot = ref.watch(activeSpotProvider);

    final count = spotBets.length;
    final canTap = phase == GamePhase.betting;
    // Shrink the circles as more spots share the felt width.
    final normalMainSize = count >= 3
        ? 78.0
        : count == 2
            ? 88.0
            : 96.0;
    final mainSize = compact ? normalMainSize * 0.78 : normalMainSize;
    final mainChip =
        compact ? (count >= 3 ? 13.0 : 16.0) : (count >= 3 ? 17.0 : 20.0);

    List<Widget> circles = [
      for (var i = 0; i < count; i++)
        _BettingCircle(
          amount: spotBets[i],
          size: mainSize,
          emptyLabel: 'BET',
          bottomLabel: count == 1 ? 'MAIN' : 'HAND ${i + 1}',
          borderColor: AppColors.gold,
          chipSize: mainChip,
          maxVisibleChips: 5,
          isActive: target == BetTarget.main && activeSpot == i,
          canTap: canTap,
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(activeSpotProvider.notifier).state = i;
            ref.read(betTargetProvider.notifier).state = BetTarget.main;
          },
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(top: compact ? 0 : 4, bottom: compact ? 0 : 2),
      child: SizedBox(
        height: compact ? 104 : 132,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in circles) ...[
                  c,
                  const SizedBox(width: 10),
                ],
                // Side bet circle — smaller "bonus" spot on the right.
                Padding(
                  padding: EdgeInsets.only(top: compact ? 4 : 6),
                  child: _BettingCircle(
                    amount: sideBet,
                    size: compact ? 46 : 58,
                    emptyLabel: 'BUST',
                    bottomLabel: 'SIDE',
                    borderColor: AppColors.unfavorable,
                    chipSize: compact ? 13 : 16,
                    maxVisibleChips: 3,
                    isActive: target == BetTarget.side,
                    canTap: canTap,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(betTargetProvider.notifier).state =
                          BetTarget.side;
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A casino-style betting spot painted on the felt: an outlined circle
/// (ringed in [borderColor]), with either an empty-state label or a stack
/// of chips inside, and a small caps label below.
///
/// During the betting phase the circle is tappable — tapping it makes it the
/// active spot for the next chip click.
class _BettingCircle extends StatelessWidget {
  final int amount;
  final double size;
  final String emptyLabel;
  final String bottomLabel;
  final Color borderColor;
  final double chipSize;
  final int maxVisibleChips;
  final bool isActive;
  final bool canTap;
  final VoidCallback onTap;

  const _BettingCircle({
    required this.amount,
    required this.size,
    required this.emptyLabel,
    required this.bottomLabel,
    required this.borderColor,
    required this.chipSize,
    required this.maxVisibleChips,
    required this.isActive,
    required this.canTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = canTap && isActive;

    return GestureDetector(
      onTap: canTap ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.22),
              border: Border.all(
                color: borderColor.withValues(alpha: highlight ? 0.95 : 0.5),
                width: highlight ? 2.5 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
                if (highlight)
                  BoxShadow(
                    color: borderColor.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
              ],
            ),
            alignment: Alignment.center,
            child: amount > 0
                ? ChipStack(
                    amount: amount,
                    chipSize: chipSize,
                    maxVisibleChips: maxVisibleChips,
                    showAmount: false,
                  )
                : Text(
                    emptyLabel,
                    style: TextStyle(
                      color: borderColor.withValues(alpha: 0.85),
                      fontSize: size * 0.11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 3),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            amount > 0 ? '$bottomLabel · \$$amount' : bottomLabel,
            style: TextStyle(
              color: amount > 0
                  ? borderColor
                  : Colors.white.withValues(alpha: 0.45),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              shadows: amount > 0
                  ? [
                      Shadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 3),
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// A quiet correction shown just above the controls after a misplay.
///
/// The whole premise of a trainer is that a wrong play gets named. It is
/// deliberately small and non-blocking: the hand carries on, and it clears
/// itself on the next decision or when the round ends.
class _StrategyFeedbackBar extends ConsumerWidget {
  const _StrategyFeedbackBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedback = ref.watch(strategyFeedbackProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: feedback == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              // Red marks a mistake across the app; the words stay white so
              // they read on the felt.
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  AppColors.error.withValues(alpha: 0.14),
                  Colors.black.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.school_outlined,
                      size: 16, color: AppColors.error),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      feedback.message,
                      key: const ValueKey('coach-feedback'),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

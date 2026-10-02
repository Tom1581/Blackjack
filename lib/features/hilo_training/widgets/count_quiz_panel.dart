import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../table/widgets/discard_tray.dart';
import '../hilo_game.dart';
import '../hilo_scoring.dart';
import '../hilo_text.dart';
import '../hilo_training_session.dart';

/// What the player has typed on the number pad: up to two digits and a sign.
class CountEntry {
  static const maxDigits = 2;

  final String digits;
  final bool negative;

  const CountEntry({this.digits = '', this.negative = false});

  bool get isEmpty => digits.isEmpty;

  int get value =>
      (negative ? -1 : 1) * (digits.isEmpty ? 0 : int.parse(digits));

  CountEntry type(int digit) {
    if (digits == '0') return CountEntry(digits: '$digit', negative: negative);
    if (digits.length >= maxDigits) return this;
    return CountEntry(digits: '$digits$digit', negative: negative);
  }

  CountEntry toggleSign() => CountEntry(digits: digits, negative: !negative);

  CountEntry backspace() => digits.isEmpty
      ? const CountEntry()
      : CountEntry(
          digits: digits.substring(0, digits.length - 1),
          negative: negative,
        );

  /// "+7", "−12", "0" — a minus sign shows as soon as it is pressed.
  String get display {
    final body = digits.isEmpty ? '0' : digits;
    if (negative) return '−$body';
    return value > 0 ? '+$body' : body;
  }
}

/// The two duel colours: gold for the first player, sky blue for the second.
const duelColors = [AppColors.gold, Color(0xFF5AB0FF)];

/// The wood panel every question screen sits in.
class _PanelFrame extends StatelessWidget {
  final Color edge;
  final List<Widget> children;

  const _PanelFrame({required this.edge, required this.children});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.wood,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: edge.withValues(alpha: 0.7), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Color color;
  final IconData icon;

  const _PanelHeader({
    required this.title,
    this.trailing,
    this.color = AppColors.gold,
    this.icon = Icons.psychology_alt_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color == AppColors.gold ? Colors.white : color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: TextStyle(
              color: AppColors.gold.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class _PanelButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Key? buttonKey;
  final Color color;

  const _PanelButton({
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.color = AppColors.gold,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        key: buttonKey,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: AppColors.wood,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 15,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

// ─── Asking ────────────────────────────────────────────────────────────────

/// The dealer's question: a number pad for the running count.
class CountKeypadPanel extends StatefulWidget {
  final String title;

  /// "3 / 10", or null.
  final String? progress;
  final String prompt;
  final Color accent;

  /// The answer clock, or null for none. The screen owns the real timeout;
  /// this only draws it.
  final Duration? limit;

  /// False while the clock is stopped (the app is away, a dialog is up).
  final bool clockRunning;

  /// Shown between the prompt and the entry — the decks-left hint for a
  /// true count.
  final Widget? extra;
  final ValueChanged<int> onSubmit;

  const CountKeypadPanel({
    super.key,
    required this.title,
    required this.onSubmit,
    this.progress,
    this.prompt = 'The dealer stops. What is the running count?',
    this.accent = AppColors.gold,
    this.limit,
    this.clockRunning = true,
    this.extra,
  });

  @override
  State<CountKeypadPanel> createState() => _CountKeypadPanelState();
}

class _CountKeypadPanelState extends State<CountKeypadPanel> {
  CountEntry _entry = const CountEntry();

  void _edit(CountEntry next) {
    HapticFeedback.selectionClick();
    setState(() => _entry = next);
  }

  static final _digitKeys = {
    for (var d = 0; d <= 9; d++) ...{
      LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + d): d,
      LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + d): d,
    },
  };

  /// A hardware keyboard works too: digits, minus for the sign, backspace,
  /// and Enter to check.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final digit = _digitKeys[key];
    if (digit != null) {
      _edit(_entry.type(digit));
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _edit(_entry.toggleSign());
    } else if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      _edit(_entry.backspace());
    } else if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter)) {
      widget.onSubmit(_entry.value);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final limit = widget.limit;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: _panel(limit),
    );
  }

  Widget _panel(Duration? limit) {
    final extra = widget.extra;
    return _PanelFrame(
      edge: widget.accent,
      children: [
        _PanelHeader(
          title: widget.title,
          trailing: widget.progress,
          color: widget.accent,
        ),
        if (limit != null) ...[
          const SizedBox(height: 10),
          AnswerClockBar(limit: limit, running: widget.clockRunning),
        ],
        const SizedBox(height: 10),
        Text(
          widget.prompt,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13.5,
            height: 1.35,
          ),
        ),
        if (extra != null) ...[
          const SizedBox(height: 10),
          extra,
        ],
        const SizedBox(height: 10),
        Container(
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.goldDim),
          ),
          child: Text(
            _entry.display,
            key: const ValueKey('hilo-entry'),
            style: TextStyle(
              color: _entry.isEmpty && !_entry.negative
                  ? Colors.white.withValues(alpha: 0.35)
                  : Colors.white,
              fontSize: 38,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ]) ...[
          Row(
            children: [
              for (final d in row) ...[
                _Key(
                  keyId: 'hilo-key-$d',
                  label: '$d',
                  onTap: () => _edit(_entry.type(d)),
                ),
                if (d != row.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            _Key(
              keyId: 'hilo-key-sign',
              label: '+/−',
              semantics: 'Change sign',
              highlighted: _entry.negative,
              onTap: () => _edit(_entry.toggleSign()),
            ),
            const SizedBox(width: 8),
            _Key(
              keyId: 'hilo-key-0',
              label: '0',
              onTap: () => _edit(_entry.type(0)),
            ),
            const SizedBox(width: 8),
            _Key(
              keyId: 'hilo-key-back',
              icon: Icons.backspace_outlined,
              semantics: 'Delete',
              onTap: () => _edit(_entry.backspace()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PanelButton(
          buttonKey: const ValueKey('hilo-check'),
          label: 'CHECK',
          color: widget.accent,
          onPressed: () => widget.onSubmit(_entry.value),
        ),
      ],
    );
  }
}

/// The answer clock running down: gold, then red for the last few seconds.
class AnswerClockBar extends StatefulWidget {
  final Duration limit;

  /// Stops the bar where it is; it carries on from there when true again.
  final bool running;

  const AnswerClockBar({super.key, required this.limit, this.running = true});

  @override
  State<AnswerClockBar> createState() => _AnswerClockBarState();
}

class _AnswerClockBarState extends State<AnswerClockBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.limit);

  @override
  void initState() {
    super.initState();
    if (widget.running) _ctrl.forward();
  }

  @override
  void didUpdateWidget(AnswerClockBar old) {
    super.didUpdateWidget(old);
    if (widget.running == old.running) return;
    widget.running ? _ctrl.forward() : _ctrl.stop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final left = 1 - _ctrl.value;
        final secondsLeft = (widget.limit.inMilliseconds * left / 1000).ceil();
        final urgent = left < 0.3;
        final color = urgent ? AppColors.error : AppColors.gold;
        return Row(
          children: [
            Icon(Icons.timer_outlined, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 7,
                  value: left,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 26,
              child: Text(
                '${secondsLeft}s',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The discard tray, large, for reading the decks left. Like the one on the
/// felt it carries no number: estimating is the skill.
class DecksLeftHint extends StatelessWidget {
  final double penetration;
  final int decks;

  const DecksLeftHint({
    super.key,
    required this.penetration,
    required this.decks,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        DiscardTray(penetration: penetration, decks: decks, height: 64),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            'A $decks-deck shoe. Read the discards to the nearest half '
            'deck; the rest is still to come.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Enter or space presses the panel's one button — for a hardware keyboard.
class _EnterToContinue extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;

  const _EnterToContinue({required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
            onPressed,
        const SingleActivator(LogicalKeyboardKey.numpadEnter,
            includeRepeats: false): onPressed,
        const SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
            onPressed,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

// ─── Duel hand-off ─────────────────────────────────────────────────────────

/// "Pass the phone": hides the first answer while the second player takes
/// over.
class HandoffPanel extends StatelessWidget {
  final String from;
  final String to;
  final Color toColor;
  final VoidCallback onReady;

  const HandoffPanel({
    super.key,
    required this.from,
    required this.to,
    required this.toColor,
    required this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return _EnterToContinue(onPressed: onReady, child: _panel());
  }

  Widget _panel() {
    return _PanelFrame(
      edge: toColor,
      children: [
        Icon(Icons.swap_horiz_rounded, color: toColor, size: 44),
        const SizedBox(height: 8),
        Text(
          'PASS THE PHONE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: toColor,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          to.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$from has locked in a count. $to, your turn — '
          '$from, no peeking.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.75),
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        _PanelButton(
          buttonKey: const ValueKey('hilo-ready'),
          label: 'I\'M READY',
          color: toColor,
          onPressed: onReady,
        ),
      ],
    );
  }
}

// ─── Verdicts ──────────────────────────────────────────────────────────────

/// The verdict on a one-player answer: right or wrong, the true count, the
/// points and what to do next.
class VerdictPanel extends StatelessWidget {
  final HiLoAnswer answer;

  /// The streak after this answer.
  final int streak;
  final String? progress;

  /// Survival: lives left and whether this answer cost one.
  final int? lives;
  final bool lifeLost;
  final int? newLevel;
  final String continueLabel;
  final VoidCallback onContinue;

  const VerdictPanel({
    super.key,
    required this.answer,
    required this.streak,
    required this.continueLabel,
    required this.onContinue,
    this.progress,
    this.lives,
    this.lifeLost = false,
    this.newLevel,
  });

  @override
  Widget build(BuildContext context) {
    final right = answer.correct;
    final color = right ? AppColors.success : AppColors.error;
    final title =
        right ? 'SPOT ON' : (answer.timedOut ? 'TIME\'S UP' : 'NOT QUITE');
    final pts = answer.points;
    final livesLeft = lives;
    final comboUp = right &&
        streak > 1 &&
        HiLoScoring.comboFor(streak) > HiLoScoring.comboFor(streak - 1);
    return _EnterToContinue(
      onPressed: onContinue,
      child: _panel(right, color, title, pts, livesLeft, comboUp),
    );
  }

  Widget _panel(
    bool right,
    Color color,
    String title,
    HiLoPoints pts,
    int? livesLeft,
    bool comboUp,
  ) {
    return _PanelFrame(
      edge: color,
      children: [
        _PanelHeader(title: 'COUNT CHECK', trailing: progress),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              right
                  ? Icons.check_circle_outline
                  : (answer.timedOut
                      ? Icons.timer_off_outlined
                      : Icons.highlight_off),
              color: color,
              size: 26,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          signedCount(answer.question.answer),
          key: const ValueKey('hilo-answer'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          answer.timedOut
              ? 'No answer in time'
              : right
                  ? 'Answered in ${seconds(answer.took)} s'
                  : 'You said ${signedCount(answer.given!)} · '
                      '${seconds(answer.took)} s',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (answer.trueCountAsked) ...[
          const SizedBox(height: 10),
          _TrueCountLine(answer: answer),
        ],
        if (pts.total > 0) ...[
          const SizedBox(height: 12),
          PointsBreakdown(points: pts),
        ],
        if (comboUp) ...[
          const SizedBox(height: 10),
          Center(child: _ComboUp(combo: HiLoScoring.comboFor(streak))),
        ],
        if (livesLeft != null) ...[
          const SizedBox(height: 12),
          LivesRow(lives: livesLeft, justLost: lifeLost),
        ],
        if (newLevel != null) ...[
          const SizedBox(height: 10),
          _LevelUpNote(level: newLevel!),
        ],
        const SizedBox(height: 10),
        Text(
          right ? comboNote(streak) : slipAdvice(answer),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: right
                ? Colors.white.withValues(alpha: 0.7)
                : AppColors.gold.withValues(alpha: 0.95),
            fontSize: 12.5,
            height: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _PanelButton(
          buttonKey: const ValueKey('hilo-continue'),
          label: continueLabel,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

/// "100 + 84 speed × 2 = 368", with the total popping in.
class PointsBreakdown extends StatelessWidget {
  final HiLoPoints points;

  const PointsBreakdown({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: Colors.white.withValues(alpha: 0.65),
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.4, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.elasticOut,
          builder: (_, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Text(
            '+${points.total}',
            key: const ValueKey('hilo-points'),
            style: const TextStyle(
              color: AppColors.goldLight,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              shadows: [Shadow(color: Color(0x99D4AF37), blurRadius: 12)],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          children: [
            if (points.base > 0) ...[
              Text('${points.base} count', style: muted),
              Text('+ ${points.speed} speed', style: muted),
              if (points.combo > 1) ComboChip(combo: points.combo, small: true),
            ],
            if (points.trueCount > 0)
              Text('+ ${points.trueCount} true count', style: muted),
          ],
        ),
      ],
    );
  }
}

/// "×3" with a flame; brighter as the multiplier climbs.
class ComboChip extends StatelessWidget {
  final int combo;
  final bool small;

  const ComboChip({super.key, required this.combo, this.small = false});

  @override
  Widget build(BuildContext context) {
    final hot = combo >= 3;
    final color = combo >= 4
        ? const Color(0xFFFF7A59)
        : (hot ? AppColors.goldLight : AppColors.gold);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.8)),
        boxShadow: hot
            ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department,
              size: small ? 13 : 15, color: color),
          const SizedBox(width: 2),
          Text(
            '×$combo',
            style: TextStyle(
              color: color,
              fontSize: small ? 11.5 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Survival's hearts. A heart just lost shrinks away.
class LivesRow extends StatelessWidget {
  final int lives;
  final bool justLost;
  final double size;

  const LivesRow({
    super.key,
    required this.lives,
    this.justLost = false,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < SurvivalLevel.lives; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: i == lives && justLost
                ? TweenAnimationBuilder<double>(
                    tween: Tween(begin: 1.4, end: 1),
                    duration: const Duration(milliseconds: 500),
                    builder: (_, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: Icon(Icons.heart_broken,
                        color: AppColors.error, size: size),
                  )
                : Icon(
                    i < lives ? Icons.favorite : Icons.favorite_border,
                    color: i < lives
                        ? AppColors.hearts
                        : Colors.white.withValues(alpha: 0.3),
                    size: size,
                  ),
          ),
      ],
    );
  }
}

/// The true count, judged, with the working shown.
class _TrueCountLine extends StatelessWidget {
  final HiLoAnswer answer;

  const _TrueCountLine({required this.answer});

  @override
  Widget build(BuildContext context) {
    final right = answer.trueCountCorrect == true;
    final given = answer.trueCountGiven;
    final color = right ? AppColors.success : AppColors.error;
    return Container(
      key: const ValueKey('hilo-true-count'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(right ? Icons.check_circle : Icons.cancel,
                  color: color, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  given == null
                      ? 'TRUE COUNT — no answer in time'
                      : 'TRUE COUNT ${signedCount(given)}',
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            trueCountWorking(answer),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// "COMBO ×3!" — the streak just reached a new multiplier.
class _ComboUp extends StatelessWidget {
  final int combo;
  const _ComboUp({required this.combo});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        key: const ValueKey('hilo-combo-up'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFF7A59), Color(0xFFFFB347)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF7A59).withValues(alpha: 0.5),
              blurRadius: 14,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department,
                size: 18, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'COMBO ×$combo!',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelUpNote extends StatelessWidget {
  final int level;
  const _LevelUpNote({required this.level});

  @override
  Widget build(BuildContext context) {
    final players = SurvivalLevel.playersFor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.6)),
      ),
      child: Text(
        'LEVEL $level — faster dealer, $players players',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.success,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Both duel answers side by side, once the second is in.
class DuelRevealPanel extends StatelessWidget {
  final HiLoResolution resolution;
  final List<HiLoPlayer> players;
  final String? progress;
  final String continueLabel;
  final VoidCallback onContinue;

  const DuelRevealPanel({
    super.key,
    required this.resolution,
    required this.players,
    required this.continueLabel,
    required this.onContinue,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return _EnterToContinue(onPressed: onContinue, child: _panel());
  }

  Widget _panel() {
    final count = resolution.answers.first.question.answer;
    return _PanelFrame(
      edge: AppColors.gold,
      children: [
        _PanelHeader(
          title: 'THE REVEAL',
          trailing: progress,
          icon: Icons.visibility_outlined,
        ),
        const SizedBox(height: 8),
        Text(
          'THE COUNT WAS',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
          ),
        ),
        Text(
          signedCount(count),
          key: const ValueKey('hilo-answer'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 44,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 0; i < players.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: _DuelSide(
                  name: players[i].name,
                  color: duelColors[i % duelColors.length],
                  answer: resolution.answers[i],
                  total: players[i].score,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _PanelButton(
          buttonKey: const ValueKey('hilo-continue'),
          label: continueLabel,
          onPressed: onContinue,
        ),
      ],
    );
  }
}

class _DuelSide extends StatelessWidget {
  final String name;
  final Color color;
  final HiLoAnswer answer;
  final int total;

  const _DuelSide({
    required this.name,
    required this.color,
    required this.answer,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final right = answer.correct;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                right ? Icons.check_circle : Icons.cancel,
                size: 18,
                color: right ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 4),
              Text(
                answer.timedOut ? '—' : signedCount(answer.given!),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            right ? '+${answer.points.total}' : '+0',
            style: TextStyle(
              color: right ? AppColors.goldLight : Colors.white38,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            '${points(total)} total',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String keyId;
  final String? label;
  final IconData? icon;
  final String? semantics;
  final bool highlighted;
  final VoidCallback onTap;

  const _Key({
    required this.keyId,
    required this.onTap,
    this.label,
    this.icon,
    this.semantics,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        label: semantics ?? label,
        excludeSemantics: true,
        child: Material(
          key: ValueKey(keyId),
          color: highlighted
              ? AppColors.gold.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: highlighted ? AppColors.gold : AppColors.goldDim,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Center(
                child: icon != null
                    ? Icon(icon, color: AppColors.gold, size: 22)
                    : Text(
                        label!,
                        style: TextStyle(
                          color: highlighted ? AppColors.gold : Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

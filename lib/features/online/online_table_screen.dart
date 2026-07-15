import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';
import '../../theme/app_theme.dart';
import '../table/widgets/card_widget.dart';
import '../table/widgets/chip_stack.dart';
import 'online_controller.dart';
import 'online_state.dart';
import 'widgets/felt_background.dart';

/// Renders and drives an online multiplayer table from an [OnlineController].
/// The controller is owned by this screen — started here and disposed on exit.
class OnlineTableScreen extends StatefulWidget {
  final OnlineController controller;
  const OnlineTableScreen({super.key, required this.controller});

  @override
  State<OnlineTableScreen> createState() => _OnlineTableScreenState();
}

class _OnlineTableScreenState extends State<OnlineTableScreen> {
  OnlineController get c => widget.controller;

  static const _chips = [5, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.start();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final table = c.table;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              if (c.conn == OnlineConn.error)
                const Expanded(child: _CenterMessage('Connection failed'))
              else if (c.tableFull)
                Expanded(
                  child: _CenterMessage(
                    'This table is full (${c.maxSeats}/${c.maxSeats}).\n'
                    'Go back and create or join another table.',
                  ),
                )
              else if (table == null)
                const Expanded(child: _Connecting())
              else ...[
                Expanded(child: _tableBody(table)),
                _controls(table),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _header() {
    final connected = c.conn == OnlineConn.connected;
    final seated = c.table?.seats.length ?? 0;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.woodLight, AppColors.wood],
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.gold.withValues(alpha: 0.45)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.arrow_back_ios, color: AppColors.gold, size: 20),
            ),
          ),
          _roomPill(),
          const Spacer(),
          _statusDot(connected),
          const SizedBox(width: 6),
          Icon(Icons.groups,
              size: 16, color: AppColors.gold.withValues(alpha: 0.8)),
          const SizedBox(width: 4),
          Text(
            '$seated/${c.maxSeats}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomPill() {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: c.roomCode));
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Room code ${c.roomCode} copied — share it!'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ROOM ',
              style: TextStyle(
                color: AppColors.gold.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            Text(
              c.roomCode,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy,
                size: 13, color: AppColors.gold.withValues(alpha: 0.75)),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(bool connected) {
    final color = connected ? AppColors.favorable : AppColors.gold;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6),
        ],
      ),
    );
  }

  // ─── Table body ─────────────────────────────────────────────────────────

  Widget _tableBody(OnlineTableState table) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          _dealerZone(table),
          const SizedBox(height: 14),
          const _OrnamentDivider(),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 12,
            children: [
              for (var i = 0; i < table.seats.length; i++)
                _SeatPod(
                  seat: table.seats[i],
                  phase: table.phase,
                  isActive: table.phase == OnlinePhase.playerTurns &&
                      table.activeSeat == i,
                  isMe: table.seats[i].id == c.clientId,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _dealerZone(OnlineTableState table) {
    final dealer = table.dealer;
    final revealed = table.phase == OnlinePhase.results;
    final hasCards = dealer.cards.isNotEmpty;
    final dealerValue = !hasCards
        ? 0
        : revealed
            ? dealer.revealAll().value
            : HandModel(cards: [dealer.cards.first]).value;

    return Column(
      children: [
        Text(
          'DEALER',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            letterSpacing: 4,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (!hasCards)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CardWidget(card: null, width: 60, animate: false),
              SizedBox(width: 6),
              CardWidget(card: null, width: 60, animate: false),
            ],
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final card in dealer.cards)
                CardWidget(card: card, width: 60, animate: false),
            ],
          ),
        if (hasCards) ...[
          const SizedBox(height: 6),
          _valueBadge(
            revealed ? '$dealerValue' : '$dealerValue + ?',
            bust: revealed && dealer.isBust,
          ),
        ],
      ],
    );
  }

  Widget _valueBadge(String text, {bool bust = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: bust
              ? AppColors.unfavorable.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Text(
          bust ? 'BUST' : text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  // ─── Bottom controls ────────────────────────────────────────────────────

  Widget _controls(OnlineTableState table) {
    switch (table.phase) {
      case OnlinePhase.betting:
        return _bettingControls(table);
      case OnlinePhase.playerTurns:
        return _turnControls(table);
      case OnlinePhase.results:
        return _resultsControls(table);
    }
  }

  Widget _barContainer(Widget child) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.woodLight, AppColors.wood],
          ),
          border: Border(
            top: BorderSide(color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        child: child,
      );

  Widget _bettingControls(OnlineTableState table) {
    final me = c.mySeat;
    final funded = table.seats.any((s) => s.bet > 0);
    return _barContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            me == null
                ? 'Joining…'
                : 'Your bet: \$${me.bet}   •   Balance: \$${me.bankroll}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final v in _chips) ...[
                _ChipButton(
                  value: v,
                  enabled: me != null && me.bet + v <= me.bankroll,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    c.placeBet(v);
                  },
                ),
                const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      (me != null && me.bet > 0) ? () => c.clearBet() : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('CLEAR'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _GoldButton(
                  label: c.isHost ? 'DEAL' : 'WAITING FOR HOST…',
                  enabled: c.isHost && funded,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    c.deal();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _turnControls(OnlineTableState table) {
    if (!c.isMyTurn) {
      final active = table.activeSeatOrNull;
      return _barContainer(
        SizedBox(
          height: 48,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(AppColors.gold),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  active == null
                      ? 'Dealing…'
                      : 'Waiting for ${active.name} to play…',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final me = c.mySeat;
    final canDouble =
        me != null && me.hand.cards.length == 2 && me.bankroll >= me.bet;
    return _barContainer(
      Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: 'STAND',
              icon: Icons.pan_tool_outlined,
              color: AppColors.btnStand,
              accent: const Color(0xFFFF8080),
              onTap: () {
                HapticFeedback.mediumImpact();
                c.stand();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              label: 'DOUBLE',
              icon: Icons.add_circle_outline,
              color: AppColors.btnDouble,
              accent: const Color(0xFF6FB0FF),
              enabled: canDouble,
              onTap: () {
                HapticFeedback.heavyImpact();
                c.doubleDown();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              label: 'HIT',
              icon: Icons.add,
              color: AppColors.btnHit,
              accent: const Color(0xFF7DE49A),
              onTap: () {
                HapticFeedback.mediumImpact();
                c.hit();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsControls(OnlineTableState table) {
    return _barContainer(
      c.isHost
          ? _GoldButton(
              label: 'NEXT ROUND',
              enabled: true,
              onTap: () {
                HapticFeedback.mediumImpact();
                c.nextRound();
              },
            )
          : const SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  'Waiting for host to deal the next round…',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}

// ─── Small building blocks ─────────────────────────────────────────────────

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.gold),
          const SizedBox(height: 16),
          Text(
            'Connecting to the table…',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  final String text;
  const _CenterMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline,
                color: AppColors.gold.withValues(alpha: 0.7), size: 30),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _GoldButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFE680), AppColors.gold, Color(0xFFB8860B)],
                )
              : null,
          color: enabled ? null : AppColors.goldDim.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.gold.withValues(alpha: 0.45),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? AppColors.wood : Colors.white38,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final int value;
  final bool enabled;
  final VoidCallback onTap;
  const _ChipButton({
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  static const _denomColors = {
    5: Color(0xFFCC2222),
    25: Color(0xFF1E6B32),
    50: Color(0xFF1155BB),
    100: Color(0xFF1A1A1A),
  };

  @override
  Widget build(BuildContext context) {
    final color = _denomColors[value] ?? AppColors.gold;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.3,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.35), width: 3),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                '$value',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.accent,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.3,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color.withValues(alpha: 0.92), color],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One player's seat: avatar, name, chips/cards, hand value, and round result.
class _SeatPod extends StatelessWidget {
  final OnlineSeat seat;
  final OnlinePhase phase;
  final bool isActive;
  final bool isMe;

  const _SeatPod({
    required this.seat,
    required this.phase,
    required this.isActive,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final (accent, glow) = _accent();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 158,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.black.withValues(alpha: isActive ? 0.42 : 0.28),
            Colors.black.withValues(alpha: 0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent, width: isActive ? 2 : 1.2),
        boxShadow: glow
            ? [BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 14)]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerRow(),
          const SizedBox(height: 8),
          SizedBox(height: 76, child: Center(child: _middle())),
          const SizedBox(height: 6),
          _statusChip(),
          if (isActive) ...[
            const SizedBox(height: 6),
            const _TurnBadge(),
          ],
        ],
      ),
    );
  }

  (Color, bool) _accent() {
    if (isActive) return (AppColors.gold, true);
    if (seat.result != null) {
      switch (seat.result!) {
        case GameResult.blackjack:
          return (AppColors.gold, true);
        case GameResult.win:
        case GameResult.dealerBust:
          return (AppColors.favorable, true);
        case GameResult.push:
          return (AppColors.neutral, false);
        case GameResult.loss:
        case GameResult.bust:
          return (AppColors.unfavorable, false);
      }
    }
    if (isMe) return (AppColors.gold.withValues(alpha: 0.5), false);
    return (Colors.white.withValues(alpha: 0.15), false);
  }

  Widget _headerRow() {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isMe ? AppColors.gold : AppColors.surface,
            border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.6), width: 1.3),
          ),
          alignment: Alignment.center,
          child: Text(
            seat.name.isEmpty ? '?' : seat.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: isMe ? AppColors.wood : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            isMe ? '${seat.name} (you)' : seat.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? AppColors.gold : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _middle() {
    if (seat.hand.cards.isNotEmpty) {
      return Wrap(
        spacing: 3,
        runSpacing: 3,
        alignment: WrapAlignment.center,
        children: [
          for (final card in seat.hand.cards)
            CardWidget(card: card, width: 40, animate: false),
        ],
      );
    }
    if (seat.bet > 0) {
      return ChipStack(
        amount: seat.bet,
        chipSize: 22,
        maxVisibleChips: 4,
        showAmount: false,
      );
    }
    return Text(
      'no bet',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.3),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _statusChip() {
    if (seat.result != null) {
      final (label, color) = _resultLabel(seat.result!);
      return _chip(label, color, filled: true);
    }
    if (seat.hand.cards.isNotEmpty) {
      final bust = seat.hand.isBust;
      return _chip(
        bust ? 'BUST' : '${seat.hand.value}',
        bust ? AppColors.unfavorable : Colors.black.withValues(alpha: 0.6),
        filled: true,
      );
    }
    return _chip(
      seat.bet > 0 ? 'BET \$${seat.bet}' : '—',
      seat.bet > 0 ? AppColors.gold : Colors.black.withValues(alpha: 0.4),
      filled: seat.bet > 0,
    );
  }

  Widget _chip(String label, Color color, {required bool filled}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled && color == AppColors.gold ? AppColors.wood : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      );

  (String, Color) _resultLabel(GameResult r) {
    switch (r) {
      case GameResult.blackjack:
        return ('BLACKJACK', AppColors.gold);
      case GameResult.win:
      case GameResult.dealerBust:
        return ('WIN', AppColors.favorable);
      case GameResult.push:
        return ('PUSH', AppColors.neutral);
      case GameResult.loss:
      case GameResult.bust:
        return ('LOSE', AppColors.unfavorable);
    }
  }
}

/// Bouncing "YOUR TURN" pill shown on the active seat.
class _TurnBadge extends StatefulWidget {
  const _TurnBadge();

  @override
  State<_TurnBadge> createState() => _TurnBadgeState();
}

class _TurnBadgeState extends State<_TurnBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
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
      builder: (_, child) => Transform.scale(
        scale: 1 + _ctrl.value * 0.06,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: AppColors.gold.withValues(alpha: 0.55), blurRadius: 12),
          ],
        ),
        child: const Text(
          'YOUR TURN',
          style: TextStyle(
            color: AppColors.wood,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

/// Thin gold divider with a center diamond, matching the lobby ornamentation.
class _OrnamentDivider extends StatelessWidget {
  const _OrnamentDivider();

  @override
  Widget build(BuildContext context) {
    Widget line(List<Color> colors) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
            ),
          ),
        );
    return Row(
      children: [
        line([
          AppColors.gold.withValues(alpha: 0),
          AppColors.gold.withValues(alpha: 0.5),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.diamond, size: 9, color: AppColors.gold),
        ),
        line([
          AppColors.gold.withValues(alpha: 0.5),
          AppColors.gold.withValues(alpha: 0),
        ]),
      ],
    );
  }
}

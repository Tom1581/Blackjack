import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/audio/sound_service.dart';
import '../../core/growth/share_messages.dart';
import '../../core/models/game_state.dart';
import '../../core/models/hand_model.dart';
import '../../theme/app_theme.dart';
import '../table/widgets/card_widget.dart';
import '../table/widgets/chip_stack.dart';
import 'online_controller.dart';
import 'online_state.dart';
import 'online_table_logic.dart';
import 'widgets/felt_background.dart';

/// Why the player left the online table. The entry screen uses this to decide
/// whether to hand them a fresh room code.
enum OnlineExit { normal, retryHost }

/// Renders and drives an online multiplayer table from an [OnlineController].
/// The controller is owned by this screen — started here and disposed on exit.
class OnlineTableScreen extends StatefulWidget {
  final OnlineController controller;
  const OnlineTableScreen({super.key, required this.controller});

  @override
  State<OnlineTableScreen> createState() => _OnlineTableScreenState();
}

class _OnlineTableScreenState extends State<OnlineTableScreen>
    with WidgetsBindingObserver {
  OnlineController get c => widget.controller;

  static const _chips = [5, 25, 50, 100];

  /// Redraws the countdowns between broadcasts.
  Timer? _ticker;

  // Sound is driven off state transitions, since a guest only ever learns
  // what happened by receiving a new table.
  OnlinePhase? _lastPhase;
  int _lastRound = -1;
  int _lastCardCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChange);
    c.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && c.clockLeft != null) setState(() {});
    });
  }

  void _onChange() {
    if (!mounted) return;
    _soundForNewState();
    setState(() {});
  }

  /// Compare the table we just received with the one we had and play whatever
  /// the difference sounds like.
  void _soundForNewState() {
    final table = c.table;
    if (table == null) return;

    if (table.round != _lastRound) {
      _lastRound = table.round;
      _lastCardCount = 0;
      _lastPhase = null;
    }

    var cards = table.dealer.cards.length;
    for (final seat in table.seats) {
      for (final hand in seat.hands) {
        cards += hand.hand.cards.length;
      }
    }
    if (cards > _lastCardCount && _lastCardCount >= 0) {
      if (_lastCardCount != 0 || cards > 0) SoundService.play(Sfx.card);
    }
    _lastCardCount = cards;

    if (table.phase != _lastPhase) {
      if (table.phase == OnlinePhase.results) {
        final me = c.mySeat;
        if (me != null && me.inRound) {
          final blackjack = me.hands
              .any((h) => h.result == GameResult.blackjack);
          if (blackjack) {
            SoundService.play(Sfx.blackjack);
          } else if (me.netLastRound > 0) {
            SoundService.play(Sfx.win);
          } else if (me.netLastRound < 0) {
            SoundService.play(Sfx.lose);
          } else {
            SoundService.play(Sfx.push);
          }
        }
      }
      _lastPhase = table.phase;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the background is exactly when a broadcast may have
    // been missed, so ask the host for the table again rather than rendering
    // whatever was on screen when the phone locked.
    if (state == AppLifecycleState.resumed) c.requestResync();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  void _leave([OnlineExit exit = OnlineExit.normal]) {
    Navigator.of(context).pop(exit);
  }

  Future<void> _shareRoom(BuildContext shareContext) async {
    final box = shareContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await Share.share(
      GrowthShareMessages.roomInvite(c.roomCode),
      subject: 'Join my Hi-Lo Blackjack table',
      sharePositionOrigin: origin,
    );
  }

  void _copyRoomCode() {
    Clipboard.setData(ClipboardData(text: c.roomCode));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Room code ${c.roomCode} copied'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final table = c.table;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: FeltBackground(
          child: SafeArea(
            child: Column(
              children: [
                _header(),
                _clockBar(table),
                if (c.isBlocked)
                  Expanded(child: _blocked())
                else if (c.tableFull)
                  Expanded(
                    child: _Blocked(
                      icon: Icons.groups,
                      title: 'This table is full',
                      body: 'All ${c.maxSeats} seats are taken. Go back and '
                          'create your own table, or ask for another code.',
                      actionLabel: 'BACK',
                      onAction: _leave,
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
      ),
    );
  }

  // ─── Blocked states ─────────────────────────────────────────────────────

  Widget _blocked() {
    switch (c.conn) {
      case OnlineConn.noTable:
        return _Blocked(
          icon: Icons.search_off,
          title: 'No table with code ${c.roomCode}',
          body: 'Nobody is hosting that code. Check the spelling with your '
              'friend, or create a table of your own.',
          actionLabel: 'BACK',
          onAction: _leave,
        );
      case OnlineConn.hostGone:
        return _Blocked(
          icon: Icons.link_off,
          title: 'The host left',
          body: 'This table ran on their device, so the round cannot continue. '
              'Start a new table and share the code.',
          actionLabel: 'LEAVE TABLE',
          onAction: _leave,
        );
      case OnlineConn.versionMismatch:
        return _Blocked(
          icon: Icons.system_update,
          title: 'Update needed',
          body: 'Someone at this table is running a different version of the '
              'app. Update to the latest version to play together.',
          actionLabel: 'BACK',
          onAction: _leave,
        );
      case OnlineConn.codeTaken:
        return _Blocked(
          icon: Icons.shuffle,
          title: 'That code is taken',
          body: 'Another table is already using ${c.roomCode}. Grab a fresh '
              'code and try again.',
          actionLabel: 'GET A NEW CODE',
          onAction: () => _leave(OnlineExit.retryHost),
        );
      default:
        return _Blocked(
          icon: Icons.wifi_off,
          title: 'Connection failed',
          body: 'We could not reach the table. Check your internet connection '
              'and try again.',
          actionLabel: 'BACK',
          onAction: _leave,
        );
    }
  }

  // ─── Header ─────────────────────────────────────────────────────────────

  Widget _header() {
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
            onTap: _leave,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.arrow_back_ios, color: AppColors.gold, size: 20),
            ),
          ),
          _roomPill(),
          const Spacer(),
          _statusDot(),
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
    return Tooltip(
      message: 'Invite friends',
      child: GestureDetector(
        onTap: () => _shareRoom(context),
        onLongPress: _copyRoomCode,
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
                  letterSpacing: 2.5,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.ios_share,
                size: 13,
                color: AppColors.gold.withValues(alpha: 0.75),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusDot() {
    final live = c.conn == OnlineConn.connected && c.table != null;
    final color = live ? AppColors.favorable : AppColors.gold;
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

  /// Thin countdown rail under the header — the shared clock everyone sees.
  Widget _clockBar(OnlineTableState? table) {
    final left = c.clockLeft;
    if (table == null || left == null) return const SizedBox(height: 3);
    final total = switch (table.phase) {
      OnlinePhase.betting => OnlineTableLogic.bettingClock,
      OnlinePhase.insurance => OnlineTableLogic.insuranceClock,
      OnlinePhase.playerTurns => OnlineTableLogic.turnClock,
      OnlinePhase.results => OnlineTableLogic.resultsClock,
    };
    final frac =
        (left.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0).toDouble();
    final urgent = left.inSeconds <= 5;
    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        value: frac,
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        valueColor: AlwaysStoppedAnimation(
          urgent ? AppColors.unfavorable : AppColors.gold,
        ),
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
          const SizedBox(height: 10),
          _ShoeStrip(table: table),
          const SizedBox(height: 12),
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
                  canKick: c.isHost &&
                      table.seats[i].id != c.clientId &&
                      (table.phase == OnlinePhase.betting ||
                          table.phase == OnlinePhase.results),
                  onKick: () => _confirmKick(table.seats[i]),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _confirmKick(OnlineSeat seat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Remove ${seat.name}?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '${seat.name} will be sent back to the lobby. They can rejoin with '
          'the room code.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('REMOVE',
                style: TextStyle(color: AppColors.unfavorable)),
          ),
        ],
      ),
    );
    if (ok == true) c.kick(seat.id);
  }

  Widget _dealerZone(OnlineTableState table) {
    final dealer = table.dealer;
    final revealed = table.phase == OnlinePhase.results;
    final hasCards = dealer.cards.isNotEmpty;

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
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
            // Until the hole card turns over, the dealer's own rank never
            // leaves the host — but the host's own copy of the table still
            // holds it, so the badge counts only face-up cards or the host's
            // screen gives the hole card away.
            revealed ? '${dealer.value}' : '${dealer.visibleValue} + ?',
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
      case OnlinePhase.insurance:
        return _insuranceControls(table);
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
            top: BorderSide(
                color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
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

  String get _seconds {
    final left = c.clockLeft;
    return left == null ? '' : ' ${left.inSeconds}s';
  }

  Widget _bettingControls(OnlineTableState table) {
    final me = c.mySeat;

    if (c.canRebuy) {
      return _barContainer(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You are out of chips',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Buy back in and keep playing with the table.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 12),
            _GoldButton(
              label: 'BUY IN FOR \$${OnlineTableLogic.rebuyAmount}',
              enabled: true,
              onTap: () {
                HapticFeedback.mediumImpact();
                c.rebuy();
              },
            ),
          ],
        ),
      );
    }

    final waiting = table.seats.where((s) => s.connected && !s.ready).length;
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
          const SizedBox(height: 2),
          Text(
            waiting == 0
                ? 'Everyone is ready'
                : '$waiting still betting$_seconds',
            style: TextStyle(
              color: AppColors.gold.withValues(alpha: 0.85),
              fontSize: 11.5,
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
                    SoundService.play(Sfx.chip);
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
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('CLEAR'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: me == null
                      ? null
                      : () {
                          HapticFeedback.lightImpact();
                          c.setReady(!me.ready);
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        me?.ready == true ? AppColors.favorable : Colors.white70,
                    side: BorderSide(
                      color: me?.ready == true
                          ? AppColors.favorable
                          : Colors.white24,
                    ),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(me?.ready == true ? 'READY ✓' : 'READY'),
                ),
              ),
              if (c.isHost) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _GoldButton(
                    label: 'DEAL',
                    enabled: c.canDeal,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      c.deal();
                    },
                  ),
                ),
              ],
            ],
          ),
          if (!c.isHost) ...[
            const SizedBox(height: 8),
            Text(
              'The host deals when everyone is ready.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _insuranceControls(OnlineTableState table) {
    final me = c.mySeat;
    if (!c.needsInsurance) {
      return _barContainer(
        _WaitingRow(
          label: me?.inRound == true
              ? 'Waiting for the other players…'
              : 'Insurance is being offered…',
        ),
      );
    }
    final cost = (me?.bet ?? 0) ~/ 2;
    final affordable = me != null && me.bankroll >= cost && cost > 0;
    return _barContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Dealer shows an Ace — insurance?$_seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Costs \$$cost and pays 2:1 if the dealer has blackjack.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    c.takeInsurance(false);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(0, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('NO THANKS'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GoldButton(
                  label: 'INSURE \$$cost',
                  enabled: affordable,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    c.takeInsurance(true);
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
        _WaitingRow(
          label: active == null
              ? 'Dealing…'
              : 'Waiting for ${active.name}…$_seconds',
        ),
      );
    }
    final me = c.mySeat!;
    final label = me.isSplit
        ? 'Your turn — hand ${me.activeHand + 1} of ${me.hands.length}$_seconds'
        : 'Your turn$_seconds';
    return _barContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.gold.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
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
              const SizedBox(width: 7),
              Expanded(
                child: _ActionButton(
                  label: 'DOUBLE',
                  icon: Icons.add_circle_outline,
                  color: AppColors.btnDouble,
                  accent: const Color(0xFF6FB0FF),
                  enabled: c.canDouble,
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    c.doubleDown();
                  },
                ),
              ),
              if (c.canSplit) ...[
                const SizedBox(width: 7),
                Expanded(
                  child: _ActionButton(
                    label: 'SPLIT',
                    icon: Icons.call_split,
                    color: AppColors.btnSplit,
                    accent: const Color(0xFFE0B0FF),
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      c.split();
                    },
                  ),
                ),
              ],
              const SizedBox(width: 7),
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
        ],
      ),
    );
  }

  Widget _resultsControls(OnlineTableState table) {
    final me = c.mySeat;
    final net = me?.netLastRound ?? 0;
    final showNet = me != null && me.inRound;
    return _barContainer(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showNet) ...[
            Text(
              net > 0
                  ? '+\$$net this round'
                  : net < 0
                      ? '−\$${net.abs()} this round'
                      : 'Push — bet returned',
              style: TextStyle(
                color: net > 0
                    ? AppColors.favorable
                    : net < 0
                        ? AppColors.unfavorable
                        : AppColors.neutral,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Balance: \$${me.bankroll}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          c.isHost
              ? _GoldButton(
                  label: 'NEXT ROUND$_seconds',
                  enabled: true,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    c.nextRound();
                  },
                )
              : _WaitingRow(label: 'Next round starts automatically$_seconds'),
        ],
      ),
    );
  }
}

// ─── Small building blocks ─────────────────────────────────────────────────

class _WaitingRow extends StatelessWidget {
  final String label;
  const _WaitingRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
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

/// A dead end the player has to act on, with the one action that resolves it.
class _Blocked extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const _Blocked({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.gold.withValues(alpha: 0.8), size: 40),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 220,
              child: _GoldButton(
                label: actionLabel,
                enabled: true,
                onTap: onAction,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared shoe telemetry — the counting HUD, but for the whole table.
class _ShoeStrip extends StatelessWidget {
  final OnlineTableState table;
  const _ShoeStrip({required this.table});

  @override
  Widget build(BuildContext context) {
    if (table.totalCards == 0) return const SizedBox.shrink();
    final tc = table.trueCount;
    final color = tc >= 2
        ? AppColors.favorable
        : tc <= -1
            ? AppColors.unfavorable
            : AppColors.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stat('RC', table.runningCount > 0
              ? '+${table.runningCount}'
              : '${table.runningCount}', color),
          _divider(),
          _stat('TC', tc.toStringAsFixed(1), color),
          _divider(),
          _stat(
            'SHOE',
            '${(table.penetration * 100).round()}%',
            Colors.white.withValues(alpha: 0.85),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white.withValues(alpha: 0.15),
      );

  Widget _stat(String label, String value, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      );
}

/// One player's seat: avatar, name, chips/cards, hand values, and results.
class _SeatPod extends StatelessWidget {
  final OnlineSeat seat;
  final OnlinePhase phase;
  final bool isActive;
  final bool isMe;
  final bool canKick;
  final VoidCallback onKick;

  const _SeatPod({
    required this.seat,
    required this.phase,
    required this.isActive,
    required this.isMe,
    required this.canKick,
    required this.onKick,
  });

  @override
  Widget build(BuildContext context) {
    final (accent, glow) = _accent();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 156,
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
      child: Opacity(
        opacity: seat.connected ? 1 : 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _headerRow(),
            const SizedBox(height: 8),
            SizedBox(height: 88, child: Center(child: _middle())),
            const SizedBox(height: 6),
            _statusRow(),
            if (isActive) ...[
              const SizedBox(height: 6),
              const _TurnBadge(),
            ],
          ],
        ),
      ),
    );
  }

  (Color, bool) _accent() {
    if (isActive) return (AppColors.gold, true);
    if (!seat.connected) return (Colors.white.withValues(alpha: 0.12), false);
    final results = [
      for (final h in seat.hands)
        if (h.result != null) h.result!,
    ];
    if (results.isNotEmpty) {
      // With split hands the pod takes the colour of the best outcome.
      if (results.contains(GameResult.blackjack)) return (AppColors.gold, true);
      if (results.contains(GameResult.win) ||
          results.contains(GameResult.dealerBust)) {
        return (AppColors.favorable, true);
      }
      if (results.contains(GameResult.push)) return (AppColors.neutral, false);
      return (AppColors.unfavorable, false);
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
        if (!seat.connected)
          Icon(Icons.cloud_off,
              size: 13, color: Colors.white.withValues(alpha: 0.5))
        else if (canKick)
          GestureDetector(
            onTap: onKick,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.person_remove_alt_1,
                size: 14, color: Colors.white.withValues(alpha: 0.35)),
          ),
      ],
    );
  }

  Widget _middle() {
    if (seat.hands.isNotEmpty) {
      final cardWidth = seat.hands.length > 2 ? 30.0 : 38.0;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < seat.hands.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              _HandColumn(
                seatHand: seat.hands[i],
                cardWidth: cardWidth,
                highlighted: seat.isSplit && i == seat.activeHand && isActive,
                showLabel: seat.isSplit,
                index: i,
              ),
            ],
          ],
        ),
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
      seat.connected ? 'no bet' : 'away',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.3),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _statusRow() {
    final chips = <Widget>[];

    if (seat.insuranceBet > 0) {
      chips.add(_chip('INS \$${seat.insuranceBet}', AppColors.neutral,
          filled: false));
    }

    if (phase == OnlinePhase.results && seat.inRound) {
      final net = seat.netLastRound;
      chips.add(_chip(
        net > 0 ? '+\$$net' : net < 0 ? '−\$${net.abs()}' : 'PUSH',
        net > 0
            ? AppColors.favorable
            : net < 0
                ? AppColors.unfavorable
                : AppColors.neutral,
        filled: true,
      ));
    } else if (seat.hands.isEmpty) {
      if (seat.bet > 0) {
        chips.add(_chip('BET \$${seat.bet}', AppColors.gold, filled: true));
      } else if (phase == OnlinePhase.betting && seat.ready) {
        chips.add(_chip('SITTING OUT', AppColors.neutral, filled: false));
      } else {
        chips.add(_chip('—', Colors.black.withValues(alpha: 0.4),
            filled: false));
      }
    }

    if (phase == OnlinePhase.betting && seat.ready && seat.bet > 0) {
      chips.add(_chip('READY', AppColors.favorable, filled: false));
    }

    if (chips.isEmpty) return const SizedBox(height: 4);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: chips,
    );
  }

  Widget _chip(String label, Color color, {required bool filled}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.8)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                filled && color == AppColors.gold ? AppColors.wood : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

/// One hand inside a seat pod — cards, its value, and its own result.
class _HandColumn extends StatelessWidget {
  final SeatHand seatHand;
  final double cardWidth;
  final bool highlighted;
  final bool showLabel;
  final int index;

  const _HandColumn({
    required this.seatHand,
    required this.cardWidth,
    required this.highlighted,
    required this.showLabel,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final hand = seatHand.hand;
    final result = seatHand.result;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      decoration: highlighted
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.75)),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'H${index + 1}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            alignment: WrapAlignment.center,
            children: [
              for (final card in hand.cards)
                CardWidget(card: card, width: cardWidth, animate: false),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            result != null
                ? _resultLabel(result)
                : hand.isBust
                    ? 'BUST'
                    : '${hand.value}',
            style: TextStyle(
              color: _valueColor(result, hand),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Color _valueColor(GameResult? result, HandModel hand) {
    if (result != null) {
      switch (result) {
        case GameResult.blackjack:
          return AppColors.gold;
        case GameResult.win:
        case GameResult.dealerBust:
          return AppColors.favorable;
        case GameResult.push:
        case GameResult.surrender:
          return AppColors.neutral;
        case GameResult.loss:
        case GameResult.bust:
          return AppColors.unfavorable;
      }
    }
    return hand.isBust ? AppColors.unfavorable : Colors.white;
  }

  String _resultLabel(GameResult r) {
    switch (r) {
      case GameResult.blackjack:
        return 'BJ 3:2';
      case GameResult.win:
      case GameResult.dealerBust:
        return 'WIN';
      case GameResult.push:
        return 'PUSH';
      case GameResult.loss:
        return 'LOSE';
      case GameResult.bust:
        return 'BUST';
      case GameResult.surrender:
        return 'SURR';
    }
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
          textAlign: TextAlign.center,
          style: TextStyle(
            color: enabled ? AppColors.wood : Colors.white38,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
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
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.35), width: 3),
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
              Icon(icon, color: accent, size: 19),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            BoxShadow(
                color: AppColors.gold.withValues(alpha: 0.55), blurRadius: 12),
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

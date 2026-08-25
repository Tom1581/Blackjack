import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lobby/table_directory.dart';
import 'online_state.dart';
import 'online_table_logic.dart';
import 'transport/realtime_transport.dart';

enum OnlineConn {
  connecting,

  /// Subscribed and receiving table state.
  connected,

  /// We joined the channel but nobody is hosting this code — almost always a
  /// mistyped or long-finished room.
  noTable,

  /// We were playing and the host vanished. The table cannot continue.
  hostGone,

  /// Somebody at this table is running a different build of the app.
  versionMismatch,

  /// Only while creating: this code is already hosted, so pick another.
  codeTaken,

  error,
}

/// Drives one client's participation in an online table. The **host** owns the
/// authoritative [OnlineTableLogic] and broadcasts state after every change;
/// **guests** send action intents and render the host's broadcast state.
///
/// A [ChangeNotifier] so the UI can rebuild on every table update.
class OnlineController extends ChangeNotifier {
  final RealtimeTransport transport;
  final bool isHost;
  final String roomCode;
  final String playerName;

  /// How often the host re-sends the table even when nothing changed. Doubles
  /// as the guests' "the host is still alive" signal and as the repair path
  /// for a broadcast that got dropped in transit.
  final Duration heartbeat;

  /// The host runs the phase clocks on this cadence.
  final Duration tickInterval;

  /// A guest that hears nothing in this long gives up on the room code.
  final Duration joinTimeout;

  /// A guest that has been playing and then hears nothing this long treats the
  /// host as gone.
  final Duration hostSilence;

  /// A new host listens this long for an existing table before claiming the
  /// code, so two hosts can never run the same room.
  final Duration hostProbe;

  /// Presence can flicker while a client reconnects, so the host dropping off
  /// the roster only ends the table if they stay gone this long.
  final Duration hostAbsentGrace;

  /// Second channel used to advertise this table in the lobby. Host only, and
  /// only when [listPublicly]; null means this table is invite-by-code.
  final RealtimeTransport? lobbyTransport;

  /// Whether this table should appear in the lobby's open-tables list.
  final bool listPublicly;

  OnlineTableLogic? _logic; // host only
  OnlineTableState? table;
  OnlineConn conn = OnlineConn.connecting;
  Object? error;

  StreamSubscription<TransportMessage>? _msgSub;
  StreamSubscription<List<PresenceMember>>? _presSub;
  Timer? _heartbeatTimer;
  Timer? _tickTimer;
  Timer? _joinTimer;
  Timer? _watchdog;
  Timer? _probeTimer;
  bool _disposed = false;
  bool _claimed = false;
  LobbyAnnouncer? _announcer;

  /// The client the table's broadcasts must come from. Pinned to whoever sent
  /// the first valid state, so a second "host" on the same code — or any peer
  /// forging a state message — cannot take over a guest's screen.
  String? _pinnedHost;

  int _lastSeq = -1;
  int _outSeq = 0;
  DateTime? _lastStateAt;

  /// Wall-clock instant the current phase clock expires, derived from the
  /// duration the host sent. Kept locally so the countdown stays smooth
  /// between broadcasts and survives clock skew between devices.
  DateTime? _clockEndsAt;

  OnlineController({
    required this.transport,
    required this.isHost,
    required this.roomCode,
    required this.playerName,
    this.heartbeat = const Duration(milliseconds: 2500),
    this.tickInterval = const Duration(seconds: 1),
    this.joinTimeout = const Duration(seconds: 8),
    this.hostSilence = const Duration(seconds: 10),
    this.hostProbe = const Duration(milliseconds: 1200),
    this.hostAbsentGrace = const Duration(seconds: 3),
    this.lobbyTransport,
    this.listPublicly = true,
  });

  String get clientId => transport.clientId;

  int get maxSeats => OnlineTableLogic.maxSeats;

  bool get isMyTurn =>
      table != null &&
      table!.phase == OnlinePhase.playerTurns &&
      table!.isActivePlayer(clientId);

  OnlineSeat? get mySeat => table?.seatById(clientId);

  /// The hand I am being asked to play right now, if any.
  SeatHand? get myHand => isMyTurn ? mySeat?.currentHand : null;

  bool get canDouble {
    final seat = mySeat;
    final hand = myHand;
    if (seat == null || hand == null) return false;
    return OnlineTableLogic.canDoubleHand(seat, hand);
  }

  bool get canSplit {
    final seat = mySeat;
    final hand = myHand;
    if (seat == null || hand == null) return false;
    return OnlineTableLogic.canSplitHand(seat, hand);
  }

  /// True while I still owe the table an insurance answer.
  bool get needsInsurance {
    final t = table;
    final seat = mySeat;
    if (t == null || seat == null) return false;
    return t.phase == OnlinePhase.insurance &&
        seat.inRound &&
        !seat.insuranceAnswered;
  }

  bool get canRebuy {
    final seat = mySeat;
    return table?.phase == OnlinePhase.betting &&
        seat != null &&
        seat.bankroll < OnlineTableLogic.minBet &&
        !seat.inRound;
  }

  /// Whether the host's DEAL button should be live.
  bool get canDeal => _logic?.canDeal ?? false;

  /// Time left on the current phase clock, counted down locally.
  Duration? get clockLeft {
    final end = _clockEndsAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// True once we've received a table state that has no room for us — i.e. the
  /// table is full. The UI uses this to tell the player to join or create
  /// another table instead of waiting forever.
  bool get tableFull =>
      table != null &&
      mySeat == null &&
      table!.seats.length >= OnlineTableLogic.maxSeats;

  /// A terminal state the player has to act on, rather than a live table.
  bool get isBlocked =>
      conn == OnlineConn.noTable ||
      conn == OnlineConn.hostGone ||
      conn == OnlineConn.versionMismatch ||
      conn == OnlineConn.codeTaken ||
      conn == OnlineConn.error;

  Future<void> start() async {
    _msgSub = transport.messages.listen(_onMessage);
    _presSub = transport.presence.listen(_onPresence);
    try {
      await transport.join(roomCode, {'id': clientId, 'name': playerName});
      if (_disposed) return;
      conn = OnlineConn.connected;

      if (isHost) {
        // Listen briefly before claiming the code. If somebody is already
        // hosting it, we back off instead of running a second, conflicting
        // table on the same channel.
        _probeTimer = Timer(hostProbe, _claimTable);
      } else {
        _joinTimer = Timer(joinTimeout, () {
          if (_disposed || table != null) return;
          conn = OnlineConn.noTable;
          _safeNotify();
        });
      }
      _safeNotify();
    } catch (e) {
      error = e;
      conn = OnlineConn.error;
      _safeNotify();
    }
  }

  /// Become the host: build the authoritative table and start broadcasting.
  void _claimTable() {
    if (_disposed || _claimed || conn == OnlineConn.codeTaken) return;
    _claimed = true;
    final logic = OnlineTableLogic(roomCode: roomCode, hostId: clientId);
    logic.addPlayer(clientId, playerName);
    _logic = logic;
    final lobby = lobbyTransport;
    if (listPublicly && lobby != null) _announcer = LobbyAnnouncer(lobby);
    // Seat anyone who arrived during the probe window.
    for (final id in _earlyArrivals.keys) {
      logic.addPlayer(id, _earlyArrivals[id]!);
    }
    _earlyArrivals.clear();
    _heartbeatTimer = Timer.periodic(heartbeat, (_) => _pushHostState());
    _tickTimer = Timer.periodic(tickInterval, (_) {
      final before = logic.state;
      final after = logic.tick();
      // Every tick re-derives the countdown, so object identity always
      // differs. Broadcast only when the tick actually changed the game —
      // guests run the countdown locally between heartbeats.
      if (before.phase != after.phase ||
          before.activeSeat != after.activeSeat ||
          before.round != after.round ||
          !identical(before.seats, after.seats)) {
        _pushHostState();
      }
    });
    _pushHostState();
  }

  final Map<String, String> _earlyArrivals = {};

  // ─── Public actions (routed to the host) ────────────────────────────────

  void placeBet(int amount) => _act('bet', amount: amount);
  void clearBet() => _act('clearBet');
  void setReady(bool ready) => _act(ready ? 'ready' : 'unready');
  void rebuy() => _act('rebuy');
  void hit() => _act('hit');
  void stand() => _act('stand');
  void doubleDown() => _act('double');
  void split() => _act('split');
  void takeInsurance(bool take) => _act(take ? 'insure' : 'declineInsurance');

  /// Host-only: deal the round / start the next one / remove a player.
  void deal() => _hostOnly((l) => l.startDeal(clientId));
  void nextRound() => _hostOnly((l) => l.nextRound(clientId));
  void kick(String playerId) => _hostOnly((l) => l.kick(clientId, playerId));

  void _hostOnly(void Function(OnlineTableLogic) action) {
    final logic = _logic;
    if (!isHost || logic == null) return;
    action(logic);
    _pushHostState();
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  void _act(String action, {int? amount}) {
    if (isHost) {
      _applyIntent(clientId, action, amount);
    } else {
      transport.send('intent', {
        'action': action,
        if (amount != null) 'amount': amount,
      });
    }
  }

  void _onMessage(TransportMessage m) {
    if (_disposed) return;
    if (isHost) {
      switch (m.event) {
        case 'intent':
          // The actor is the transport's sender, never a value the message
          // body claims — otherwise any client could act as any player.
          _applyIntent(
            m.senderId,
            m.payload['action'] as String?,
            m.payload['amount'] as int?,
          );
        case 'requestState':
          _pushHostState();
        case 'state':
          // Another client is hosting this room code. We are not the table.
          if (!_claimed && m.senderId != clientId) {
            conn = OnlineConn.codeTaken;
            _probeTimer?.cancel();
            _safeNotify();
          }
      }
      return;
    }

    if (m.event != 'state') return;

    // Only the pinned host may drive this screen.
    if (_pinnedHost != null && m.senderId != _pinnedHost) return;

    // Only a client claiming to be this table's host can tell us we are out of
    // date — otherwise any peer could push everyone to an "update" screen.
    if (m.payload['hostId'] != m.senderId) return;

    final version = m.payload['v'] as int? ?? 1;
    if (version != onlineWireVersion) {
      conn = OnlineConn.versionMismatch;
      _safeNotify();
      return;
    }

    final OnlineTableState next;
    try {
      next = OnlineTableState.fromJson(m.payload);
    } catch (_) {
      return; // Malformed — ignore rather than crash the table.
    }
    // A stale or replayed broadcast can never rewind what we already have.
    if (next.seq <= _lastSeq) return;

    _pinnedHost ??= m.senderId;
    _lastSeq = next.seq;
    _lastStateAt = DateTime.now();
    _joinTimer?.cancel();
    table = next;
    _applyClock(next.clockMs);
    if (conn != OnlineConn.versionMismatch) conn = OnlineConn.connected;
    _armHostWatchdog();
    _safeNotify();
  }

  void _applyIntent(String from, String? action, int? amount) {
    final logic = _logic;
    if (logic == null || action == null) return;
    if (logic.state.seatById(from) == null) return;
    switch (action) {
      case 'bet':
        logic.placeBet(from, amount ?? 0);
      case 'clearBet':
        logic.clearBet(from);
      case 'ready':
        logic.setReady(from, true);
      case 'unready':
        logic.setReady(from, false);
      case 'rebuy':
        logic.rebuy(from);
      case 'hit':
        logic.hit(from);
      case 'stand':
        logic.stand(from);
      case 'double':
        logic.doubleDown(from);
      case 'split':
        logic.split(from);
      case 'insure':
        logic.answerInsurance(from, true);
      case 'declineInsurance':
        logic.answerInsurance(from, false);
      default:
        return;
    }
    _pushHostState();
  }

  void _onPresence(List<PresenceMember> members) {
    if (_disposed) return;
    final present = <String, String>{
      for (final m in members)
        m.clientId: (m.data['name'] as String? ?? 'Player'),
    };

    if (!isHost) {
      // Presence is the fastest "the host left" signal, but it is also the
      // noisiest — a reconnecting client can briefly vanish from the roster.
      // Shorten the watchdog instead of ending the table on one bad sync; a
      // state broadcast arriving in the meantime re-arms it as normal.
      final host = _pinnedHost ?? table?.hostId;
      if (host != null && members.isNotEmpty && !present.containsKey(host)) {
        _watchdog?.cancel();
        _watchdog = Timer(hostAbsentGrace, () {
          if (_disposed || isHost) return;
          conn = OnlineConn.hostGone;
          _safeNotify();
        });
      }
      return;
    }

    final logic = _logic;
    if (logic == null) {
      // Still probing — remember who is here so nobody is missed.
      _earlyArrivals.addAll(present);
      return;
    }

    present.forEach(logic.addPlayer);
    // A player who drops keeps their seat and chips for a grace period.
    for (final seat in logic.state.seats) {
      if (seat.id == clientId) continue;
      if (!present.containsKey(seat.id) && seat.connected) {
        logic.markDisconnected(seat.id);
      }
    }
    _pushHostState();
  }

  void _armHostWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(hostSilence, () {
      if (_disposed || isHost) return;
      final last = _lastStateAt;
      if (last == null) return;
      if (DateTime.now().difference(last) >= hostSilence) {
        conn = OnlineConn.hostGone;
        _safeNotify();
      }
    });
  }

  void _applyClock(int? ms) {
    _clockEndsAt =
        ms == null ? null : DateTime.now().add(Duration(milliseconds: ms));
  }

  void _pushHostState() {
    final logic = _logic;
    if (logic == null || _disposed) return;
    logic.refreshClock();
    table = logic.state.copyWith(seq: ++_outSeq);
    logic.state = table!;
    _applyClock(table!.clockMs);
    _safeNotify();
    transport.send('state', table!.toJson());
    _announceTable();
  }

  /// Keep the lobby advert in step with the table. [LobbyAnnouncer.announce]
  /// ignores an unchanged listing, so calling this on every broadcast costs
  /// nothing when nothing has moved.
  void _announceTable() {
    final announcer = _announcer;
    final t = table;
    if (announcer == null || t == null) return;
    announcer.announce(TableListing(
      code: roomCode,
      hostName: playerName,
      seated: t.seats.where((s) => s.connected).length,
      maxSeats: maxSeats,
      phase: t.phase,
      round: t.round,
    ));
  }

  /// Ask the host to resend the table — used after the app comes back from the
  /// background, where a broadcast may have been missed entirely.
  void requestResync() {
    if (isHost) return;
    transport.send('requestState', const {});
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeatTimer?.cancel();
    _tickTimer?.cancel();
    _joinTimer?.cancel();
    _watchdog?.cancel();
    _probeTimer?.cancel();
    _msgSub?.cancel();
    _presSub?.cancel();
    _announcer?.stop();
    transport.leave();
    super.dispose();
  }
}

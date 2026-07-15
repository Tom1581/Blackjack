import 'dart:async';

import 'package:flutter/foundation.dart';

import 'online_state.dart';
import 'online_table_logic.dart';
import 'transport/realtime_transport.dart';

enum OnlineConn { connecting, connected, error }

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

  OnlineTableLogic? _logic; // host only
  OnlineTableState? table;
  OnlineConn conn = OnlineConn.connecting;
  Object? error;

  StreamSubscription<TransportMessage>? _msgSub;
  StreamSubscription<List<PresenceMember>>? _presSub;
  bool _disposed = false;

  OnlineController({
    required this.transport,
    required this.isHost,
    required this.roomCode,
    required this.playerName,
  });

  String get clientId => transport.clientId;

  int get maxSeats => OnlineTableLogic.maxSeats;

  bool get isMyTurn =>
      table != null &&
      table!.phase == OnlinePhase.playerTurns &&
      table!.isActivePlayer(clientId);

  OnlineSeat? get mySeat => table?.seatById(clientId);

  /// True once we've received a table state that has no room for us — i.e. the
  /// table is full. The UI uses this to tell the player to join or create
  /// another table instead of waiting forever.
  bool get tableFull =>
      table != null &&
      mySeat == null &&
      table!.seats.length >= OnlineTableLogic.maxSeats;

  Future<void> start() async {
    _msgSub = transport.messages.listen(_onMessage);
    _presSub = transport.presence.listen(_onPresence);
    try {
      if (isHost) {
        _logic = OnlineTableLogic(roomCode: roomCode, hostId: clientId);
        _logic!.addPlayer(clientId, playerName);
        table = _logic!.state;
      }
      await transport.join(roomCode, {'id': clientId, 'name': playerName});
      conn = OnlineConn.connected;
      if (isHost) _broadcast();
      _safeNotify();
    } catch (e) {
      error = e;
      conn = OnlineConn.error;
      _safeNotify();
    }
  }

  // ─── Public actions (routed to the host) ────────────────────────────────

  void placeBet(int amount) => _act('bet', amount: amount);
  void clearBet() => _act('clearBet');
  void hit() => _act('hit');
  void stand() => _act('stand');
  void doubleDown() => _act('double');

  /// Host-only: deal the round / start the next one.
  void deal() {
    if (!isHost || _logic == null) return;
    _logic!.startDeal(clientId);
    _pushHostState();
  }

  void nextRound() {
    if (!isHost || _logic == null) return;
    _logic!.nextRound(clientId);
    _pushHostState();
  }

  // ─── Internals ──────────────────────────────────────────────────────────

  void _act(String action, {int? amount}) {
    final payload = <String, dynamic>{
      'from': clientId,
      'action': action,
      if (amount != null) 'amount': amount,
    };
    if (isHost) {
      _applyIntent(payload);
    } else {
      transport.send('intent', payload);
    }
  }

  void _onMessage(TransportMessage m) {
    if (isHost) {
      if (m.event == 'intent') _applyIntent(m.payload);
    } else if (m.event == 'state') {
      table = OnlineTableState.fromJson(m.payload);
      _safeNotify();
    }
  }

  void _applyIntent(Map<String, dynamic> payload) {
    final logic = _logic;
    if (logic == null) return;
    final from = payload['from'] as String?;
    final action = payload['action'] as String?;
    if (from == null || action == null) return;
    final amount = payload['amount'] as int?;
    switch (action) {
      case 'bet':
        logic.placeBet(from, amount ?? 0);
        break;
      case 'clearBet':
        logic.clearBet(from);
        break;
      case 'hit':
        logic.hit(from);
        break;
      case 'stand':
        logic.stand(from);
        break;
      case 'double':
        logic.doubleDown(from);
        break;
      default:
        return;
    }
    _pushHostState();
  }

  void _onPresence(List<PresenceMember> members) {
    final logic = _logic;
    if (!isHost || logic == null) return;
    final present = <String, String>{
      for (final m in members) m.clientId: (m.data['name'] as String? ?? 'Player'),
    };
    present.forEach(logic.addPlayer);
    // Drop seats whose player disconnected — but never the host's own seat.
    final gone = logic.state.seats
        .map((s) => s.id)
        .where((id) => id != clientId && !present.containsKey(id))
        .toList();
    for (final id in gone) {
      logic.removePlayer(id);
    }
    _pushHostState();
  }

  void _pushHostState() {
    final logic = _logic;
    if (logic == null) return;
    table = logic.state;
    _safeNotify();
    _broadcast();
  }

  void _broadcast() {
    final t = table;
    if (t != null) transport.send('state', t.toJson());
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _msgSub?.cancel();
    _presSub?.cancel();
    transport.leave();
    super.dispose();
  }
}

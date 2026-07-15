import 'dart:async';

import 'package:blackjack_app/features/online/transport/realtime_transport.dart';

/// An in-memory stand-in for Supabase Realtime used in tests. All transports
/// created from the same [InMemoryBroker] and joining the same room code
/// exchange broadcast messages and share presence — exactly like a real
/// channel, but with no network. Broadcasts follow the `self: false` rule (a
/// sender never receives its own message).
class InMemoryBroker {
  final Map<String, List<InMemoryTransport>> _rooms = {};

  InMemoryTransport createClient(String clientId) =>
      InMemoryTransport._(this, clientId);

  void _register(String room, InMemoryTransport t) {
    _rooms.putIfAbsent(room, () => []).add(t);
    _emitPresence(room);
  }

  void _unregister(String room, InMemoryTransport t) {
    _rooms[room]?.remove(t);
    _emitPresence(room);
  }

  void _broadcast(String room, InMemoryTransport from, TransportMessage msg) {
    for (final t in _rooms[room] ?? const <InMemoryTransport>[]) {
      if (t != from) t._deliver(msg);
    }
  }

  void _emitPresence(String room) {
    final clients = _rooms[room] ?? const <InMemoryTransport>[];
    final members = [
      for (final c in clients) PresenceMember(c.clientId, c._presenceData),
    ];
    for (final c in clients) {
      c._deliverPresence(List<PresenceMember>.from(members));
    }
  }
}

class InMemoryTransport implements RealtimeTransport {
  final InMemoryBroker _broker;
  @override
  final String clientId;

  String? _room;
  Map<String, dynamic> _presenceData = const {};
  final _messages = StreamController<TransportMessage>.broadcast();
  final _presence = StreamController<List<PresenceMember>>.broadcast();

  InMemoryTransport._(this._broker, this.clientId);

  @override
  Stream<TransportMessage> get messages => _messages.stream;

  @override
  Stream<List<PresenceMember>> get presence => _presence.stream;

  @override
  Future<void> join(String roomCode, Map<String, dynamic> presenceData) async {
    _room = roomCode;
    _presenceData = presenceData;
    _broker._register(roomCode, this);
  }

  @override
  Future<void> send(String event, Map<String, dynamic> payload) async {
    final room = _room;
    if (room == null) return;
    _broker._broadcast(room, this, TransportMessage(event, payload));
  }

  void _deliver(TransportMessage msg) {
    if (!_messages.isClosed) _messages.add(msg);
  }

  void _deliverPresence(List<PresenceMember> members) {
    if (!_presence.isClosed) _presence.add(members);
  }

  @override
  Future<void> leave() async {
    final room = _room;
    _room = null;
    if (room != null) _broker._unregister(room, this);
    await _messages.close();
    await _presence.close();
  }
}

/// Flush pending microtasks/timers so queued transport messages propagate.
Future<void> flush([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

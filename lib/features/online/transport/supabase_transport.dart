import 'dart:async';

import 'package:supabase/supabase.dart';

import 'realtime_transport.dart';

/// Supabase Realtime implementation of [RealtimeTransport]. Uses a Broadcast
/// channel (one per room code) for game messages and Presence for the roster.
/// Every channel is private: a signed-in account must first be admitted to the
/// room by the database. Broadcast writes are allowed only for admitted room
/// members by the Realtime RLS policy.
///
/// Deliberately imports the pure-Dart `supabase` package rather than
/// `supabase_flutter`, so the whole online stack can be driven against the
/// real service from a plain Dart script — see `tool/live_table_check.dart`.
class SupabaseTransport implements RealtimeTransport {
  final SupabaseClient _client;
  @override
  final String clientId;

  RealtimeChannel? _channel;
  final _messages = StreamController<TransportMessage>.broadcast();
  final _presence = StreamController<List<PresenceMember>>.broadcast();

  SupabaseTransport(this._client, this.clientId);

  @override
  Stream<TransportMessage> get messages => _messages.stream;

  @override
  Stream<List<PresenceMember>> get presence => _presence.stream;

  @override
  bool get usesServerStampedIdentity => false;

  static const _envelope = 'msg';

  static const _channelPrefix = 'bj_room_';

  /// Payload key naming the message kind ('state', 'intent', …).
  ///
  /// NOT `event`: Supabase Realtime overwrites `payload['event']` with the
  /// broadcast event name (always `msg` here) and adds its own `type`, so a
  /// message labelled with either key arrives relabelled and is dropped by the
  /// receiver. Those two names are reserved — do not use them in the payload.
  static const _kind = 'kind';

  /// Payload key naming the sender.
  static const _from = 'from';

  /// Payload key holding the message body.
  static const _data = 'data';

  /// Keys Supabase Realtime writes into a delivered broadcast payload itself.
  /// Anything we put under these names is overwritten in transit.
  static const reservedPayloadKeys = {'event', 'type'};

  @override
  Future<void> join(String roomCode, Map<String, dynamic> presenceData) async {
    if (_client.auth.currentUser == null) {
      throw StateError('Sign in before joining an online room.');
    }
    final channel = _client.channel(
      '$_channelPrefix$roomCode',
      opts: RealtimeChannelConfig(
        key: clientId,
        private: true,
      ),
    );

    channel.onBroadcast(
      event: _envelope,
      callback: (payload) {
        final message = decodeEnvelope(payload);
        if (message != null) _messages.add(message);
      },
    );

    void emitPresence(_) => _emitPresence(channel);
    channel
        .onPresenceSync(emitPresence)
        .onPresenceJoin(emitPresence)
        .onPresenceLeave(emitPresence);

    final subscribed = Completer<void>();
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!subscribed.isCompleted) subscribed.complete();
      } else if (error != null && !subscribed.isCompleted) {
        subscribed.completeError(error);
      }
    });

    await subscribed.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'Timed out joining Supabase Realtime.',
      ),
    );
    // Presence is only a liveness hint. The controller seats players from the
    // server-stamped memberJoined broadcast, never from this data.
    await channel.track({...presenceData, 'id': clientId});
    _channel = channel;
  }

  @override
  Future<void> updatePresence(Map<String, dynamic> presenceData) async {
    // Tracking again on a subscribed channel replaces this client's entry.
    await _channel?.track({...presenceData, 'id': clientId});
  }

  @override
  Future<void> send(String event, Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null) return;
    final response = await channel.sendBroadcastMessage(
      event: _envelope,
      payload: encodeEnvelope(event, payload, clientId),
    );
    if (response != ChannelResponse.ok) {
      throw StateError('Supabase Realtime rejected the game message.');
    }
  }

  /// Wrap a game message for the wire.
  static Map<String, dynamic> encodeEnvelope(
    String kind,
    Map<String, dynamic> data,
    String from,
  ) =>
      {_kind: kind, _from: from, _data: data};

  /// Unwrap a broadcast payload, or null if it is not one of ours.
  ///
  /// The incoming map is whatever Supabase delivers — our keys plus the
  /// service's own `event` and `type`. Database-originated broadcasts have
  /// one further wrapper: `{id, data: <our envelope>}`, which is accepted too
  /// for compatibility with retained/replayed database messages.
  static TransportMessage? decodeEnvelope(Map<String, dynamic> payload) {
    final wrapped = payload[_data];
    final envelope = payload[_kind] == null && wrapped is Map
        ? Map<String, dynamic>.from(wrapped)
        : payload;
    final kind = envelope[_kind] as String? ?? '';
    final from = envelope[_from] as String? ?? '';
    // Supabase never stamps a sender, so the envelope id is the best signal
    // available here. The host does the real check: an intent is only applied
    // if its sender actually holds a seat at the table.
    if (kind.isEmpty || from.isEmpty) return null;
    final data = envelope[_data];
    return TransportMessage(
      kind,
      data is Map ? Map<String, dynamic>.from(data) : const {},
      from,
    );
  }

  void _emitPresence(RealtimeChannel channel) {
    final members = <PresenceMember>[];
    for (final entry in channel.presenceState()) {
      for (final p in entry.presences) {
        final data = Map<String, dynamic>.from(p.payload);
        final id = data['id'] as String? ?? entry.key;
        members.add(PresenceMember(id, data));
      }
    }
    if (!_presence.isClosed) _presence.add(members);
  }

  @override
  Future<void> leave() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await channel.untrack();
      await _client.removeChannel(channel);
    }
    if (!_messages.isClosed) await _messages.close();
    if (!_presence.isClosed) await _presence.close();
  }
}

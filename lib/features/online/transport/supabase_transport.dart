import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'realtime_transport.dart';

/// Supabase Realtime implementation of [RealtimeTransport]. Uses a Broadcast
/// channel (one per room code) for game messages and Presence for the roster.
/// Works with the public/anon key alone — no tables, auth, or Edge Functions
/// required, so it stays comfortably inside the free tier.
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

  static const _channelPrefix = 'bj_room_';
  // Everything is wrapped in a single broadcast event so one listener suffices.
  static const _envelope = 'msg';

  @override
  Future<void> join(String roomCode, Map<String, dynamic> presenceData) async {
    final channel = _client.channel(
      '$_channelPrefix$roomCode',
      opts: RealtimeChannelConfig(key: clientId),
    );

    channel.onBroadcast(
      event: _envelope,
      callback: (payload) {
        final event = payload['event'] as String? ?? '';
        final data = payload['data'];
        _messages.add(TransportMessage(
          event,
          data is Map ? Map<String, dynamic>.from(data) : const {},
        ));
      },
    );

    void emitPresence(_) => _emitPresence(channel);
    channel
        .onPresenceSync(emitPresence)
        .onPresenceJoin(emitPresence)
        .onPresenceLeave(emitPresence);

    final completer = Completer<void>();
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track(presenceData);
        if (!completer.isCompleted) completer.complete();
      } else if (error != null && !completer.isCompleted) {
        completer.completeError(error);
      }
    });

    _channel = channel;
    return completer.future;
  }

  @override
  Future<void> send(String event, Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null) return;
    await channel.sendBroadcastMessage(
      event: _envelope,
      payload: {'event': event, 'data': payload},
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
    _presence.add(members);
  }

  @override
  Future<void> leave() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await channel.untrack();
      await _client.removeChannel(channel);
    }
    await _messages.close();
    await _presence.close();
  }
}

/// A broadcast message received on the room channel.
class TransportMessage {
  final String event;
  final Map<String, dynamic> payload;
  const TransportMessage(this.event, this.payload);
}

/// A connected member of the room, as reported by presence.
class PresenceMember {
  final String clientId;
  final Map<String, dynamic> data;
  const PresenceMember(this.clientId, this.data);
}

/// Abstraction over the realtime layer so the multiplayer controller can be
/// driven by either Supabase Realtime (production) or an in-memory broker
/// (tests). Nothing in the game loop depends on Supabase directly.
abstract class RealtimeTransport {
  /// Stable id of this client.
  String get clientId;

  /// Join a room channel and start tracking presence with [presenceData].
  /// Completes once the channel is subscribed.
  Future<void> join(String roomCode, Map<String, dynamic> presenceData);

  /// Broadcast an [event] with [payload] to the other clients on the channel.
  Future<void> send(String event, Map<String, dynamic> payload);

  /// Inbound broadcast messages from other clients.
  Stream<TransportMessage> get messages;

  /// Latest roster of connected members whenever presence changes.
  Stream<List<PresenceMember>> get presence;

  /// Leave the channel and release resources.
  Future<void> leave();
}

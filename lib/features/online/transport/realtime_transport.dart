/// A broadcast message received on the room channel.
class TransportMessage {
  final String event;
  final Map<String, dynamic> payload;

  /// Who the transport says sent this message.
  ///
  /// The game layer reads the actor from here and NEVER from the payload body,
  /// so a client cannot act as another player just by writing someone else's
  /// id into the message it sends.
  ///
  /// How strong this is depends on the transport:
  ///  * The in-memory broker used in tests reports the true sender.
  ///  * `SupabaseTransport` reports the id on the message envelope. Supabase
  ///    Broadcast relays a payload verbatim and does not stamp a sender, so a
  ///    deliberately modified client can still forge it. Routing every action
  ///    through this one field closes the accidental and casual cases and puts
  ///    the seam in one place; making it unforgeable needs a server-side dealer
  ///    with real auth, which is the documented upgrade path.
  final String senderId;

  const TransportMessage(this.event, this.payload, this.senderId);
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

  /// Whether this transport delivers membership messages with a sender id
  /// stamped by the server. The in-memory test transport is intentionally
  /// simple and keeps its existing presence-based seating behavior.
  bool get usesServerStampedIdentity => false;

  /// Join a room channel and start tracking presence with [presenceData].
  /// Completes once the channel is subscribed.
  Future<void> join(String roomCode, Map<String, dynamic> presenceData);

  /// Replace this client's presence entry, e.g. to keep a lobby listing
  /// current as seats fill up and the round moves on.
  Future<void> updatePresence(Map<String, dynamic> presenceData);

  /// Broadcast an [event] with [payload] to the other clients on the channel.
  Future<void> send(String event, Map<String, dynamic> payload);

  /// Inbound broadcast messages from other clients.
  Stream<TransportMessage> get messages;

  /// Latest roster of connected members whenever presence changes.
  Stream<List<PresenceMember>> get presence;

  /// Leave the channel and release resources.
  Future<void> leave();
}

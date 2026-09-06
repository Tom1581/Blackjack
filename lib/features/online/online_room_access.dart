import 'package:supabase/supabase.dart';

/// Authenticates an online player and grants their account access to a room
/// before the Realtime channel is opened.
///
/// The room database functions are deliberately the only path that can create
/// membership. Private Realtime policies then use that membership to decide
/// whether a socket may join, publish presence, or receive game traffic.
class OnlineRoomAccess {
  final SupabaseClient _client;

  const OnlineRoomAccess(this._client);

  /// A stable authenticated identity for this installation.
  Future<String> identify() async {
    final existing = _client.auth.currentUser;
    if (existing != null) return existing.id;

    final response = await _client.auth.signInAnonymously();
    final user = response.user;
    if (user == null) {
      throw const AuthException('Anonymous sign-in failed.');
    }
    return user.id;
  }

  /// Creates a room and seats its host before the host opens its channel.
  Future<void> create({
    required String roomCode,
    required String displayName,
    required bool listed,
  }) async {
    await _client.rpc('create_online_room', params: {
      'p_room_code': roomCode,
      'p_display_name': displayName,
      'p_listed': listed,
    });
  }

  /// Seats this authenticated account in an existing room.
  Future<void> join({
    required String roomCode,
    required String displayName,
  }) async {
    await _client.rpc('join_online_room', params: {
      'p_room_code': roomCode,
      'p_display_name': displayName,
    });
  }
}

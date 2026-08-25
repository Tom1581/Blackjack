import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase/supabase_service.dart';
import 'transport/realtime_transport.dart';
import 'transport/supabase_transport.dart';

/// Builds a [RealtimeTransport] for a given client id. Overridden in tests with
/// an in-memory broker so the whole online flow can run without a network.
typedef TransportFactory = RealtimeTransport Function(String clientId);

final transportFactoryProvider = Provider<TransportFactory>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (clientId) => SupabaseTransport(client, clientId);
});

/// Stable per-device player id (persisted). Used as the presence/seat key.
Future<String> loadOrCreatePlayerId() async {
  final prefs = await SharedPreferences.getInstance();
  var id = prefs.getString('online_player_id');
  if (id == null || id.isEmpty) {
    id = _randomId();
    await prefs.setString('online_player_id', id);
  }
  return id;
}

Future<String> loadPlayerName() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString('online_player_name');
  return (name == null || name.trim().isEmpty) ? '' : name;
}

Future<void> savePlayerName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('online_player_name', name.trim());
}

/// Length of a room code. Five characters over a 32-symbol alphabet is ~33.5M
/// codes — enough that two live tables colliding is not a practical concern,
/// and the host still probes the channel before claiming one.
const roomCodeLength = 5;

/// A short, human-friendly room code (unambiguous alphabet — no O/0, I/1).
String generateRoomCode([Random? rng]) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = rng ?? Random();
  return List.generate(
    roomCodeLength,
    (_) => alphabet[r.nextInt(alphabet.length)],
  ).join();
}

String _randomId() {
  final r = Random();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final body = List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  return 'p_${DateTime.now().millisecondsSinceEpoch}_$body';
}

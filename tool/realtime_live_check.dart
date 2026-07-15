// Live connectivity smoke check against the real Supabase Realtime service.
// Opens two independent clients (like two phones), subscribes both to one room
// channel, broadcasts from one, and requires the other to receive it — the same
// Broadcast mechanism the multiplayer feature uses.
//
// Run: dart run tool/realtime_live_check.dart
// Prints LIVE_REALTIME_ROUNDTRIP_OK and exits 0 on success.
import 'dart:async';
import 'dart:io';

import 'package:realtime_client/realtime_client.dart';

Future<void> main() async {
  const endpoint = 'wss://yktyobprlradqtvmqfki.supabase.co/realtime/v1';
  const key = 'sb_publishable_foYtDGPKyHV_wpdgjPcsjg_0x25jZMm';
  final topic = 'bj_room_LIVE${DateTime.now().millisecondsSinceEpoch % 100000}';

  final rx = RealtimeClient(endpoint, params: {'apikey': key});
  final tx = RealtimeClient(endpoint, params: {'apikey': key});
  final gotMessage = Completer<Map<String, dynamic>>();
  final gotPresence = Completer<void>();

  Future<void> subscribed(RealtimeChannel chan, String tag) {
    final done = Completer<void>();
    chan.subscribe((status, err) {
      stdout.writeln('$tag: $status ${err ?? ''}');
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!done.isCompleted) done.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        if (!done.isCompleted) done.completeError('$tag $status ${err ?? ''}');
      }
    });
    return done.future.timeout(const Duration(seconds: 20));
  }

  try {
    final rxChan = rx.channel(topic);
    rxChan.onBroadcast(
      event: 'msg',
      callback: (payload) {
        if (!gotMessage.isCompleted) gotMessage.complete(payload);
      },
    );
    rxChan.onPresenceSync((_) {
      for (final s in rxChan.presenceState()) {
        for (final p in s.presences) {
          if (p.payload['id'] == 'sender' && !gotPresence.isCompleted) {
            gotPresence.complete();
          }
        }
      }
    });
    await subscribed(rxChan, 'receiver');

    final txChan = tx.channel(topic);
    await subscribed(txChan, 'sender');

    // Let both channel joins settle.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // 1) Presence (used for seating): the sender tracks, the receiver must see it.
    await txChan.track({'id': 'sender', 'name': 'Bo'});
    await gotPresence.future.timeout(const Duration(seconds: 20));
    stdout.writeln('LIVE_PRESENCE_OK (receiver saw sender join)');

    // 2) Broadcast (used for game state + actions).
    await txChan.sendBroadcastMessage(
      event: 'msg',
      payload: {
        'event': 'state',
        'data': {'ping': 'pong'}
      },
    );
    stdout.writeln('sent broadcast on $topic');

    final msg = await gotMessage.future.timeout(const Duration(seconds: 20));
    stdout.writeln('RECEIVED: $msg');
    stdout.writeln('LIVE_REALTIME_ROUNDTRIP_OK');
    exit(0);
  } catch (e) {
    stderr.writeln('LIVE_REALTIME_FAILED: $e');
    exit(1);
  }
}

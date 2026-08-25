import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/transport/supabase_transport.dart';

void main() {
  group('The broadcast envelope survives what Supabase does to it', () {
    /// Reproduce a delivered broadcast: Supabase relays our payload but writes
    /// its own `event` (always the broadcast event name) and adds `type`.
    Map<String, dynamic> asDelivered(Map<String, dynamic> sent) => {
          ...sent,
          'event': 'msg',
          'type': 'broadcast',
        };

    test('a message round-trips through a delivered payload', () {
      final sent = SupabaseTransport.encodeEnvelope(
        'state',
        {'roomCode': 'ABCDE', 'seq': 4},
        'host-1',
      );
      final got = SupabaseTransport.decodeEnvelope(asDelivered(sent));

      expect(got, isNotNull);
      expect(got!.event, 'state',
          reason: 'the kind must survive the service relabelling the payload');
      expect(got.senderId, 'host-1');
      expect(got.payload['roomCode'], 'ABCDE');
      expect(got.payload['seq'], 4);
    });

    test('the envelope never uses a key Supabase overwrites', () {
      final sent = SupabaseTransport.encodeEnvelope('intent', {'a': 1}, 'g1');
      for (final reserved in SupabaseTransport.reservedPayloadKeys) {
        expect(
          sent.containsKey(reserved),
          isFalse,
          reason: 'payload["$reserved"] is rewritten in transit, so carrying '
              'our data there loses it — this exact bug silently dropped every '
              'message on the real transport while the in-memory tests passed',
        );
      }
    });

    test('an intent round-trips too', () {
      final sent = SupabaseTransport.encodeEnvelope(
        'intent',
        {'action': 'hit'},
        'guest-9',
      );
      final got = SupabaseTransport.decodeEnvelope(asDelivered(sent));
      expect(got!.event, 'intent');
      expect(got.payload['action'], 'hit');
      expect(got.senderId, 'guest-9');
    });

    test('a foreign or unlabelled broadcast is ignored, not misread', () {
      expect(
        SupabaseTransport.decodeEnvelope(
            {'event': 'msg', 'type': 'broadcast', 'hello': 'world'}),
        isNull,
      );
      // Missing sender.
      expect(
        SupabaseTransport.decodeEnvelope({'kind': 'state', 'data': {}}),
        isNull,
      );
      // Missing kind.
      expect(
        SupabaseTransport.decodeEnvelope({'from': 'x', 'data': {}}),
        isNull,
      );
    });

    test('a body that is not a map decodes to an empty payload', () {
      final got = SupabaseTransport.decodeEnvelope(
          {'kind': 'state', 'from': 'x', 'data': 'nonsense'});
      expect(got!.payload, isEmpty);
    });
  });
}

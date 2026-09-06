import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/online/online_providers.dart';

void main() {
  test('invite codes are long, unambiguous, and database-compatible', () {
    final code = generateRoomCode(Random(7));

    expect(code.length, roomCodeLength);
    expect(roomCodeLength, 10);
    expect(code, matches(RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$')));
  });
}

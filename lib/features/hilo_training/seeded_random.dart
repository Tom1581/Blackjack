import 'dart:math';

/// A small random generator (mulberry32) whose sequence is fixed by its seed
/// forever.
///
/// The Daily Challenge and friend challenge codes promise that everyone deals
/// the same shoe. `dart:math`'s [Random] only promises that within one SDK
/// build, so a Dart upgrade could quietly give two phones different deals.
/// This one is a few lines of integer arithmetic that no SDK can change.
class SeededRandom implements Random {
  int _state;

  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  static const _two32 = 0x100000000;

  /// The next 32 random bits.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;

  @override
  int nextInt(int max) {
    if (max <= 0 || max > _two32) {
      throw RangeError.range(max, 1, _two32, 'max');
    }
    // Reject the top sliver so every value is equally likely.
    final limit = (_two32 ~/ max) * max;
    while (true) {
      final r = nextUint32();
      if (r < limit) return r % max;
    }
  }

  @override
  double nextDouble() {
    final high = nextUint32() >> 5; // 27 bits
    final low = nextUint32() >> 6; // 26 bits
    return (high * 67108864 + low) / 9007199254740992;
  }

  @override
  bool nextBool() => nextUint32() & 1 == 1;
}

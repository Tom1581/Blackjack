/// How much to bet at a given true count: the "true count minus one" ramp.
///
/// One unit at +2 or below, then one unit less than the true count, capped
/// at [maxUnits] — +3 is two units, +4 three, +9 and up eight. It is the
/// simplest ramp that still captures most of a Hi-Lo counter's edge, and the
/// one most courses teach first. The true count is floored, as everywhere
/// else in the app: +3.9 is still +3.
class BetRamp {
  const BetRamp._();

  /// A 1–8 spread: the most a multi-deck counter can usually get away with.
  static const maxUnits = 8;

  static int units(double trueCount) {
    final floored = trueCount.floor();
    return (floored - 1).clamp(1, maxUnits);
  }

  /// Whether [bet] chips is exactly the ramp's bet in units of [unit].
  static bool matches(int bet, double trueCount, int unit) =>
      bet > 0 && bet % unit == 0 && bet ~/ unit == units(trueCount);
}

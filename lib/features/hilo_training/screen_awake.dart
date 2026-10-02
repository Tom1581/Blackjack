import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the screen on while a Hi-Lo Training game is dealing.
///
/// The player watches cards for a minute or more without touching the phone
/// — longer than many screen timeouts — so without this the phone would dim
/// and lock mid-shoe. It is switched off again whenever the game is paused,
/// finished, left or sent to the background.
class ScreenAwake {
  const ScreenAwake._();

  static bool _on = false;

  /// Whether the screen is being kept on.
  static bool get isOn => _on;

  /// Replaces the plugin, for tests.
  @visibleForTesting
  static void Function(bool on)? override;

  static Future<void> set(bool on) async {
    if (on == _on) return;
    _on = on;
    final o = override;
    if (o != null) {
      o(on);
      return;
    }
    try {
      await (on ? WakelockPlus.enable() : WakelockPlus.disable());
    } catch (error) {
      // A phone that cannot hold the screen on still plays; it just dims.
      debugPrint('Screen wake lock unavailable: $error');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _on = false;
    override = null;
  }
}

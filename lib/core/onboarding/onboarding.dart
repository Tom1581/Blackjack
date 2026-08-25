import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the player has been shown the intro.
class Onboarding {
  const Onboarding._();

  static const _kSeen = 'onboarding_seen_v1';

  /// Whether the intro has already run. Defaults to "seen" if preferences
  /// cannot be read, because showing the intro twice is worse than skipping it.
  static Future<bool> seen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kSeen) ?? false;
    } catch (error) {
      debugPrint('Could not read onboarding flag: $error');
      return true;
    }
  }

  static Future<void> markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSeen, true);
    } catch (_) {
      // Nothing to do — worst case the intro appears once more.
    }
  }

  @visibleForTesting
  static Future<void> resetForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSeen);
  }
}

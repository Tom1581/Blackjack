import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rule_set.dart';

/// Remembers which table the player is practising against.
class RulesStore {
  const RulesStore._();

  static const _kId = 'rule_set_id';

  static RuleSet _current = RuleSet.fallback;

  /// The selected rules. Defaults to what the app has always played, so an
  /// existing player who never opens the picker sees no change at all.
  static RuleSet get current => _current;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _current = RuleSet.byId(prefs.getString(_kId));
    } catch (error) {
      debugPrint('Could not read the rule set: $error');
      _current = RuleSet.fallback;
    }
  }

  static Future<void> select(RuleSet rules) async {
    _current = rules;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kId, rules.id);
    } catch (_) {
      // A preference we cannot persist is not worth failing over.
    }
  }

  @visibleForTesting
  static void resetForTest() => _current = RuleSet.fallback;
}

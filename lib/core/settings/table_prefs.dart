import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The table settings a player picks in the lobby, remembered across launches.
///
/// These used to live only in memory, so every restart quietly put the count
/// HUD back on, the shoe back to six decks and the table back to one hand —
/// exactly the settings a counter changes on purpose.
///
/// Values are plain types so this file does not depend on the table feature;
/// the providers in `table_provider.dart` seed themselves from here.
class TablePrefs {
  const TablePrefs._();

  static const _kShowCount = 'table_show_count';
  static const _kShoe = 'table_shoe_mode';
  static const _kSpots = 'table_spot_count';
  static const _kCountCheck = 'table_count_check';
  static const _kIndexPlays = 'table_index_plays';
  static const _kBetCoach = 'table_bet_coach';
  static const _kBetUnit = 'table_bet_unit';

  /// Betting units a player can pick for the bet-spread coach.
  static const betUnits = [5, 10, 25, 50, 100];

  static bool _showCount = true;
  static String? _shoe;
  static int _spots = 1;
  static bool _countCheck = true;
  static bool _indexPlays = false;
  static bool _betCoach = false;
  static int _betUnit = 25;

  static bool get showCount => _showCount;

  /// The saved shoe mode's name, or null for the default.
  static String? get shoe => _shoe;
  static int get spots => _spots;

  /// Whether the table quizzes the player on the running count while the HUD
  /// is hidden.
  static bool get countCheck => _countCheck;

  /// Whether the coach grades against the Illustrious 18 / Fab 4 index plays
  /// instead of basic strategy alone. Off by default: it is the last step of
  /// the curriculum, and wrong for anyone still learning the chart.
  static bool get indexPlays => _indexPlays;

  /// Whether the betting panel shows the bet the count calls for.
  static bool get betCoach => _betCoach;

  /// One betting unit, in chips.
  static int get betUnit => _betUnit;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showCount = prefs.getBool(_kShowCount) ?? true;
      _shoe = prefs.getString(_kShoe);
      _spots = (prefs.getInt(_kSpots) ?? 1).clamp(1, 3);
      _countCheck = prefs.getBool(_kCountCheck) ?? true;
      _indexPlays = prefs.getBool(_kIndexPlays) ?? false;
      _betCoach = prefs.getBool(_kBetCoach) ?? false;
      final unit = prefs.getInt(_kBetUnit) ?? 25;
      _betUnit = betUnits.contains(unit) ? unit : 25;
    } catch (error) {
      debugPrint('Could not read table settings: $error');
    }
  }

  static Future<void> setShowCount(bool value) =>
      _write(() => _showCount = value, (p) => p.setBool(_kShowCount, value));

  static Future<void> setShoe(String value) =>
      _write(() => _shoe = value, (p) => p.setString(_kShoe, value));

  static Future<void> setSpots(int value) =>
      _write(() => _spots = value, (p) => p.setInt(_kSpots, value));

  static Future<void> setCountCheck(bool value) =>
      _write(() => _countCheck = value, (p) => p.setBool(_kCountCheck, value));

  static Future<void> setIndexPlays(bool value) =>
      _write(() => _indexPlays = value, (p) => p.setBool(_kIndexPlays, value));

  static Future<void> setBetCoach(bool value) =>
      _write(() => _betCoach = value, (p) => p.setBool(_kBetCoach, value));

  static Future<void> setBetUnit(int value) {
    assert(betUnits.contains(value));
    return _write(() => _betUnit = value, (p) => p.setInt(_kBetUnit, value));
  }

  static Future<void> _write(
    void Function() apply,
    Future<bool> Function(SharedPreferences prefs) persist,
  ) async {
    apply();
    try {
      await persist(await SharedPreferences.getInstance());
    } catch (_) {
      // A preference we cannot persist is not worth failing over.
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _showCount = true;
    _shoe = null;
    _spots = 1;
    _countCheck = true;
    _indexPlays = false;
    _betCoach = false;
    _betUnit = 25;
  }
}

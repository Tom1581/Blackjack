import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'basic_strategy.dart';

/// How the player has been doing against basic strategy.
@immutable
class StrategyRecord {
  final int correct;
  final int total;

  const StrategyRecord({required this.correct, required this.total});

  static const empty = StrategyRecord(correct: 0, total: 0);

  int get mistakes => total - correct;

  /// 0–1. Zero decisions reads as zero rather than "perfect".
  double get accuracy => total > 0 ? correct / total : 0;

  int get accuracyPercent => (accuracy * 100).round();

  /// Enough decisions for the number to mean anything.
  bool get isMeaningful => total >= 20;
}

/// One wrong decision, for the moment of feedback right after it is made.
@immutable
class StrategyFeedback {
  final StrategyMove played;
  final StrategyMove best;
  final int handValue;
  final bool handWasSoft;
  final String dealerUp;

  const StrategyFeedback({
    required this.played,
    required this.best,
    required this.handValue,
    required this.handWasSoft,
    required this.dealerUp,
  });

  /// e.g. "Soft 18 vs 5 — basic strategy says Double"
  String get message {
    final total = handWasSoft ? 'Soft $handValue' : '$handValue';
    return '$total vs $dealerUp — basic strategy says ${best.label}';
  }
}

/// Scores the player's decisions against basic strategy and remembers how
/// they are doing.
///
/// This is the point of a trainer: an app that lets you misplay sixteen
/// against a ten forever without ever mentioning it is not teaching anything.
///
/// Insurance is deliberately **not** scored. Flat basic strategy says never
/// take it, but this is a card-counting trainer, and insurance becomes correct
/// at a high enough true count — so marking it wrong would contradict the very
/// thing the app teaches.
class StrategyCoach {
  const StrategyCoach._();

  static const _kCorrect = 'strategy_correct';
  static const _kTotal = 'strategy_total';
  static const _kHints = 'strategy_hints_enabled';

  static bool _hintsEnabled = true;

  /// Whether the recommended action is highlighted while playing.
  static bool get hintsEnabled => _hintsEnabled;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hintsEnabled = prefs.getBool(_kHints) ?? true;
    } catch (_) {
      _hintsEnabled = true;
    }
  }

  static Future<void> setHintsEnabled(bool value) async {
    _hintsEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kHints, value);
    } catch (_) {
      // A preference we cannot persist is not worth failing over.
    }
  }

  static Future<void> record({required bool correct}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTotal, (prefs.getInt(_kTotal) ?? 0) + 1);
      if (correct) {
        await prefs.setInt(_kCorrect, (prefs.getInt(_kCorrect) ?? 0) + 1);
      }
    } catch (error) {
      debugPrint('Could not record a decision: $error');
    }
  }

  static Future<StrategyRecord> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return StrategyRecord(
        correct: prefs.getInt(_kCorrect) ?? 0,
        total: prefs.getInt(_kTotal) ?? 0,
      );
    } catch (_) {
      return StrategyRecord.empty;
    }
  }

  static Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCorrect);
    await prefs.remove(_kTotal);
  }

  @visibleForTesting
  static void resetForTest() => _hintsEnabled = true;
}

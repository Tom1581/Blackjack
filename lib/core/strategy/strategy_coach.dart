import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'basic_strategy.dart';
import 'deviations.dart';

/// Which part of the chart a decision came from. Players are rarely equally
/// good at all three — soft doubles and pair splits are where most of them
/// leak — so one global accuracy number hides exactly what needs work.
enum StrategyCategory {
  hard('Hard totals'),
  soft('Soft totals'),
  pair('Pairs');

  const StrategyCategory(this.label);
  final String label;
}

/// One chart cell the player keeps getting wrong.
@immutable
class StrategyMiss {
  /// e.g. "Soft 18 vs 9".
  final String spot;
  final int count;

  const StrategyMiss(this.spot, this.count);
}

/// Accuracy broken down by [StrategyCategory], plus the cells missed most.
@immutable
class StrategyMastery {
  final Map<StrategyCategory, StrategyRecord> byCategory;
  final List<StrategyMiss> topMisses;

  const StrategyMastery({required this.byCategory, required this.topMisses});

  StrategyRecord of(StrategyCategory category) =>
      byCategory[category] ?? StrategyRecord.empty;

  static const empty = StrategyMastery(byCategory: {}, topMisses: []);
}

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

  /// Set when an index play decided the answer rather than the chart.
  final IndexPlay? indexPlay;

  /// The true count the decision was made at, for index-play feedback.
  final double? trueCount;

  /// A complete message, for feedback that is not about a hand — insurance.
  final String? note;

  const StrategyFeedback({
    required this.played,
    required this.best,
    required this.handValue,
    required this.handWasSoft,
    required this.dealerUp,
    this.indexPlay,
    this.trueCount,
    this.note,
  });

  /// Feedback that is a complete sentence of its own — insurance and bet
  /// checks, which are not about a hand.
  const StrategyFeedback.note(String message)
      : played = StrategyMove.stand,
        best = StrategyMove.stand,
        handValue = 0,
        handWasSoft = false,
        dealerUp = 'A',
        indexPlay = null,
        trueCount = null,
        note = message;

  /// e.g. "Soft 18 vs 5 — basic strategy says Double", or for an index play
  /// "16 vs 10 at true count +1.2 — the count says Stand (Illustrious 18
  /// index 0)".
  String get message {
    if (note != null) return note!;
    final total = handWasSoft ? 'Soft $handValue' : '$handValue';
    final play = indexPlay;
    final tc = trueCount;
    if (play != null && tc != null) {
      final index = play.index > 0
          ? '+${play.index}'
          : (play.index < 0 ? '−${-play.index}' : '0');
      return '$total vs $dealerUp at true count ${formatTrueCount(tc)} — the '
          'count says ${best.label} (${play.set.label} index $index)';
    }
    return '$total vs $dealerUp — basic strategy says ${best.label}';
  }
}

/// "+1.2", "−0.5", "0.0".
String formatTrueCount(double tc) {
  final text = tc.abs().toStringAsFixed(1);
  if (tc > 0 && text != '0.0') return '+$text';
  if (tc < 0 && text != '0.0') return '−$text';
  return '0.0';
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
  static const _kMisses = 'strategy_misses';
  static const _kIndexTotal = 'strategy_index_total';
  static const _kIndexCorrect = 'strategy_index_correct';
  static String _kCatTotal(StrategyCategory c) => 'strategy_${c.name}_total';
  static String _kCatCorrect(StrategyCategory c) =>
      'strategy_${c.name}_correct';

  /// How many distinct missed cells are remembered. Plenty for a top-five
  /// list, and it keeps the stored map small.
  static const _maxTrackedMisses = 40;

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

  /// Record one decision. [category] and [spot] feed the per-category
  /// breakdown and the most-missed list; both are optional so a caller that
  /// only knows right-or-wrong still counts toward the overall accuracy.
  static Future<void> record({
    required bool correct,
    StrategyCategory? category,
    String? spot,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Every read-modify-write below is synchronous against the preferences
      // cache, so two decisions recorded back to back cannot lose an update.
      await prefs.setInt(_kTotal, (prefs.getInt(_kTotal) ?? 0) + 1);
      if (correct) {
        await prefs.setInt(_kCorrect, (prefs.getInt(_kCorrect) ?? 0) + 1);
      }
      if (category != null) {
        final t = _kCatTotal(category);
        await prefs.setInt(t, (prefs.getInt(t) ?? 0) + 1);
        if (correct) {
          final c = _kCatCorrect(category);
          await prefs.setInt(c, (prefs.getInt(c) ?? 0) + 1);
        }
      }
      if (!correct && spot != null) {
        final misses = _decodeMisses(prefs.getString(_kMisses));
        misses[spot] = (misses[spot] ?? 0) + 1;
        if (misses.length > _maxTrackedMisses) {
          // Forget the least-missed cell to make room.
          final weakest =
              misses.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
          if (weakest != spot) misses.remove(weakest);
        }
        await prefs.setString(_kMisses, jsonEncode(misses));
      }
    } catch (error) {
      debugPrint('Could not record a decision: $error');
    }
  }

  static Map<String, int> _decodeMisses(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in decoded.entries)
          if (e.value is int) e.key: e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  /// Record a decision that an index play (or the insurance index) decided.
  /// Kept apart from the chart record so "do I know my indices?" has its own
  /// answer.
  static Future<void> recordIndex({required bool correct}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kIndexTotal, (prefs.getInt(_kIndexTotal) ?? 0) + 1);
      if (correct) {
        await prefs.setInt(
            _kIndexCorrect, (prefs.getInt(_kIndexCorrect) ?? 0) + 1);
      }
    } catch (error) {
      debugPrint('Could not record an index play: $error');
    }
  }

  static Future<StrategyRecord> readIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return StrategyRecord(
        correct: prefs.getInt(_kIndexCorrect) ?? 0,
        total: prefs.getInt(_kIndexTotal) ?? 0,
      );
    } catch (_) {
      return StrategyRecord.empty;
    }
  }

  /// Accuracy by category and the five cells missed most often.
  static Future<StrategyMastery> readMastery() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final misses = _decodeMisses(prefs.getString(_kMisses)).entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return StrategyMastery(
        byCategory: {
          for (final c in StrategyCategory.values)
            c: StrategyRecord(
              correct: prefs.getInt(_kCatCorrect(c)) ?? 0,
              total: prefs.getInt(_kCatTotal(c)) ?? 0,
            ),
        },
        topMisses: [
          for (final e in misses.take(5)) StrategyMiss(e.key, e.value),
        ],
      );
    } catch (_) {
      return StrategyMastery.empty;
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
    await prefs.remove(_kMisses);
    await prefs.remove(_kIndexTotal);
    await prefs.remove(_kIndexCorrect);
    for (final c in StrategyCategory.values) {
      await prefs.remove(_kCatTotal(c));
      await prefs.remove(_kCatCorrect(c));
    }
  }

  @visibleForTesting
  static void resetForTest() => _hintsEnabled = true;
}

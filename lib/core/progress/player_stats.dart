import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/game_state.dart';

/// Lifetime table results and counting practice, for the stats screen.
///
/// The stats screen used to read `hands_played`, `wins`, `losses` and friends
/// from preferences that nothing in the app ever wrote, so it showed zero
/// hands and a 0% win rate forever. This is the writer.
@immutable
class PlayerStats {
  final int hands;
  final int wins;
  final int losses;
  final int pushes;
  final int blackjacks;

  /// Hands given up to late surrender. Also counted in [losses].
  final int surrenders;

  /// Chips won or lost at the table only — daily bonuses and rewarded chips
  /// are not winnings and are left out.
  final int tableNet;
  final int biggestWin;

  /// True count when each recent round was dealt, oldest first.
  final List<double> trueCountHistory;

  /// Running-count quizzes answered at the table while the HUD was hidden.
  final int countChecks;
  final int countChecksCorrect;

  /// Deals checked against the bet-spread ramp.
  final int betChecks;
  final int betChecksCorrect;

  const PlayerStats({
    this.hands = 0,
    this.wins = 0,
    this.losses = 0,
    this.pushes = 0,
    this.blackjacks = 0,
    this.surrenders = 0,
    this.tableNet = 0,
    this.biggestWin = 0,
    this.trueCountHistory = const [],
    this.countChecks = 0,
    this.countChecksCorrect = 0,
    this.betChecks = 0,
    this.betChecksCorrect = 0,
  });

  /// Share of decided hands won. Pushes are left out of the denominator — a
  /// push is neither — and zero hands reads as zero, not as perfect.
  double get winRate {
    final decided = wins + losses;
    return decided > 0 ? wins / decided : 0;
  }

  int get countCheckPercent =>
      countChecks > 0 ? (countChecksCorrect * 100 / countChecks).round() : 0;

  int get betCheckPercent =>
      betChecks > 0 ? (betChecksCorrect * 100 / betChecks).round() : 0;
}

class PlayerStatsStore {
  const PlayerStatsStore._();

  static const _kHands = 'hands_played';
  static const _kWins = 'wins';
  static const _kLosses = 'losses';
  static const _kPushes = 'pushes';
  static const _kBlackjacks = 'blackjacks';
  static const _kSurrenders = 'surrenders';
  static const _kNet = 'table_net';
  static const _kBiggest = 'biggest_win';
  static const _kTcHistory = 'true_count_history';
  static const _kChecks = 'count_checks';
  static const _kChecksCorrect = 'count_checks_correct';
  static const _kBetChecks = 'bet_checks';
  static const _kBetChecksCorrect = 'bet_checks_correct';

  /// How many rounds of true-count history to keep for the chart.
  static const historyLength = 60;

  /// Record a settled round: each hand's result, the round's net, and the
  /// true count it was dealt at.
  static Future<void> recordRound({
    required List<GameResult?> results,
    required int roundNet,
    required double trueCountAtDeal,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var wins = 0, losses = 0, pushes = 0, blackjacks = 0, surrenders = 0;
      for (final r in results) {
        switch (r) {
          case GameResult.blackjack:
            blackjacks++;
            wins++;
          case GameResult.win:
          case GameResult.dealerBust:
            wins++;
          case GameResult.loss:
          case GameResult.bust:
            losses++;
          case GameResult.push:
            pushes++;
          case GameResult.surrender:
            // Half the bet is lost: a loss for the win rate, and counted on
            // its own so the stats can show how often it was used.
            losses++;
            surrenders++;
          case null:
            break;
        }
      }
      Future<void> add(String key, int by) async {
        if (by != 0) await prefs.setInt(key, (prefs.getInt(key) ?? 0) + by);
      }

      await add(_kHands, wins + losses + pushes);
      await add(_kWins, wins);
      await add(_kLosses, losses);
      await add(_kPushes, pushes);
      await add(_kBlackjacks, blackjacks);
      await add(_kSurrenders, surrenders);
      await add(_kNet, roundNet);
      if (roundNet > (prefs.getInt(_kBiggest) ?? 0)) {
        await prefs.setInt(_kBiggest, roundNet);
      }

      final history = [
        ...(prefs.getStringList(_kTcHistory) ?? const <String>[]),
        trueCountAtDeal.toStringAsFixed(1),
      ];
      final start =
          history.length > historyLength ? history.length - historyLength : 0;
      await prefs.setStringList(_kTcHistory, history.sublist(start));
    } catch (error) {
      debugPrint('Could not record the round: $error');
    }
  }

  static Future<void> recordCountCheck({required bool correct}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kChecks, (prefs.getInt(_kChecks) ?? 0) + 1);
      if (correct) {
        await prefs.setInt(
            _kChecksCorrect, (prefs.getInt(_kChecksCorrect) ?? 0) + 1);
      }
    } catch (error) {
      debugPrint('Could not record the count check: $error');
    }
  }

  static Future<void> recordBetCheck({required bool correct}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBetChecks, (prefs.getInt(_kBetChecks) ?? 0) + 1);
      if (correct) {
        await prefs.setInt(
            _kBetChecksCorrect, (prefs.getInt(_kBetChecksCorrect) ?? 0) + 1);
      }
    } catch (error) {
      debugPrint('Could not record the bet check: $error');
    }
  }

  static Future<PlayerStats> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return PlayerStats(
        hands: prefs.getInt(_kHands) ?? 0,
        wins: prefs.getInt(_kWins) ?? 0,
        losses: prefs.getInt(_kLosses) ?? 0,
        pushes: prefs.getInt(_kPushes) ?? 0,
        blackjacks: prefs.getInt(_kBlackjacks) ?? 0,
        surrenders: prefs.getInt(_kSurrenders) ?? 0,
        tableNet: prefs.getInt(_kNet) ?? 0,
        biggestWin: prefs.getInt(_kBiggest) ?? 0,
        trueCountHistory: [
          for (final raw in prefs.getStringList(_kTcHistory) ?? const [])
            if (double.tryParse(raw) != null) double.parse(raw),
        ],
        countChecks: prefs.getInt(_kChecks) ?? 0,
        countChecksCorrect: prefs.getInt(_kChecksCorrect) ?? 0,
        betChecks: prefs.getInt(_kBetChecks) ?? 0,
        betChecksCorrect: prefs.getInt(_kBetChecksCorrect) ?? 0,
      );
    } catch (_) {
      return const PlayerStats();
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_service.dart';
import '../leaderboard/leaderboard_service.dart';
import '../online/online_providers.dart';
import 'hilo_game.dart';

/// Whether the shared Hi-Lo boards could return live data.
enum HiLoBoardStatus { live, notConfigured, offline }

/// A score shown on either Hi-Lo board.
class HiLoBoardEntry {
  final String name;
  final int score;
  final int correct;
  final int answered;
  final int? level;
  final int rank;
  final bool isCurrentUser;

  const HiLoBoardEntry({
    required this.name,
    required this.score,
    required this.correct,
    required this.answered,
    this.level,
    required this.rank,
    required this.isCurrentUser,
  });
}

/// The current player's position in a Daily Challenge.
class HiLoDailyStanding {
  final int rank;
  final int players;
  final int score;

  const HiLoDailyStanding({
    required this.rank,
    required this.players,
    required this.score,
  });
}

class HiLoDailyBoard {
  final HiLoBoardStatus status;
  final List<HiLoBoardEntry> entries;
  final HiLoDailyStanding? standing;
  final String? diagnostic;

  const HiLoDailyBoard({
    required this.status,
    this.entries = const [],
    this.standing,
    this.diagnostic,
  });

  bool get isLive => status == HiLoBoardStatus.live;
}

class HiLoSurvivalBoard {
  final HiLoBoardStatus status;
  final List<HiLoBoardEntry> entries;
  final String? diagnostic;

  const HiLoSurvivalBoard({
    required this.status,
    this.entries = const [],
    this.diagnostic,
  });

  bool get isLive => status == HiLoBoardStatus.live;
}

/// The small backend boundary keeps the submission and ranking rules testable
/// without a Supabase client.
abstract class HiLoBoardsBackend {
  Future<String> identify();
  Future<void> submitDaily(Map<String, dynamic> row);
  Future<void> submitSurvival(Map<String, dynamic> row);
  Future<List<Map<String, dynamic>>> dailyRows(int day, int limit);
  Future<List<Map<String, dynamic>>> survivalRows(String weekKey, int limit);
  Future<Map<String, dynamic>?> dailyStanding(int day);
}

class SupabaseHiLoBoardsBackend implements HiLoBoardsBackend {
  final SupabaseClient client;

  const SupabaseHiLoBoardsBackend(this.client);

  @override
  Future<String> identify() async {
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;
    final response = await client.auth.signInAnonymously();
    final user = response.user;
    if (user == null) throw const AuthException('Anonymous sign-in failed.');
    return user.id;
  }

  @override
  Future<void> submitDaily(Map<String, dynamic> row) async {
    await client.rpc('submit_hilo_daily', params: {
      'p_day': row['day'],
      'p_display_name': row['display_name'],
      'p_score': row['score'],
      'p_correct': row['correct'],
      'p_answered': row['answered'],
      'p_best_streak': row['best_streak'],
    });
  }

  @override
  Future<void> submitSurvival(Map<String, dynamic> row) async {
    await client.rpc('submit_hilo_survival', params: {
      'p_week_key': row['week_key'],
      'p_display_name': row['display_name'],
      'p_score': row['score'],
      'p_correct': row['correct'],
      'p_answered': row['answered'],
      'p_level': row['level'],
    });
  }

  @override
  Future<List<Map<String, dynamic>>> dailyRows(int day, int limit) async {
    final rows = await client
        .from('hilo_daily_scores')
        .select('player_id, display_name, score, correct, answered, '
            'best_streak, submitted_at')
        .eq('day', day)
        .order('score', ascending: false)
        .order('submitted_at', ascending: true)
        .order('player_id', ascending: true)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> survivalRows(
      String weekKey, int limit) async {
    final rows = await client
        .from('hilo_survival_scores')
        .select('player_id, display_name, score, correct, answered, level, '
            'submitted_at')
        .eq('week_key', weekKey)
        .order('score', ascending: false)
        .order('submitted_at', ascending: true)
        .order('player_id', ascending: true)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<Map<String, dynamic>?> dailyStanding(int day) async {
    final result = await client.rpc('hilo_daily_standing', params: {
      'p_day': day,
    });
    if (result is List) {
      return result.isEmpty ? null : Map<String, dynamic>.from(result.first);
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }
}

/// Reads and writes the shared Daily and Survival boards. A failing backend is
/// deliberately invisible to the game result: local progression is primary.
class HiLoBoardsService {
  const HiLoBoardsService._();

  static const boardLimit = 100;

  @visibleForTesting
  static HiLoBoardsBackend? backendOverride;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static HiLoBoardsBackend? get _backend {
    final override = backendOverride;
    if (override != null) return override;
    if (!AppSupabase.isReady) return null;
    return SupabaseHiLoBoardsBackend(Supabase.instance.client);
  }

  /// Push one eligible game. Replays and friend challenges intentionally do
  /// not reach the server, so memorising a shoe cannot change a rank.
  static Future<bool> submitGame(HiLoGame game) async {
    final spec = game.spec;
    final isDaily = spec.mode == HiLoMode.daily && spec.ranked;
    final isSurvival = spec.isSurvival && spec.ranked && !spec.isChallenge;
    if (!isDaily && !isSurvival) return false;

    final backend = _backend;
    if (backend == null) return false;

    final player = game.players.first;
    try {
      final userId = await backend.identify();
      final name = await _displayName();
      if (isDaily) {
        await backend.submitDaily({
          'player_id': userId,
          'day': spec.dailyNumber,
          'display_name': name,
          'score': player.score,
          'correct': player.correct,
          'answered': player.answered,
          'best_streak': player.bestStreak,
        });
      } else {
        await backend.submitSurvival({
          'player_id': userId,
          'week_key': LeaderboardService.weekKey(now()),
          'display_name': name,
          'score': player.score,
          'correct': player.correct,
          'answered': player.answered,
          'level': game.level,
        });
      }
      return true;
    } catch (error) {
      debugPrint('Hi-Lo board submit failed: ${describeFailure(error)}');
      return false;
    }
  }

  static Future<HiLoDailyBoard> fetchDaily({int? day}) async {
    final backend = _backend;
    if (backend == null) {
      return const HiLoDailyBoard(
        status: HiLoBoardStatus.offline,
        diagnostic: 'Supabase is not initialised on this device.',
      );
    }

    final dailyNumber = day ?? HiLoDaily.numberFor(now());
    try {
      final userId = await backend.identify();
      final results = await Future.wait([
        backend.dailyRows(dailyNumber, boardLimit),
        backend.dailyStanding(dailyNumber),
      ]);
      final rows = results[0] as List<Map<String, dynamic>>;
      final standing = results[1] as Map<String, dynamic>?;
      return HiLoDailyBoard(
        status: HiLoBoardStatus.live,
        entries: [
          for (var i = 0; i < rows.length; i++)
            _entryFrom(rows[i], userId, i + 1),
        ],
        standing: standing == null
            ? null
            : HiLoDailyStanding(
                rank: _number(standing['rank']),
                players: _number(standing['players']),
                score: _number(standing['score']),
              ),
      );
    } catch (error) {
      return HiLoDailyBoard(
        status: isSetupProblem(error)
            ? HiLoBoardStatus.notConfigured
            : HiLoBoardStatus.offline,
        diagnostic: describeFailure(error),
      );
    }
  }

  static Future<HiLoSurvivalBoard> fetchSurvival() async {
    final backend = _backend;
    if (backend == null) {
      return const HiLoSurvivalBoard(
        status: HiLoBoardStatus.offline,
        diagnostic: 'Supabase is not initialised on this device.',
      );
    }

    try {
      final userId = await backend.identify();
      final rows = await backend.survivalRows(
        LeaderboardService.weekKey(now()),
        boardLimit,
      );
      return HiLoSurvivalBoard(
        status: HiLoBoardStatus.live,
        entries: [
          for (var i = 0; i < rows.length; i++)
            _entryFrom(rows[i], userId, i + 1),
        ],
      );
    } catch (error) {
      return HiLoSurvivalBoard(
        status: isSetupProblem(error)
            ? HiLoBoardStatus.notConfigured
            : HiLoBoardStatus.offline,
        diagnostic: describeFailure(error),
      );
    }
  }

  static HiLoBoardEntry _entryFrom(
    Map<String, dynamic> row,
    String userId,
    int rank,
  ) =>
      HiLoBoardEntry(
        name: (row['display_name'] as String?) ?? 'Player',
        score: _number(row['score']),
        correct: _number(row['correct']),
        answered: _number(row['answered']),
        level: row.containsKey('level') ? _number(row['level']) : null,
        rank: rank,
        isCurrentUser: row['player_id'] == userId,
      );

  static int _number(Object? value) => (value as num?)?.toInt() ?? 0;

  static Future<String> _displayName() async {
    var name = (await loadPlayerName()).trim();
    if (name.isEmpty) name = 'Player';
    return name.length > 12 ? name.substring(0, 12) : name;
  }

  /// Missing-table/function codes are a deployment state, not a player
  /// error. PGRST205 is Supabase's missing-relation answer.
  @visibleForTesting
  static bool isSetupProblem(Object error) {
    if (error is PostgrestException) {
      return error.code == 'PGRST202' ||
          error.code == 'PGRST205' ||
          error.code == '42883' ||
          error.code == '42P01' ||
          error.code == '42703' ||
          error.code == '42501';
    }
    return error is AuthException;
  }

  @visibleForTesting
  static String describeFailure(Object error) {
    if (error is PostgrestException) {
      return 'Postgrest ${error.code}: ${error.message}.';
    }
    if (error is AuthException) {
      return 'Auth: ${error.message}. Enable anonymous sign-ins.';
    }
    if (error is SocketException || error is TimeoutException) {
      return 'Network unavailable.';
    }
    return error.toString();
  }

  @visibleForTesting
  static void resetForTest() {
    backendOverride = null;
    now = DateTime.now;
  }
}

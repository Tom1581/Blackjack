import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_service.dart';
import '../online/online_providers.dart';
import 'leaderboard_service.dart';

/// Where the board's numbers came from.
enum BoardStatus {
  /// Real scores, from every player who played this week.
  live,

  /// The backend is reachable but the board is not set up — the migration has
  /// not been applied, or anonymous sign-ins are disabled.
  notConfigured,

  /// We could not reach the service right now.
  offline,
}

/// One row of the weekly board.
class LeaderboardEntry {
  final String name;
  final int profit;
  final int handsPlayed;
  final bool isCurrentUser;

  /// 1-based position on the board. Zero means "not ranked yet".
  final int rank;

  const LeaderboardEntry({
    required this.name,
    required this.profit,
    this.handsPlayed = 0,
    this.isCurrentUser = false,
    this.rank = 0,
  });

  LeaderboardEntry withRank(int value) => LeaderboardEntry(
        name: name,
        profit: profit,
        handsPlayed: handsPlayed,
        isCurrentUser: isCurrentUser,
        rank: value,
      );
}

/// A week's ranking, plus enough context for the screen to be honest about
/// what it is showing.
class WeeklyBoard {
  final BoardStatus status;
  final List<LeaderboardEntry> entries;

  /// The player's own row, even when they fall outside [entries].
  final LeaderboardEntry? me;

  /// How many players have a score this week.
  final int playerCount;

  /// Chips needed to overtake the player directly above — the number that
  /// actually makes someone play one more round.
  final int? gapToNextRank;

  /// Developer-facing reason the board is not [BoardStatus.live].
  final String? diagnostic;

  const WeeklyBoard({
    required this.status,
    this.entries = const [],
    this.me,
    this.playerCount = 0,
    this.gapToNextRank,
    this.diagnostic,
  });

  bool get isLive => status == BoardStatus.live;
  bool get isEmpty => entries.isEmpty;
}

/// The only things the weekly board needs from a backend. Kept this narrow so
/// the ranking logic can be tested without a network or a Supabase client.
abstract class BoardBackend {
  /// Stable id for this device, signing in anonymously if needed.
  Future<String> identify();

  /// Write this device's row for the week.
  Future<void> submit(Map<String, dynamic> row);

  /// Read a week's rows, highest profit first.
  Future<List<Map<String, dynamic>>> weekRows(String weekKey, int limit);
}

/// Talks to the `weekly_rankings` table.
class SupabaseBoardBackend implements BoardBackend {
  final SupabaseClient client;
  const SupabaseBoardBackend(this.client);

  static const table = 'weekly_rankings';

  @override
  Future<String> identify() async {
    final existing = client.auth.currentUser;
    if (existing != null) return existing.id;
    // Anonymous sign-in gives each device a real user id, which is what the
    // row-level policies key on — without it, players could overwrite each
    // other's scores.
    final response = await client.auth.signInAnonymously();
    final user = response.user;
    if (user == null) throw const AuthException('Anonymous sign-in failed.');
    return user.id;
  }

  @override
  Future<void> submit(Map<String, dynamic> row) async {
    // Direct table writes are deliberately revoked. The database function
    // enforces the current week, a monotonic hand count, and plausible score
    // changes before it updates this authenticated user's row.
    await client.rpc('submit_weekly_ranking', params: {
      'p_week_key': row['week_key'],
      'p_display_name': row['display_name'],
      'p_profit': row['profit'],
      'p_hands_played': row['hands_played'],
    });
  }

  @override
  Future<List<Map<String, dynamic>>> weekRows(String weekKey, int limit) async {
    final rows = await client
        .from(table)
        .select('player_id, display_name, profit, hands_played')
        .eq('week_key', weekKey)
        .order('profit', ascending: false)
        .limit(limit);
    return rows.cast<Map<String, dynamic>>();
  }
}

/// Reads and writes the shared weekly ranking.
///
/// Degrades rather than fails: if the table or the anonymous provider is
/// missing, the player still sees their own week instead of an error.
class WeeklyBoardService {
  const WeeklyBoardService._();

  /// Rows fetched for the board.
  static const boardLimit = 100;

  /// Scores are pushed no more often than this while playing.
  static const pushInterval = Duration(seconds: 30);

  static DateTime? _lastPush;
  static int? _pushedProfit;
  static int? _pushedHands;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  @visibleForTesting
  static BoardBackend? backendOverride;

  static BoardBackend? get _backend {
    final override = backendOverride;
    if (override != null) return override;
    if (!AppSupabase.isReady) return null;
    return SupabaseBoardBackend(Supabase.instance.client);
  }

  /// Push this device's weekly totals.
  ///
  /// Skips the write when nothing has changed since the last one, and
  /// otherwise waits out [pushInterval] — a round finishing should not mean a
  /// REST call.
  static Future<bool> push({bool force = false}) async {
    final backend = _backend;
    if (backend == null) return false;

    final profit = await LeaderboardService.readWeeklyProfit();
    final hands = await LeaderboardService.readHandsPlayed();
    // Nothing to say until they have actually played.
    if (hands == 0) return false;
    if (profit == _pushedProfit && hands == _pushedHands) return false;

    final last = _lastPush;
    if (!force && last != null && now().difference(last) < pushInterval) {
      return false;
    }

    try {
      final userId = await backend.identify();
      var name = await loadPlayerName();
      if (name.isEmpty) name = 'Player';
      if (name.length > 12) name = name.substring(0, 12);

      await backend.submit({
        'player_id': userId,
        'week_key': LeaderboardService.weekKey(),
        'display_name': name,
        'profit': profit,
        'hands_played': hands,
      });
      _lastPush = now();
      _pushedProfit = profit;
      _pushedHands = hands;
      return true;
    } catch (error) {
      debugPrint('Weekly board push failed: ${describeFailure(error)}');
      return false;
    }
  }

  /// Read this week's board.
  static Future<WeeklyBoard> fetch() async {
    // Make sure our own score is on the board before we look at it.
    await push(force: true);

    final backend = _backend;
    if (backend == null) {
      return _localOnly(
        BoardStatus.offline,
        'Supabase is not initialised on this device.',
      );
    }

    try {
      final userId = await backend.identify();
      final rows =
          await backend.weekRows(LeaderboardService.weekKey(), boardLimit);

      final entries = <LeaderboardEntry>[];
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        entries.add(LeaderboardEntry(
          name: (row['display_name'] as String?) ?? 'Player',
          profit: (row['profit'] as num?)?.toInt() ?? 0,
          handsPlayed: (row['hands_played'] as num?)?.toInt() ?? 0,
          isCurrentUser: row['player_id'] == userId,
          rank: i + 1,
        ));
      }

      final myIndex = entries.indexWhere((e) => e.isCurrentUser);
      final me = myIndex >= 0 ? entries[myIndex] : await _localEntry();
      final gap = myIndex > 0
          ? entries[myIndex - 1].profit - entries[myIndex].profit
          : null;

      return WeeklyBoard(
        status: BoardStatus.live,
        entries: entries,
        me: me,
        playerCount: entries.length,
        gapToNextRank: gap,
      );
    } catch (error) {
      return _localOnly(
        isSetupProblem(error) ? BoardStatus.notConfigured : BoardStatus.offline,
        describeFailure(error),
      );
    }
  }

  /// A board of one: just this player's own week. Honest, and still something
  /// to beat next week.
  static Future<WeeklyBoard> _localOnly(
    BoardStatus status,
    String diagnostic,
  ) async {
    final me = await _localEntry();
    final played = me.handsPlayed > 0;
    debugPrint('Weekly board unavailable ($status): $diagnostic');
    return WeeklyBoard(
      status: status,
      entries: played ? [me.withRank(1)] : const [],
      me: me.withRank(played ? 1 : 0),
      playerCount: played ? 1 : 0,
      diagnostic: diagnostic,
    );
  }

  static Future<LeaderboardEntry> _localEntry() async {
    var name = await loadPlayerName();
    if (name.isEmpty) name = 'You';
    return LeaderboardEntry(
      name: name,
      profit: await LeaderboardService.readWeeklyProfit(),
      handsPlayed: await LeaderboardService.readHandsPlayed(),
      isCurrentUser: true,
    );
  }

  /// Distinguish "nobody applied the migration / enabled anonymous sign-ins"
  /// from "the network is down", so the log says which one to go and fix.
  @visibleForTesting
  static bool isSetupProblem(Object error) {
    if (error is PostgrestException) {
      // 42P01 undefined_table, 42501 insufficient_privilege.
      return error.code == '42P01' || error.code == '42501';
    }
    return error is AuthException;
  }

  @visibleForTesting
  static String describeFailure(Object error) {
    if (error is PostgrestException) {
      return 'Postgrest ${error.code}: ${error.message}. '
          'Apply supabase/migrations/20260825000000_weekly_rankings.sql';
    }
    if (error is AuthException) {
      return 'Auth: ${error.message}. '
          'Enable Authentication -> Providers -> Anonymous sign-ins.';
    }
    if (error is SocketException || error is TimeoutException) {
      return 'Network unavailable.';
    }
    return error.toString();
  }

  @visibleForTesting
  static void resetForTest() {
    _lastPush = null;
    _pushedProfit = null;
    _pushedHands = null;
    backendOverride = null;
    now = DateTime.now;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'leaderboard_service.dart';

/// Bumped after every hand to force the weekly board future to re-run, so
/// the lobby's Top-3 preview and the leaderboard screen pick up the user's
/// new profit without manual refresh.
final boardRefreshTickProvider = StateProvider<int>((ref) => 0);

/// Cached weekly leaderboard. Re-runs whenever [boardRefreshTickProvider]
/// changes (after a hand) or whenever a consumer re-watches it after the
/// auto-dispose timeout.
final weeklyBoardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) async {
  ref.watch(boardRefreshTickProvider);
  return LeaderboardService.rankedBoard();
});

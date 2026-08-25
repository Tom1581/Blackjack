import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'weekly_board_service.dart';

/// Bumped after every hand to force the weekly board future to re-run, so
/// the lobby's Top-3 preview and the leaderboard screen pick up the user's
/// new profit without manual refresh.
final boardRefreshTickProvider = StateProvider<int>((ref) => 0);

/// This week's shared ranking. Re-runs whenever [boardRefreshTickProvider]
/// changes (after a hand) or whenever a consumer re-watches it after the
/// auto-dispose timeout. Pushes this device's score before reading, so you
/// always see yourself on the board you are looking at.
final weeklyBoardProvider =
    FutureProvider.autoDispose<WeeklyBoard>((ref) async {
  ref.watch(boardRefreshTickProvider);
  return WeeklyBoardService.fetch();
});

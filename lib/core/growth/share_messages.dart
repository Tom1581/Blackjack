const hiLoBlackjackPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=io.github.a15817348.hiloblackjacktrainer';

class GrowthShareMessages {
  static String dailyDrill({
    required int correct,
    required int total,
    required int bestStreak,
  }) {
    return 'I scored $correct/$total in today\'s Hi-Lo Count Drill '
        'with a $bestStreak-card streak in Hi-Lo Blackjack Trainer. '
        'Can you beat me?\n$hiLoBlackjackPlayStoreUrl';
  }

  static String roomInvite(String roomCode) {
    final code = roomCode.trim().toUpperCase();
    return 'Join my private table in Hi-Lo Blackjack Trainer.\n'
        'Room code: $code\n\n'
        'Open or install the game: $hiLoBlackjackPlayStoreUrl';
  }
}

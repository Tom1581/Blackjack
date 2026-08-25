import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Asks for a Play Store rating, but only at a moment the player is plausibly
/// pleased and only rarely.
///
/// Ratings matter disproportionately for a young listing: below roughly ten
/// of them Play shows no star rating at all, which costs both ranking and
/// conversion. The prompt is still the player's screen though, so the rules
/// here are deliberately conservative — a badly timed ask earns a one-star.
class ReviewPrompter {
  const ReviewPrompter._();

  static const _kRounds = 'review_rounds_played';
  static const _kAsks = 'review_asks';
  static const _kAskedAtMs = 'review_last_ask_ms';

  /// Rounds played before each successive ask. Never more than three times.
  static const milestones = [20, 100, 300];

  /// Minimum gap between asks, regardless of milestones.
  static const minGap = Duration(days: 60);

  /// Requests the native Play review sheet. Swappable for tests, which must
  /// never touch the platform channel.
  @visibleForTesting
  static Future<void> Function() requester = _requestPlayReview;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static Future<void> _requestPlayReview() async {
    final review = InAppReview.instance;
    if (await review.isAvailable()) await review.requestReview();
  }

  /// Record a finished round and, if this is a good moment, ask for a rating.
  ///
  /// [roundNet] is the player's chips won or lost. We only ever ask after a
  /// winning round — asking someone who just busted out is how you collect
  /// bad reviews.
  static Future<bool> onRoundFinished(int roundNet) async {
    final prefs = await SharedPreferences.getInstance();
    final rounds = (prefs.getInt(_kRounds) ?? 0) + 1;
    await prefs.setInt(_kRounds, rounds);

    if (!_isGoodMoment(prefs, rounds: rounds, roundNet: roundNet)) return false;

    await prefs.setInt(_kAsks, (prefs.getInt(_kAsks) ?? 0) + 1);
    await prefs.setInt(_kAskedAtMs, now().millisecondsSinceEpoch);
    try {
      await requester();
    } catch (error) {
      // A review sheet that will not open is never worth an error to the
      // player; the attempt is already recorded so we will not retry today.
      debugPrint('Review request failed: $error');
    }
    return true;
  }

  static bool _isGoodMoment(
    SharedPreferences prefs, {
    required int rounds,
    required int roundNet,
  }) {
    if (roundNet <= 0) return false;

    final asks = prefs.getInt(_kAsks) ?? 0;
    if (asks >= milestones.length) return false;
    if (rounds < milestones[asks]) return false;

    final lastMs = prefs.getInt(_kAskedAtMs);
    if (lastMs != null) {
      final since = now().difference(DateTime.fromMillisecondsSinceEpoch(lastMs));
      if (since < minGap) return false;
    }
    return true;
  }

  /// Rounds played so far — exposed for the stats screen and for tests.
  static Future<int> roundsPlayed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kRounds) ?? 0;
  }

  @visibleForTesting
  static void resetForTest() {
    requester = _requestPlayReview;
    now = DateTime.now;
  }
}

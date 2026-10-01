import 'dart:math';

import '../../core/growth/share_messages.dart' show hiLoBlackjackPlayStoreUrl;
import '../../core/models/card_model.dart';
import '../training/drills.dart' show hiLoTag;
import 'hilo_game.dart';
import 'hilo_scoring.dart';
import 'hilo_training_session.dart';

// The words Hi-Lo Training says: counts, scores, advice and the text a
// player shares. Pure Dart, so every line is tested.

/// "+7", "−3", "0" — with a real minus sign.
String signedCount(int v) => v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0');

/// "12,450".
String points(int v) {
  final digits = v.abs().toString();
  final out = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

String seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(1);

/// "2.5", "3" — decks to the half deck.
String decksText(double decks) => decks == decks.roundToDouble()
    ? decks.toStringAsFixed(0)
    : decks.toStringAsFixed(1);

/// "+1.6", "−0.4", "0".
String signedDecimal(double v) {
  final text = v.abs().toStringAsFixed(1);
  if (text == '0.0') return '0';
  return v > 0 ? '+$text' : '−$text';
}

/// How the true count is worked out: "+4 ÷ 2.5 decks = +1.6, so +1 or +2".
/// (No arrow: Roboto has no glyph for one.)
String trueCountWorking(HiLoAnswer a) {
  final q = a.question;
  final rc = a.trueCountBasis;
  final accepted = q.acceptedTrueCounts(rc).toList()..sort();
  return '${signedCount(rc)} ÷ ${decksText(q.decksLeft)} decks = '
      '${signedDecimal(rc / q.decksLeft)}, so '
      '${accepted.map(signedCount).join(' or ')}';
}

/// The habit behind a slip, for "your most common miss".
String slipName(HiLoSlip slip) => switch (slip) {
      HiLoSlip.countedHoleCard => 'Counting the face-down card',
      HiLoSlip.missedLastCard => 'Missing the last card',
      HiLoSlip.flippedSign => 'Flipping the sign',
      HiLoSlip.timeUp => 'Running out of time',
      HiLoSlip.drift || HiLoSlip.none => 'Losing the count over a shoe',
    };

/// "4 players · 6 decks · Brisk".
String tableLabel(HiLoTrainingConfig c) =>
    '${c.players} player${c.players == 1 ? '' : 's'} · ${c.decks} decks · '
    '${c.pace.label}${c.trueCount ? ' · true count' : ''}';

/// One line on what to do about this answer.
String slipAdvice(HiLoAnswer result) {
  final q = result.question;
  switch (result.slip) {
    case HiLoSlip.none:
      final hole = q.holeCardDown;
      return hole != null && hiLoTag(hole) != 0
          ? 'And you left the face-down card out. Exactly right.'
          : 'Carry it on from here.';
    case HiLoSlip.countedHoleCard:
      return 'You counted the dealer\'s face-down card. It only counts '
          'once it is turned over.';
    case HiLoSlip.missedLastCard:
      final card = q.lastCard!;
      return 'One card behind: the ${card.rank.hiLoName} that just landed is '
          '${signedCount(hiLoTag(card))}. Add each card as it lands.';
    case HiLoSlip.flippedSign:
      return 'Right size, wrong sign. Low cards (2–6) are +1; tens and '
          'aces are −1.';
    case HiLoSlip.drift:
      final off = (result.given! - q.answer).abs();
      return 'Off by $off. Pick the count up from here — a low card and a '
          'high card cancel, so count them as pairs.';
    case HiLoSlip.timeUp:
      return 'Time\'s up. At a table the count has to be ready before the '
          'next bet — keep it running, don\'t rebuild it.';
  }
}

/// How far the streak is from the next multiplier.
String comboNote(int streak) {
  final combo = HiLoScoring.comboFor(streak);
  final toGo = HiLoScoring.toNextCombo(streak);
  if (toGo == null) return 'x$combo combo — the top multiplier. Keep it alive.';
  final next = HiLoScoring.comboFor(streak + toGo);
  return '$toGo more in a row for x$next.';
}

/// What to work on next, from the mistakes a game actually made. In
/// [survival] the pace and the table are not the player's to choose, so the
/// advice points at Practice instead.
String coachingTip(
  List<HiLoAnswer> answers,
  HiLoTrainingConfig config, {
  bool survival = false,
}) {
  final wrong = answers.where((a) => !a.correct).toList();
  if (answers.isEmpty) return 'Deal again and keep the count going.';
  final asked = answers.where((a) => a.trueCountAsked).toList();
  final tcMissed = asked.where((a) => a.trueCountCorrect != true).length;
  // The running counts held but the conversion did not.
  if (asked.isNotEmpty &&
      tcMissed * 2 > asked.length &&
      wrong.length * 2 <= answers.length) {
    return 'The running counts were there; the true counts were not. '
        'Read the decks left off the discard tray to the nearest half deck, '
        'then divide — rounding either way is fine.';
  }
  if (wrong.isEmpty && survival) {
    return 'No misses before you stopped. Run it to the end next time — '
        'the dealer only gets faster.';
  }
  if (wrong.isEmpty) {
    final faster = config.pace.faster;
    if (faster != null) {
      return 'Every count right. Try the ${faster.label} pace next.';
    }
    if (config.players < HiLoTrainingConfig.playerOptions.last) {
      return 'Every count right at casino pace. Add players — more cards '
          'land each round.';
    }
    return 'Every count right at a full table at casino pace. That is game '
        'speed.';
  }
  final tally = <HiLoSlip, int>{};
  for (final a in wrong) {
    tally[a.slip] = (tally[a.slip] ?? 0) + 1;
  }
  final top = tally.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return switch (top) {
    HiLoSlip.countedHoleCard =>
      'The dealer\'s face-down card kept creeping into your count. Leave it '
          'out until it is turned over, then add it.',
    HiLoSlip.missedLastCard =>
      'Your count was one card behind. Add each card as it lands, not a '
          'whole hand at a time.',
    HiLoSlip.flippedSign =>
      'The size was right but the sign was not: low cards (2–6) are +1, '
          'tens and aces −1.',
    HiLoSlip.timeUp => 'The clock beat you. Keep the count running as the '
        'cards land so the answer is already there when the dealer asks.',
    _ when survival => 'The count slipped as the dealer sped up. Practise '
        'at that pace in Practice, and cancel pairs — a low card and a high '
        'card together are 0.',
    _ => 'Try a slower pace or fewer players until the count holds, and '
        'cancel pairs — a low card and a high card together are 0.',
  };
}

/// 🟩 right, 🟥 wrong, ⬛ out of time. Long runs are cut short.
String answerGrid(List<HiLoAnswer> answers, {int limit = 20}) {
  final squares = [
    for (final a in answers.take(limit))
      a.correct ? '🟩' : (a.timedOut ? '⬛' : '🟥'),
  ].join();
  return answers.length > limit ? '$squares…' : squares;
}

/// The message a player sends a friend: the result, the grid, and a code
/// that deals the friend the same shoe.
String shareText(HiLoGame game) {
  final p = game.players.first;
  final spec = game.spec;
  final header = switch (spec.mode) {
    HiLoMode.daily =>
      'Hi-Lo Daily #${spec.dailyNumber} — ${points(p.score)} pts',
    HiLoMode.survival =>
      'Hi-Lo Survival — ${points(p.score)} pts, level ${game.level}',
    _ => 'Hi-Lo Training — ${points(p.score)} pts',
  };
  final code = game.toChallenge().encode();
  final tcAsked = p.answers.where((a) => a.trueCountAsked).length;
  final tcRight = p.answers.where((a) => a.trueCountCorrect == true).length;
  return '$header\n'
      '${answerGrid(p.answers)}\n'
      '${p.correct}/${p.answered} counts right · best streak ${p.bestStreak}\n'
      '${tcAsked > 0 ? 'True counts $tcRight/$tcAsked\n' : ''}\n'
      'Same shoe, your turn — challenge code $code\n'
      '(Hi-Lo Training → Enter a friend\'s code)\n'
      '$hiLoBlackjackPlayStoreUrl';
}

/// Today's official Daily score, shared from the hub after the game is gone.
String dailyShareText(int day, int score) {
  final code = HiLoChallenge(
    seed: HiLoDaily.seedFor(day),
    config: HiLoDaily.configFor(day),
    survival: false,
    score: score,
  ).encode();
  return 'Hi-Lo Daily #$day — ${points(score)} pts\n'
      'Same shoe, your turn — challenge code $code\n'
      '(Hi-Lo Training → Enter a friend\'s code)\n'
      '$hiLoBlackjackPlayStoreUrl';
}

/// "5h 12m" / "12m".
String countdown(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${max(1, m)}m';
}

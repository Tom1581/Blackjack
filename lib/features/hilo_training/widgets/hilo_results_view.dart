import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'hilo_button.dart';
import '../hilo_game.dart';
import '../hilo_text.dart';
import '../hilo_training_progress.dart';
import '../hilo_training_session.dart';
import 'count_quiz_panel.dart';
import 'hilo_badges.dart';

/// The end of a game: the score, how it was made, what it earned, and the
/// ways to go again.
class HiLoResultsView extends StatelessWidget {
  final HiLoGame game;

  /// Null for the moment the profile is still being saved.
  final HiLoGameReward? reward;
  final VoidCallback onPlayAgain;
  final VoidCallback onDone;

  /// Null where there is nothing to share (a duel).
  final void Function(BuildContext shareContext)? onShare;

  const HiLoResultsView({
    super.key,
    required this.game,
    required this.reward,
    required this.onPlayAgain,
    required this.onDone,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final spec = game.spec;
    final share = onShare;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spec.isDuel)
          _DuelHeadline(game: game)
        else
          _SoloHeadline(game: game, reward: reward),
        const SizedBox(height: 14),
        for (var i = 0; i < game.players.length; i++) ...[
          if (game.players.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                game.players[i].name.toUpperCase(),
                style: TextStyle(
                  color: duelColors[i],
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          _StatsRow(game: game, player: game.players[i]),
          const SizedBox(height: 8),
          AnswerSquares(answers: game.players[i].answers),
          const SizedBox(height: 14),
        ],
        if (reward != null) _RewardCard(reward: reward!),
        if (!spec.isDuel) ...[
          const SizedBox(height: 12),
          _Note(
            text: coachingTip(
              game.players.first.answers,
              spec.config,
              survival: spec.isSurvival,
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (share != null) ...[
          Builder(
            builder: (shareContext) => HiLoButton(
              label: 'CHALLENGE A FRIEND',
              icon: Icons.ios_share,
              onPressed: () => share(shareContext),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sends your score and a code that deals them this exact shoe.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 12),
        ],
        HiLoButton(
          label: _againLabel(spec),
          icon: Icons.refresh,
          outlined: share != null,
          onPressed: onPlayAgain,
        ),
        const SizedBox(height: 10),
        HiLoButton(label: 'DONE', outlined: true, onPressed: onDone),
      ],
    );
  }

  static String _againLabel(HiLoGameSpec spec) => switch (spec.mode) {
        HiLoMode.daily => 'REPLAY THIS SHOE',
        HiLoMode.duel => 'REMATCH',
        HiLoMode.challenge => 'TRY THIS SHOE AGAIN',
        _ => 'PLAY AGAIN',
      };
}

class _SoloHeadline extends StatelessWidget {
  final HiLoGame game;
  final HiLoGameReward? reward;

  const _SoloHeadline({required this.game, required this.reward});

  @override
  Widget build(BuildContext context) {
    final spec = game.spec;
    final player = game.players.first;
    final target = spec.targetScore;
    final (IconData icon, String title) = switch (spec.mode) {
      _ when spec.isChallenge => game.challengeWon
          ? (Icons.emoji_events, 'CHALLENGE WON')
          : (Icons.sports_score, 'SO CLOSE'),
      HiLoMode.survival => (
          Icons.heart_broken,
          'GAME OVER · LEVEL ${game.level}'
        ),
      HiLoMode.daily => (
          Icons.today,
          spec.ranked
              ? 'DAILY #${spec.dailyNumber} · OFFICIAL'
              : 'DAILY #${spec.dailyNumber} · REPLAY'
        ),
      _ => player.perfect && player.answered > 0
          ? (Icons.workspace_premium, 'PERFECT COUNT')
          : (Icons.insights, 'GAME COMPLETE'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold, size: 36),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: player.score),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => Text(
              points(v),
              key: const ValueKey('hilo-final-score'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            'POINTS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.5,
            ),
          ),
          if (reward?.newBest == true) ...[
            const SizedBox(height: 10),
            const _Ribbon(text: 'NEW PERSONAL BEST'),
          ],
          if (target != null) ...[
            const SizedBox(height: 10),
            Text(
              'Your friend scored ${points(target)}',
              style: TextStyle(
                color: game.challengeWon
                    ? AppColors.favorable
                    : Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (!spec.ranked) ...[
            const SizedBox(height: 8),
            Text(
              spec.mode == HiLoMode.daily
                  ? 'Replays are practice — the first game of the day is the '
                      'one that counts.'
                  : 'A replay of a shoe you have seen is practice — no XP, '
                      'records or wins.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DuelHeadline extends StatelessWidget {
  final HiLoGame game;

  const _DuelHeadline({required this.game});

  @override
  Widget build(BuildContext context) {
    final winner = game.winner;
    final title = winner == null
        ? 'IT\'S A DRAW'
        : '${game.players[winner].name.toUpperCase()} WINS';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (winner == null ? AppColors.gold : duelColors[winner])
              .withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Icon(
            winner == null ? Icons.handshake_outlined : Icons.emoji_events,
            color: winner == null ? AppColors.gold : duelColors[winner],
            size: 38,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            key: const ValueKey('hilo-duel-title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: winner == null ? AppColors.gold : duelColors[winner],
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < game.players.length; i++) ...[
                if (i > 0)
                  Text(
                    'vs',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (winner == i)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.star,
                                  size: 16, color: duelColors[i]),
                            ),
                          Flexible(
                            child: Text(
                              game.players[i].name.toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: duelColors[i],
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        points(game.players[i].score),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final HiLoGame game;
  final HiLoPlayer player;

  const _StatsRow({required this.game, required this.player});

  @override
  Widget build(BuildContext context) {
    final answered = player.answered;
    final avgMs = answered == 0
        ? 0
        : player.answers.fold<int>(0, (s, a) => s + a.took.inMilliseconds) ~/
            answered;
    final tcAsked = player.answers.where((a) => a.trueCountAsked).length;
    final tcRight =
        player.answers.where((a) => a.trueCountCorrect == true).length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Stat(label: 'RIGHT', value: '${player.correct}/$answered'),
        _Stat(label: 'BEST STREAK', value: '${player.bestStreak}'),
        _Stat(
          label: 'AVG ANSWER',
          value: '${seconds(Duration(milliseconds: avgMs))}s',
        ),
        if (tcAsked > 0) _Stat(label: 'TRUE COUNT', value: '$tcRight/$tcAsked'),
        if (game.spec.isSurvival) _Stat(label: 'LEVEL', value: '${game.level}'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// One square per question: green right, red wrong, grey out of time.
class AnswerSquares extends StatelessWidget {
  final List<HiLoAnswer> answers;

  const AnswerSquares({super.key, required this.answers});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (var i = 0; i < answers.length; i++)
          Tooltip(
            message:
                'Q${i + 1}: count ${signedCount(answers[i].question.answer)}'
                '${answers[i].timedOut ? ', no answer' : ', you said ${signedCount(answers[i].given!)}'}',
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: answers[i].correct
                    ? AppColors.favorable
                    : (answers[i].timedOut
                        ? Colors.white24
                        : AppColors.unfavorable),
                borderRadius: BorderRadius.circular(5),
              ),
              child: answers[i].points.combo > 1
                  ? Center(
                      child: Text(
                        '×${answers[i].points.combo}',
                        style: const TextStyle(
                          color: AppColors.wood,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _RewardCard extends StatelessWidget {
  final HiLoGameReward reward;

  const _RewardCard({required this.reward});

  @override
  Widget build(BuildContext context) {
    final after = reward.after;
    final rank = after.rank;
    final next = rank.next;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rankColor(rank).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RankEmblem(rank: rank, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reward.rankUp != null)
                      const Text(
                        'RANK UP!',
                        style: TextStyle(
                          color: AppColors.favorable,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    Text(
                      rank.title,
                      style: TextStyle(
                        color: rankColor(rank),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    TweenAnimationBuilder<double>(
                      tween: Tween(
                        begin: reward.rankUp != null
                            ? 0
                            : rank.progress(reward.before.xp),
                        end: rank.progress(after.xp),
                      ),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) =>
                          HiLoProgressBar(progress: v, color: rankColor(rank)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      next == null
                          ? '${points(after.xp)} XP · top rank'
                          : '${points(after.xp)} XP · ${points(next.xp - after.xp)} to ${next.title}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                reward.xpGained > 0 ? '+${reward.xpGained} XP' : 'no XP',
                key: const ValueKey('hilo-xp'),
                style: TextStyle(
                  color: reward.xpGained > 0
                      ? AppColors.goldLight
                      : Colors.white38,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (reward.unlocked.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'ACHIEVEMENT UNLOCKED',
              style: TextStyle(
                color: AppColors.gold,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.8,
              ),
            ),
            const SizedBox(height: 8),
            for (final a in reward.unlocked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    AchievementBadge(achievement: a, unlocked: true, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            a.description,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  final String text;
  const _Ribbon({required this.text});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFE680), AppColors.gold, Color(0xFFB8860B)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.5),
              blurRadius: 14,
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.wood,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.gold.withValues(alpha: 0.95),
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

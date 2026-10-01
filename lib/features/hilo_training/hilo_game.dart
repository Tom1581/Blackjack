import 'dart:math';

import 'hilo_scoring.dart';
import 'hilo_training_session.dart';
import 'seeded_random.dart';

/// The ways to play Hi-Lo Training.
enum HiLoMode {
  /// Your table, your pace, no clock.
  practice('Practice'),

  /// The same shoe for everyone today, on the clock.
  daily('Daily Challenge'),

  /// Three lives; the dealer speeds up as you go.
  survival('Survival'),

  /// Two players on one phone, answering in secret.
  duel('Duel'),

  /// A friend's shoe, from a code, with their score to beat.
  challenge('Challenge');

  const HiLoMode(this.label);
  final String label;
}

/// Everything that decides a game before the first card: the mode, the
/// table, the shoe's seed and who is playing.
class HiLoGameSpec {
  /// Seeds fit in 20 bits so any game can travel in a challenge code.
  static const seedBits = 20;
  static const _endless = 1 << 30;

  /// The answer clock in the ranked modes.
  static const rankedAnswerLimit = Duration(seconds: 15);

  final HiLoMode mode;
  final HiLoTrainingConfig config;
  final int seed;
  final List<String> playerNames;

  /// Null for no clock.
  final Duration? answerLimit;

  /// The Daily Challenge number, for a daily game.
  final int? dailyNumber;

  /// A friend's score to beat, from a challenge code.
  final int? targetScore;

  /// Whether the game counts: XP, bests, records, wins. False for a replay
  /// of a shoe already seen — the day's Daily after the first try, or a
  /// friend's challenge played again — where the cards can be remembered.
  final bool ranked;

  const HiLoGameSpec({
    required this.mode,
    required this.config,
    required this.seed,
    this.playerNames = const ['You'],
    this.answerLimit,
    this.dailyNumber,
    this.targetScore,
    this.ranked = true,
  });

  static int randomSeed([Random? rng]) =>
      (rng ?? Random()).nextInt(1 << seedBits);

  factory HiLoGameSpec.practice(HiLoTrainingConfig config, {int? seed}) =>
      HiLoGameSpec(
        mode: HiLoMode.practice,
        config: config,
        seed: seed ?? randomSeed(),
      );

  factory HiLoGameSpec.daily(int number, {bool ranked = true}) => HiLoGameSpec(
        mode: HiLoMode.daily,
        config: HiLoDaily.configFor(number),
        seed: HiLoDaily.seedFor(number),
        answerLimit: rankedAnswerLimit,
        dailyNumber: number,
        ranked: ranked,
      );

  factory HiLoGameSpec.survival({
    int? seed,
    int? targetScore,
    bool ranked = true,
  }) =>
      HiLoGameSpec(
        mode: HiLoMode.survival,
        config: HiLoTrainingConfig(
          players: SurvivalLevel.playersFor(1),
          decks: 6,
          frequency: HiLoQuizFrequency.often,
          questions: _endless,
        ),
        seed: seed ?? randomSeed(),
        answerLimit: SurvivalLevel.answerLimit,
        targetScore: targetScore,
        ranked: ranked,
      );

  factory HiLoGameSpec.duel({
    required List<String> names,
    required int questions,
    required HiLoPace pace,
    int? seed,
  }) =>
      HiLoGameSpec(
        mode: HiLoMode.duel,
        config: HiLoTrainingConfig(
          players: 3,
          decks: 6,
          pace: pace,
          frequency: HiLoQuizFrequency.often,
          questions: questions,
        ),
        seed: seed ?? randomSeed(),
        playerNames: names,
      );

  /// The game a code describes: a Survival run, or a fixed-length game on
  /// the clock.
  factory HiLoGameSpec.fromChallenge(HiLoChallenge c) => c.survival
      ? HiLoGameSpec.survival(seed: c.seed, targetScore: c.score)
      : HiLoGameSpec(
          mode: HiLoMode.challenge,
          config: c.config,
          seed: c.seed,
          answerLimit: rankedAnswerLimit,
          targetScore: c.score,
        );

  /// The spec for "play again": a fresh shoe where the mode deals one; the
  /// same shoe, unranked, for a daily or a friend's challenge.
  HiLoGameSpec again() => switch (mode) {
        HiLoMode.practice => HiLoGameSpec.practice(config),
        HiLoMode.daily => HiLoGameSpec.daily(dailyNumber!, ranked: false),
        HiLoMode.survival => isChallenge
            ? HiLoGameSpec.survival(
                seed: seed,
                targetScore: targetScore,
                ranked: false,
              )
            : HiLoGameSpec.survival(),
        HiLoMode.duel => HiLoGameSpec.duel(
            names: playerNames,
            questions: config.questions,
            pace: config.pace,
          ),
        HiLoMode.challenge => HiLoGameSpec(
            mode: mode,
            config: config,
            seed: seed,
            answerLimit: answerLimit,
            targetScore: targetScore,
            ranked: false,
          ),
      };

  /// This game asks for the true count after each running count.
  bool get asksTrueCount => config.trueCount && !isDuel;

  bool get isSurvival => mode == HiLoMode.survival;
  bool get isDuel => mode == HiLoMode.duel;
  bool get isChallenge => targetScore != null;
}

/// One player's side of a game.
class HiLoPlayer {
  final String name;
  int score = 0;
  int streak = 0;
  int bestStreak = 0;
  final List<HiLoAnswer> answers = [];

  HiLoPlayer(this.name);

  int get correct => answers.where((a) => a.correct).length;
  int get answered => answers.length;
  int get combo => HiLoScoring.comboFor(streak);
  bool get perfect => answers.isNotEmpty && answers.every((a) => a.correct);
}

/// What closing a question changed.
class HiLoResolution {
  /// Every player's answer, in player order.
  final List<HiLoAnswer> answers;
  final bool lifeLost;

  /// The level just reached in Survival, if this question reached one.
  final int? newLevel;

  const HiLoResolution({
    required this.answers,
    this.lifeLost = false,
    this.newLevel,
  });
}

/// A game in progress: the dealer's session plus the scoreboard.
///
/// Flow: when [quizDue], [ask]; then [submit] once per player (in a duel
/// they take turns going first). After the last player, the question closes
/// and [lastResolution] says what changed. The game [isOver] when the
/// questions run out, or in Survival when the lives do.
class HiLoGame {
  final HiLoGameSpec spec;
  final HiLoTrainingSession session;
  final List<HiLoPlayer> players;
  int lives;
  int level = 1;

  int _turn = 0;
  final Map<int, HiLoAnswer> _pending = {};

  /// A running count given and waiting for its true count.
  ({int given, Duration took})? _running;

  /// Every player's standing when the open question was asked, so a game
  /// ended part-way through a question can take back the half-answered
  /// question.
  List<({int score, int streak, int bestStreak, int answered})> _before = [];
  HiLoResolution? _lastResolution;
  bool _quit = false;

  HiLoGame(this.spec)
      : session =
            HiLoTrainingSession(spec.config, rng: SeededRandom(spec.seed)),
        players = [for (final name in spec.playerNames) HiLoPlayer(name)],
        lives = spec.isSurvival ? SurvivalLevel.lives : 0;

  /// Time each card stays the newest on the felt.
  Duration get pace =>
      spec.isSurvival ? SurvivalLevel.paceFor(level) : spec.config.pace.perCard;

  HiLoQuestion? get question => session.openQuestion;

  /// Whose answer is wanted now.
  int get turn => _turn;
  HiLoPlayer get turnPlayer => players[_turn];

  /// Some players have answered the open question and others have not.
  bool get midQuestion => question != null && _pending.isNotEmpty;

  /// The running count is in; the true count is next.
  bool get awaitingTrueCount => _running != null;

  /// The running count just given, while the true count is asked for.
  int? get pendingRunningCount => _running?.given;

  HiLoResolution? get lastResolution => _lastResolution;

  bool get isOver =>
      _quit ||
      (spec.isSurvival ? lives <= 0 : session.isFinished && question == null);

  /// The question being asked, counting from 1.
  int get questionNumber =>
      session.questionsClosed + (question != null ? 1 : 0);

  /// Questions in the game, or null for Survival, which runs until the
  /// lives do.
  int? get questionCount => spec.isSurvival ? null : spec.config.questions;

  bool get quizDue => !isOver && session.quizDue;

  HiLoQuestion ask() {
    final q = session.ask();
    _pending.clear();
    _running = null;
    _lastResolution = null;
    _before = [
      for (final p in players)
        (
          score: p.score,
          streak: p.streak,
          bestStreak: p.bestStreak,
          answered: p.answered,
        ),
    ];
    // In a duel the first answer alternates, so nobody always gets the
    // extra thinking time.
    _turn = session.questionsClosed % players.length;
    return q;
  }

  /// Record the current player's running count ([given] null when their
  /// clock ran out). Once everyone has answered, the question closes.
  ///
  /// In a game that [asksTrueCount], a running count given in time is held
  /// and null is returned: [submitTrueCount] completes the answer.
  HiLoAnswer? submit(int? given, {Duration took = Duration.zero}) {
    if (question == null) {
      throw StateError('submit() called with no question open');
    }
    if (_running != null) {
      throw StateError('submit() called while a true count is awaited');
    }
    if (spec.asksTrueCount && given != null) {
      _running = (given: given, took: took);
      return null;
    }
    return _record(given, took);
  }

  /// The true count for the running count just given ([trueCount] null when
  /// the clock ran out).
  HiLoAnswer submitTrueCount(int? trueCount) {
    final running = _running;
    if (running == null) {
      throw StateError('submitTrueCount() called with no running count');
    }
    _running = null;
    return _record(
      running.given,
      running.took,
      trueCountAsked: true,
      trueCountGiven: trueCount,
    );
  }

  HiLoAnswer _record(
    int? given,
    Duration took, {
    bool trueCountAsked = false,
    int? trueCountGiven,
  }) {
    final q = question!;
    final player = players[_turn];
    final correct = given == q.answer;
    final streak = correct ? player.streak + 1 : 0;
    var points =
        HiLoScoring.score(correct: correct, took: took, streak: streak);
    final tcRight = HiLoAnswer(
          question: q,
          given: given,
          trueCountAsked: trueCountAsked,
          trueCountGiven: trueCountGiven,
        ).trueCountCorrect ==
        true;
    if (tcRight) points = points.withTrueCount(HiLoScoring.trueCountBonus);
    final answer = HiLoAnswer(
      question: q,
      given: given,
      took: took,
      points: points,
      trueCountAsked: trueCountAsked,
      trueCountGiven: trueCountGiven,
    );
    player.answers.add(answer);
    player.streak = streak;
    player.bestStreak = max(player.bestStreak, streak);
    player.score += answer.points.total;
    _pending[_turn] = answer;

    if (_pending.length < players.length) {
      _turn = (_turn + 1) % players.length;
    } else {
      _resolve();
    }
    return answer;
  }

  void _resolve() {
    session.close();
    var lifeLost = false;
    int? newLevel;
    if (spec.isSurvival) {
      if (!_pending[0]!.correct) {
        lives--;
        lifeLost = true;
      } else {
        final reached = SurvivalLevel.levelFor(players.first.correct);
        if (reached > level) {
          level = reached;
          newLevel = reached;
          session.setPlayers(SurvivalLevel.playersFor(reached));
        }
      }
    }
    _lastResolution = HiLoResolution(
      answers: [for (var i = 0; i < players.length; i++) _pending[i]!],
      lifeLost: lifeLost,
      newLevel: newLevel,
    );
    _pending.clear();
  }

  /// Stop early. The game ends with the questions everyone has answered: a
  /// duel question only one player got to is taken back, so it cannot decide
  /// the winner.
  void quit() {
    if (midQuestion) {
      for (var i = 0; i < players.length; i++) {
        final p = players[i];
        final b = _before[i];
        p
          ..score = b.score
          ..streak = b.streak
          ..bestStreak = b.bestStreak;
        p.answers.removeRange(b.answered, p.answers.length);
      }
      _pending.clear();
    }
    _quit = true;
  }

  /// The duel winner, or null for a draw or a one-player game.
  int? get winner {
    if (players.length < 2) return null;
    final a = players[0].score;
    final b = players[1].score;
    if (a == b) return null;
    return a > b ? 0 : 1;
  }

  /// Beat the friend's score — on a first try at their shoe.
  bool get challengeWon {
    final target = spec.targetScore;
    return target != null && spec.ranked && players.first.score > target;
  }

  /// Every question was asked and answered: not quit part-way.
  bool get completed =>
      !_quit && (spec.isSurvival ? lives <= 0 : session.isFinished);

  /// This game as a code a friend can play, carrying [score].
  HiLoChallenge toChallenge() => HiLoChallenge(
        seed: spec.seed,
        config: spec.config,
        survival: spec.isSurvival,
        score: players.first.score,
      );
}

/// Today's shoe. Every phone deals the same one, so scores are comparable.
class HiLoDaily {
  const HiLoDaily._();

  /// Daily #1 is 2026-09-29.
  static final _epoch = DateTime.utc(2026, 9, 28);
  static const questions = 10;

  /// A different table each day of the week, easiest first.
  static const _tables = [
    (players: 2, decks: 6, pace: HiLoPace.steady),
    (players: 3, decks: 6, pace: HiLoPace.steady),
    (players: 3, decks: 2, pace: HiLoPace.brisk),
    (players: 4, decks: 6, pace: HiLoPace.brisk),
    (players: 3, decks: 8, pace: HiLoPace.brisk),
    (players: 5, decks: 6, pace: HiLoPace.brisk),
    (players: 4, decks: 6, pace: HiLoPace.casino),
  ];

  /// The challenge number for the local calendar day of [now]. A clock set
  /// before launch day still gets #1 rather than a number below it.
  static int numberFor(DateTime now) => max(
        1,
        DateTime.utc(now.year, now.month, now.day).difference(_epoch).inDays,
      );

  static HiLoTrainingConfig configFor(int number) {
    final t = _tables[number % _tables.length];
    return HiLoTrainingConfig(
      players: t.players,
      decks: t.decks,
      pace: t.pace,
      frequency: HiLoQuizFrequency.often,
      questions: questions,
    );
  }

  static int seedFor(int number) =>
      ((number + 1) * 2654435761 + 0x5EED) & ((1 << HiLoGameSpec.seedBits) - 1);

  /// Time left until tomorrow's shoe.
  static Duration untilNext(DateTime now) =>
      DateTime(now.year, now.month, now.day + 1).difference(now);
}

/// A game packed into a short code: the shoe, the table, and the score to
/// beat. A friend who enters it is dealt exactly the same cards.
///
/// Ten characters carry the game; the eleventh is a Luhn mod 32 check
/// character, which catches every single mistyped character and almost
/// every swapped pair, so a typo is refused rather than dealing some other
/// shoe. Codes are not signed — a friend could type in a made-up score —
/// which is fine between friends and why they are not a leaderboard.
class HiLoChallenge {
  static const maxScore = (1 << 17) - 1;
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _payloadChars = 10;

  final int seed;
  final HiLoTrainingConfig config;
  final bool survival;
  final int score;

  const HiLoChallenge({
    required this.seed,
    required this.config,
    required this.survival,
    required this.score,
  });

  static const _seedBits = HiLoGameSpec.seedBits;

  /// 50 bits of fields: exactly ten 5-bit characters.
  static const _payloadBits = _seedBits + 3 + 2 + 2 + 2 + 2 + 1 + 1 + 17;

  String encode() {
    var v = _payloadOf(this);
    final digits = List.filled(_payloadChars, 0);
    for (var i = _payloadChars - 1; i >= 0; i--) {
      digits[i] = v % 32;
      v ~/= 32;
    }
    final s = [...digits, _luhn32(digits)].map((d) => _alphabet[d]).join();
    return '${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8)}';
  }

  /// The challenge in [text], or null if it is not a valid code. Case,
  /// dashes, spaces and the look-alikes O, I and L are forgiven.
  static HiLoChallenge? decode(String text) {
    final clean = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (clean.length != _payloadChars + 1) return null;
    final digits = [for (final ch in clean.split('')) _alphabet.indexOf(ch)];
    if (digits.contains(-1)) return null;
    final payload = digits.sublist(0, _payloadChars);
    if (_luhn32(payload) != digits.last) return null;

    var v = payload.fold(0, (n, d) => n * 32 + d);
    if (v >= 1 << _payloadBits) return null;

    int take(int bits) {
      final unit = 1 << bits;
      final field = v % unit;
      v ~/= unit;
      return field;
    }

    final seed = take(_seedBits);
    final players = take(3) + 1;
    final deckIndex = take(2);
    final paceIndex = take(2);
    final frequencyIndex = take(2);
    final questionIndex = take(2);
    final survival = take(1) == 1;
    final trueCount = take(1) == 1;
    final score = take(17);

    if (players > HiLoTrainingConfig.playerOptions.last ||
        deckIndex >= HiLoTrainingConfig.deckOptions.length ||
        paceIndex >= HiLoPace.values.length ||
        frequencyIndex >= HiLoQuizFrequency.values.length ||
        questionIndex >= HiLoTrainingConfig.questionOptions.length) {
      return null;
    }
    return HiLoChallenge(
      seed: seed,
      config: HiLoTrainingConfig(
        players: players,
        decks: HiLoTrainingConfig.deckOptions[deckIndex],
        pace: HiLoPace.values[paceIndex],
        frequency: HiLoQuizFrequency.values[frequencyIndex],
        questions: HiLoTrainingConfig.questionOptions[questionIndex],
        trueCount: trueCount,
      ),
      survival: survival,
      score: score,
    );
  }

  /// The Luhn mod N check character for base-32 [digits].
  static int _luhn32(List<int> digits) {
    var factor = 2;
    var sum = 0;
    for (var i = digits.length - 1; i >= 0; i--) {
      final addend = factor * digits[i];
      sum += addend ~/ 32 + addend % 32;
      factor = factor == 2 ? 1 : 2;
    }
    return (32 - sum % 32) % 32;
  }

  /// The fields packed low to high: seed, players, decks, pace, frequency,
  /// questions, survival, true count, score.
  static int _payloadOf(HiLoChallenge c) {
    var v = 0;
    var shift = 1;
    void put(int value, int bits) {
      v += value * shift;
      shift *= 1 << bits;
    }

    put(c.seed & ((1 << _seedBits) - 1), _seedBits);
    put(c.config.players - 1, 3);
    put(HiLoTrainingConfig.deckOptions.indexOf(c.config.decks), 2);
    put(c.config.pace.index, 2);
    put(c.config.frequency.index, 2);
    put(max(0, HiLoTrainingConfig.questionOptions.indexOf(c.config.questions)),
        2);
    put(c.survival ? 1 : 0, 1);
    put(c.config.trueCount ? 1 : 0, 1);
    put(min(c.score, maxScore), 17);
    return v;
  }
}

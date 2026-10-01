import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../training/drills.dart' show hiLoTag;
import 'hilo_game.dart';
import 'hilo_scoring.dart';
import 'hilo_training_session.dart';

/// Ranks earned with XP — one XP for every ten points scored.
enum HiLoRank {
  rookie('Rookie', 0),
  cardWatcher('Card Watcher', 300),
  counter('Counter', 1000),
  shoeReader('Shoe Reader', 2500),
  advantagePlayer('Advantage Player', 5000),
  pitBossNightmare('Pit Boss\'s Nightmare', 10000),
  legend('Legend', 20000);

  const HiLoRank(this.title, this.xp);
  final String title;

  /// XP needed to reach this rank.
  final int xp;

  static HiLoRank forXp(int xp) =>
      values.lastWhere((r) => xp >= r.xp, orElse: () => rookie);

  HiLoRank? get next => index + 1 < values.length ? values[index + 1] : null;

  /// 0–1 of the way from this rank to the next.
  double progress(int xp) {
    final n = next;
    if (n == null) return 1;
    return ((xp - this.xp) / (n.xp - this.xp)).clamp(0.0, 1.0);
  }
}

enum HiLoAchievement {
  firstCount('First Count', 'Get a count right.'),
  quickDraw('Quick Draw', 'A right count in under 2 seconds.'),
  pokerFace('Poker Face',
      'Count right 10 times while the dealer\'s card is face down.'),
  perfectTen('Perfect Ten', '10 right with no misses in one game.'),
  casinoSpeed('Casino Speed', 'A perfect game at Casino pace.'),
  fullHouse('Full House', '10 in a row at a table of five.'),
  unshakeable('Unshakeable', 'A streak of 25.'),
  survivor('Survivor', '20 right in one Survival run.'),
  pitBoss('Pit Boss Material', 'Reach level 7 in Survival.'),
  regular('Regular', 'Play the Daily Challenge 3 days running.'),
  everyDay('Every Shoe, Every Day', 'Play the Daily Challenge 7 days running.'),
  duelist('Duelist', 'Finish a duel.'),
  challengeAccepted('Challenge Accepted', 'Beat a friend\'s challenge score.'),
  centurion('Centurion', '100 right counts in all.'),
  trueBeliever('True Believer', '10 true counts right.');

  const HiLoAchievement(this.title, this.description);
  final String title;
  final String description;
}

/// Everything Hi-Lo Training remembers about the player on this device.
class HiLoProfile {
  static const survivalTopSize = 5;
  static const dailyHistorySize = 30;

  final int xp;

  // Lifetime totals over the one-player modes.
  final int games;
  final int questions;
  final int correct;
  final int bestStreak;

  /// Right counts given while the dealer's hole card was face down and not
  /// a 7–9 — the answers where counting it would have been wrong.
  final int holeCardReads;

  final int practiceBest;
  final List<int> survivalTop;
  final int survivalBestLevel;

  final int? dailyLastPlayed;
  final int dailyStreak;

  /// Daily Challenge number → official score (the first game that day).
  final Map<int, int> dailyScores;

  final int duels;
  final int challengesWon;
  final Set<HiLoAchievement> achievements;

  /// True counts asked and got right, in games that ask for them.
  final int trueCountsAsked;
  final int trueCountsRight;

  /// Wrong running counts by what most likely went wrong — the habit worth
  /// working on.
  final Map<HiLoSlip, int> slips;

  const HiLoProfile({
    this.xp = 0,
    this.games = 0,
    this.questions = 0,
    this.correct = 0,
    this.bestStreak = 0,
    this.holeCardReads = 0,
    this.practiceBest = 0,
    this.survivalTop = const [],
    this.survivalBestLevel = 0,
    this.dailyLastPlayed,
    this.dailyStreak = 0,
    this.dailyScores = const {},
    this.duels = 0,
    this.challengesWon = 0,
    this.achievements = const {},
    this.trueCountsAsked = 0,
    this.trueCountsRight = 0,
    this.slips = const {},
  });

  HiLoRank get rank => HiLoRank.forXp(xp);

  /// The mistake made most often, once there have been a few to go on.
  HiLoSlip? get commonSlip {
    final counted = slips.entries.where((e) => e.value > 0).toList();
    if (counted.fold(0, (n, e) => n + e.value) < 3) return null;
    return counted.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  int get accuracy => questions == 0 ? 0 : (correct * 100 / questions).round();
  int get survivalBest => survivalTop.isEmpty ? 0 : survivalTop.first;
  int get dailyBest => dailyScores.values.fold(0, max);

  bool playedDaily(int number) => dailyScores.containsKey(number);

  /// The daily streak as it stands on day [today]: a streak whose last game
  /// was before yesterday has lapsed.
  int dailyStreakOn(int today) {
    final last = dailyLastPlayed;
    if (last == null || today - last > 1) return 0;
    return dailyStreak;
  }

  HiLoProfile copyWith({
    int? xp,
    int? games,
    int? questions,
    int? correct,
    int? bestStreak,
    int? holeCardReads,
    int? practiceBest,
    List<int>? survivalTop,
    int? survivalBestLevel,
    int? dailyLastPlayed,
    int? dailyStreak,
    Map<int, int>? dailyScores,
    int? duels,
    int? challengesWon,
    Set<HiLoAchievement>? achievements,
    int? trueCountsAsked,
    int? trueCountsRight,
    Map<HiLoSlip, int>? slips,
  }) =>
      HiLoProfile(
        xp: xp ?? this.xp,
        games: games ?? this.games,
        questions: questions ?? this.questions,
        correct: correct ?? this.correct,
        bestStreak: bestStreak ?? this.bestStreak,
        holeCardReads: holeCardReads ?? this.holeCardReads,
        practiceBest: practiceBest ?? this.practiceBest,
        survivalTop: survivalTop ?? this.survivalTop,
        survivalBestLevel: survivalBestLevel ?? this.survivalBestLevel,
        dailyLastPlayed: dailyLastPlayed ?? this.dailyLastPlayed,
        dailyStreak: dailyStreak ?? this.dailyStreak,
        dailyScores: dailyScores ?? this.dailyScores,
        duels: duels ?? this.duels,
        challengesWon: challengesWon ?? this.challengesWon,
        achievements: achievements ?? this.achievements,
        trueCountsAsked: trueCountsAsked ?? this.trueCountsAsked,
        trueCountsRight: trueCountsRight ?? this.trueCountsRight,
        slips: slips ?? this.slips,
      );

  Map<String, dynamic> toJson() => {
        'xp': xp,
        'games': games,
        'questions': questions,
        'correct': correct,
        'bestStreak': bestStreak,
        'holeCardReads': holeCardReads,
        'practiceBest': practiceBest,
        'survivalTop': survivalTop,
        'survivalBestLevel': survivalBestLevel,
        if (dailyLastPlayed != null) 'dailyLastPlayed': dailyLastPlayed,
        'dailyStreak': dailyStreak,
        'dailyScores': {
          for (final e in dailyScores.entries) '${e.key}': e.value,
        },
        'duels': duels,
        'challengesWon': challengesWon,
        'achievements': [
          for (final a in HiLoAchievement.values)
            if (achievements.contains(a)) a.name,
        ],
        'trueCountsAsked': trueCountsAsked,
        'trueCountsRight': trueCountsRight,
        'slips': {
          for (final s in HiLoSlip.values)
            if ((slips[s] ?? 0) > 0) s.name: slips[s],
        },
      };

  /// Lenient: a missing or malformed field reads as its default, so a bad
  /// save costs one field rather than the whole profile.
  factory HiLoProfile.fromJson(Map<String, dynamic> json) {
    int i(String key) => json[key] is int ? json[key] as int : 0;
    final scores = <int, int>{};
    final rawScores = json['dailyScores'];
    if (rawScores is Map) {
      for (final e in rawScores.entries) {
        final day = int.tryParse('${e.key}');
        if (day != null && e.value is int) scores[day] = e.value as int;
      }
    }
    final names = json['achievements'];
    final top = json['survivalTop'];
    final rawSlips = json['slips'];
    return HiLoProfile(
      xp: i('xp'),
      games: i('games'),
      questions: i('questions'),
      correct: i('correct'),
      bestStreak: i('bestStreak'),
      holeCardReads: i('holeCardReads'),
      practiceBest: i('practiceBest'),
      survivalTop: top is List
          ? [
              for (final s in top)
                if (s is int) s
            ]
          : [],
      survivalBestLevel: i('survivalBestLevel'),
      dailyLastPlayed: json['dailyLastPlayed'] is int
          ? json['dailyLastPlayed'] as int
          : null,
      dailyStreak: i('dailyStreak'),
      dailyScores: scores,
      duels: i('duels'),
      challengesWon: i('challengesWon'),
      achievements: {
        if (names is List)
          for (final a in HiLoAchievement.values)
            if (names.contains(a.name)) a,
      },
      trueCountsAsked: i('trueCountsAsked'),
      trueCountsRight: i('trueCountsRight'),
      slips: {
        if (rawSlips is Map)
          for (final s in HiLoSlip.values)
            if (rawSlips[s.name] is int) s: rawSlips[s.name] as int,
      },
    );
  }
}

/// What one finished game did to the profile.
class HiLoGameReward {
  final HiLoProfile before;
  final HiLoProfile after;
  final int xpGained;
  final List<HiLoAchievement> unlocked;

  /// A personal best for the mode.
  final bool newBest;

  /// False for a replay of a shoe already seen: no XP, bests or wins.
  final bool ranked;

  const HiLoGameReward({
    required this.before,
    required this.after,
    required this.xpGained,
    required this.unlocked,
    required this.newBest,
    required this.ranked,
  });

  HiLoRank? get rankUp => after.rank != before.rank ? after.rank : null;
}

/// The day's ranked attempt has begun: it counts toward the streak, and the
/// day's score stands at 0 until the game finishes. Marking it at the start
/// means leaving a bad run and replaying the shoe you have now seen does not
/// get a second ranked go.
HiLoProfile startDaily(HiLoProfile p, int day) {
  if (p.playedDaily(day)) return p;
  final streak = p.dailyLastPlayed == day - 1 ? p.dailyStreak + 1 : 1;
  final keep = ({...p.dailyScores, day: 0}.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key)))
      .take(HiLoProfile.dailyHistorySize);
  return p.copyWith(
    dailyLastPlayed: day,
    dailyStreak: streak,
    dailyScores: {for (final e in keep) e.key: e.value},
  );
}

/// Folds a finished game into the profile. Pure, so every rule is tested
/// without storage.
HiLoGameReward applyGame(HiLoProfile before, HiLoGame game) {
  final spec = game.spec;
  var p = before;
  var xp = 0;
  var newBest = false;
  var ranked = true;

  if (spec.isDuel) {
    // Only a finished duel counts — quitting one is not worth XP.
    if (game.completed) {
      p = p.copyWith(duels: p.duels + 1);
      xp = 30;
    }
  } else {
    final player = game.players.first;
    final score = player.score;
    final holeReads = player.answers.where((a) {
      final hole = a.question.holeCardDown;
      return a.correct && hole != null && hiLoTag(hole) != 0;
    }).length;
    final slips = {...p.slips};
    for (final a in player.answers.where((a) => !a.correct)) {
      slips[a.slip] = (slips[a.slip] ?? 0) + 1;
    }
    final tcAsked = player.answers.where((a) => a.trueCountAsked).length;
    final tcRight =
        player.answers.where((a) => a.trueCountCorrect == true).length;
    p = p.copyWith(
      games: p.games + 1,
      questions: p.questions + player.answered,
      correct: p.correct + player.correct,
      bestStreak: max(p.bestStreak, player.bestStreak),
      holeCardReads: p.holeCardReads + holeReads,
      slips: slips,
      trueCountsAsked: p.trueCountsAsked + tcAsked,
      trueCountsRight: p.trueCountsRight + tcRight,
    );
    xp = score ~/ 10;
    if (!spec.ranked) {
      // A shoe already seen: practice for the counts, nothing for the
      // records.
      ranked = false;
      xp = 0;
    }

    if (ranked) {
      switch (spec.mode) {
        case HiLoMode.practice:
          newBest = score > p.practiceBest && score > 0;
          p = p.copyWith(practiceBest: max(p.practiceBest, score));
        case HiLoMode.survival:
          newBest = score > p.survivalBest && score > 0;
          final top = [...p.survivalTop, score]..sort((a, b) => b.compareTo(a));
          p = p.copyWith(
            survivalTop: top.take(HiLoProfile.survivalTopSize).toList(),
            survivalBestLevel: max(p.survivalBestLevel, game.level),
          );
        case HiLoMode.daily:
          final day = spec.dailyNumber!;
          final otherDays = {...p.dailyScores}..remove(day);
          newBest = score > otherDays.values.fold(0, max) && score > 0;
          p = startDaily(p, day);
          p = p.copyWith(dailyScores: {...p.dailyScores, day: score});
          xp += 50;
        case HiLoMode.challenge:
        case HiLoMode.duel:
          break;
      }
    }
    if (game.challengeWon) {
      p = p.copyWith(challengesWon: p.challengesWon + 1);
    }
  }

  p = p.copyWith(xp: p.xp + xp);
  final earned =
      _earned(p, game, ranked: ranked).difference(before.achievements);
  p = p.copyWith(achievements: {...before.achievements, ...earned});
  return HiLoGameReward(
    before: before,
    after: p,
    xpGained: xp,
    unlocked: [
      for (final a in HiLoAchievement.values)
        if (earned.contains(a)) a,
    ],
    newBest: newBest,
    ranked: ranked,
  );
}

/// Every achievement [game] and the updated [profile] now qualify for. An
/// unranked game still adds to the lifetime counts, but earns nothing for
/// itself.
Set<HiLoAchievement> _earned(
  HiLoProfile profile,
  HiLoGame game, {
  required bool ranked,
}) {
  final got = <HiLoAchievement>{};
  final spec = game.spec;
  if (profile.correct >= 1) got.add(HiLoAchievement.firstCount);
  if (profile.correct >= 100) got.add(HiLoAchievement.centurion);
  if (profile.holeCardReads >= 10) got.add(HiLoAchievement.pokerFace);
  if (profile.trueCountsRight >= 10) got.add(HiLoAchievement.trueBeliever);
  if (profile.dailyStreak >= 3) got.add(HiLoAchievement.regular);
  if (profile.dailyStreak >= 7) got.add(HiLoAchievement.everyDay);

  if (spec.isDuel) {
    if (game.completed) got.add(HiLoAchievement.duelist);
    return got;
  }
  if (!ranked) return got;
  final player = game.players.first;
  if (player.answers
      .any((a) => a.correct && a.took < HiLoScoring.fullSpeedWithin)) {
    got.add(HiLoAchievement.quickDraw);
  }
  if (player.answered >= 10 && player.perfect) {
    got.add(HiLoAchievement.perfectTen);
  }
  if (!spec.isSurvival &&
      game.completed &&
      spec.config.pace == HiLoPace.casino &&
      player.answered >= 5 &&
      player.perfect) {
    got.add(HiLoAchievement.casinoSpeed);
  }
  if (game.session.players >= 5 && player.bestStreak >= 10) {
    got.add(HiLoAchievement.fullHouse);
  }
  if (player.bestStreak >= 25) got.add(HiLoAchievement.unshakeable);
  if (spec.isSurvival && player.correct >= 20) {
    got.add(HiLoAchievement.survivor);
  }
  if (spec.isSurvival && game.level >= 7) got.add(HiLoAchievement.pitBoss);
  if (game.challengeWon) got.add(HiLoAchievement.challengeAccepted);
  return got;
}

/// Storage for the profile and the settings last played.
class HiLoTrainingProgress {
  const HiLoTrainingProgress._();

  static const _profileKey = 'hilo_training_profile';
  static const _duelNamesKey = 'hilo_training_duel_names';

  static const _decksKey = 'hilo_training_decks';
  static const _playersKey = 'hilo_training_players';
  static const _paceKey = 'hilo_training_pace';
  static const _frequencyKey = 'hilo_training_frequency';
  static const _lengthKey = 'hilo_training_length';
  static const _trueCountKey = 'hilo_training_true_count';

  static Future<HiLoProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null) return const HiLoProfile();
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) return HiLoProfile.fromJson(json);
    } on FormatException {
      // A corrupt save starts over rather than blocking the screen.
    }
    return const HiLoProfile();
  }

  static Future<void> saveProfile(HiLoProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }

  /// Mark the day's ranked Daily Challenge as begun.
  static Future<void> startDailyAttempt(int day) async {
    await saveProfile(startDaily(await loadProfile(), day));
  }

  /// Load, apply [game], save, and say what changed.
  static Future<HiLoGameReward> recordGame(HiLoGame game) async {
    final reward = applyGame(await loadProfile(), game);
    await saveProfile(reward.after);
    return reward;
  }

  static Future<List<String>> loadDuelNames() async {
    final prefs = await SharedPreferences.getInstance();
    final names = prefs.getStringList(_duelNamesKey);
    return names != null && names.length == 2 ? names : const ['', ''];
  }

  static Future<void> saveDuelNames(List<String> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_duelNamesKey, names);
  }

  /// The practice settings last played. Anything missing or no longer
  /// offered falls back to the default.
  static Future<HiLoTrainingConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    const fallback = HiLoTrainingConfig();

    int pick(String key, List<int> allowed, int otherwise) {
      final v = prefs.getInt(key);
      return v != null && allowed.contains(v) ? v : otherwise;
    }

    T byName<T extends Enum>(String key, List<T> values, T otherwise) {
      final name = prefs.getString(key);
      for (final v in values) {
        if (v.name == name) return v;
      }
      return otherwise;
    }

    return HiLoTrainingConfig(
      decks: pick(_decksKey, HiLoTrainingConfig.deckOptions, fallback.decks),
      players:
          pick(_playersKey, HiLoTrainingConfig.playerOptions, fallback.players),
      pace: byName(_paceKey, HiLoPace.values, fallback.pace),
      frequency:
          byName(_frequencyKey, HiLoQuizFrequency.values, fallback.frequency),
      questions: pick(
          _lengthKey, HiLoTrainingConfig.questionOptions, fallback.questions),
      trueCount: prefs.getBool(_trueCountKey) ?? fallback.trueCount,
    );
  }

  static Future<void> saveConfig(HiLoTrainingConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_decksKey, config.decks);
    await prefs.setInt(_playersKey, config.players);
    await prefs.setString(_paceKey, config.pace.name);
    await prefs.setString(_frequencyKey, config.frequency.name);
    await prefs.setInt(_lengthKey, config.questions);
    await prefs.setBool(_trueCountKey, config.trueCount);
  }
}

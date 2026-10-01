import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:blackjack_app/features/hilo_training/hilo_boards_service.dart';
import 'package:blackjack_app/features/hilo_training/hilo_game.dart';
import 'package:blackjack_app/features/hilo_training/hilo_training_session.dart';

class _FakeHiLoBackend implements HiLoBoardsBackend {
  String userId = 'me';
  Object? identifyError;
  Object? dailyError;
  Object? survivalError;
  Object? fetchError;
  Map<String, dynamic>? standing;
  final daily = <Map<String, dynamic>>[];
  final survival = <Map<String, dynamic>>[];
  final dailySubmissions = <Map<String, dynamic>>[];
  final survivalSubmissions = <Map<String, dynamic>>[];

  @override
  Future<String> identify() async {
    final error = identifyError;
    if (error != null) throw error;
    return userId;
  }

  @override
  Future<void> submitDaily(Map<String, dynamic> row) async {
    final error = dailyError;
    if (error != null) throw error;
    dailySubmissions.add(Map<String, dynamic>.from(row));
  }

  @override
  Future<void> submitSurvival(Map<String, dynamic> row) async {
    final error = survivalError;
    if (error != null) throw error;
    survivalSubmissions.add(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<Map<String, dynamic>>> dailyRows(int day, int limit) async {
    final error = fetchError;
    if (error != null) throw error;
    return daily.where((row) => row['day'] == day).take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> survivalRows(
      String weekKey, int limit) async {
    final error = fetchError;
    if (error != null) throw error;
    return survival
        .where((row) => row['week_key'] == weekKey)
        .take(limit)
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> dailyStanding(int day) async {
    final error = fetchError;
    if (error != null) throw error;
    return standing;
  }
}

HiLoAnswer _answer(bool correct) => HiLoAnswer(
      question: const HiLoQuestion(answer: 0, round: 1),
      given: correct ? 0 : 1,
    );

HiLoGame _dailyGame({bool ranked = true}) {
  final game = HiLoGame(HiLoGameSpec.daily(3, ranked: ranked));
  game.players.first
    ..score = 700
    ..bestStreak = 1
    ..answers.addAll([_answer(true), _answer(false)]);
  return game;
}

HiLoGame _survivalGame({int? targetScore}) {
  final game =
      HiLoGame(HiLoGameSpec.survival(seed: 9, targetScore: targetScore));
  game
    ..level = 1
    ..players.first.score = 200
    ..players.first.bestStreak = 2
    ..players.first.answers.addAll([_answer(true), _answer(true)]);
  return game;
}

void main() {
  late _FakeHiLoBackend backend;
  var clock = DateTime(2026, 10, 1, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({'online_player_name': 'Zed'});
    backend = _FakeHiLoBackend();
    clock = DateTime(2026, 10, 1, 12);
    HiLoBoardsService.resetForTest();
    HiLoBoardsService.backendOverride = backend;
    HiLoBoardsService.now = () => clock;
  });

  tearDown(HiLoBoardsService.resetForTest);

  test('submits the first ranked daily game with a valid player name',
      () async {
    SharedPreferences.setMockInitialValues(
        {'online_player_name': 'ThisNameIsFarTooLong'});

    expect(await HiLoBoardsService.submitGame(_dailyGame()), isTrue);

    final row = backend.dailySubmissions.single;
    expect(row['player_id'], 'me');
    expect(row['day'], 3);
    expect(row['display_name'], 'ThisNameIsFa');
    expect(row['score'], 700);
    expect(row['correct'], 1);
    expect(row['answered'], 2);
    expect(row['best_streak'], 1);
  });

  test('never submits a daily replay or a friend-picked Survival shoe',
      () async {
    expect(
        await HiLoBoardsService.submitGame(_dailyGame(ranked: false)), isFalse);
    expect(await HiLoBoardsService.submitGame(_survivalGame(targetScore: 100)),
        isFalse);
    expect(backend.dailySubmissions, isEmpty);
    expect(backend.survivalSubmissions, isEmpty);
  });

  test('submits an eligible Survival run to the current week', () async {
    expect(await HiLoBoardsService.submitGame(_survivalGame()), isTrue);

    final row = backend.survivalSubmissions.single;
    expect(row['player_id'], 'me');
    expect(row['week_key'], 'W143');
    expect(row['display_name'], 'Zed');
    expect(row['score'], 200);
    expect(row['correct'], 2);
    expect(row['answered'], 2);
    expect(row['level'], 1);
  });

  test('maps daily ranks and the player standing from the live board',
      () async {
    backend.daily.addAll([
      {
        'player_id': 'ann',
        'day': 3,
        'display_name': 'Ann',
        'score': 800,
        'correct': 1,
        'answered': 1,
        'best_streak': 1,
      },
      {
        'player_id': 'me',
        'day': 3,
        'display_name': 'Zed',
        'score': 700,
        'correct': 1,
        'answered': 2,
        'best_streak': 1,
      },
    ]);
    backend.standing = {'rank': 2, 'players': 2, 'score': 700};

    final board = await HiLoBoardsService.fetchDaily();

    expect(board.status, HiLoBoardStatus.live);
    expect(board.entries.map((entry) => entry.name), ['Ann', 'Zed']);
    expect(board.entries.map((entry) => entry.rank), [1, 2]);
    expect(board.entries.last.isCurrentUser, isTrue);
    expect(board.standing!.rank, 2);
    expect(board.standing!.players, 2);
  });

  test('uses the same week key as the weekly board for Survival', () async {
    backend.survival.add({
      'player_id': 'me',
      'week_key': 'W143',
      'display_name': 'Zed',
      'score': 200,
      'correct': 2,
      'answered': 2,
      'level': 1,
    });

    final board = await HiLoBoardsService.fetchSurvival();

    expect(board.status, HiLoBoardStatus.live);
    expect(board.entries.single.isCurrentUser, isTrue);
    expect(board.entries.single.level, 1);
  });

  test('reports a missing table as a setup state, not a network failure',
      () async {
    backend.fetchError =
        const PostgrestException(message: 'relation missing', code: 'PGRST205');

    final board = await HiLoBoardsService.fetchDaily();

    expect(board.status, HiLoBoardStatus.notConfigured);
    expect(board.entries, isEmpty);
  });

  test('a failed submit is harmless to the result screen', () async {
    backend.dailyError = const SocketException('offline');

    expect(await HiLoBoardsService.submitGame(_dailyGame()), isFalse);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:blackjack_app/features/leaderboard/leaderboard_service.dart';
import 'package:blackjack_app/features/leaderboard/weekly_board_service.dart';

/// A stand-in for the `weekly_rankings` table.
class _FakeBackend implements BoardBackend {
  final rows = <Map<String, dynamic>>[];
  String userId = 'me';
  Object? identifyError;
  Object? submitError;
  Object? fetchError;
  Object? accuracyError;
  int submits = 0;

  @override
  Future<String> identify() async {
    final error = identifyError;
    if (error != null) throw error;
    return userId;
  }

  @override
  Future<void> submit(Map<String, dynamic> row) async {
    final error = submitError;
    if (error != null) throw error;
    submits++;
    rows.removeWhere((r) =>
        r['player_id'] == row['player_id'] && r['week_key'] == row['week_key']);
    rows.add(Map<String, dynamic>.from(row));
  }

  @override
  Future<List<Map<String, dynamic>>> weekRows(String weekKey, int limit) async {
    final error = fetchError;
    if (error != null) throw error;
    final week = rows.where((r) => r['week_key'] == weekKey).toList()
      ..sort((a, b) => (b['profit'] as int).compareTo(a['profit'] as int));
    return week.take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> accuracyRows(
      String weekKey, int minDecisions, int limit) async {
    final error = accuracyError;
    if (error != null) throw error;
    int bp(Map<String, dynamic> r) {
      final d = (r['decisions'] as int?) ?? 0;
      return d == 0 ? 0 : ((r['correct_decisions'] as int) * 10000) ~/ d;
    }

    final week = rows
        .where((r) =>
            r['week_key'] == weekKey &&
            ((r['decisions'] as int?) ?? 0) >= minDecisions)
        .toList()
      ..sort((a, b) {
        final byAccuracy = bp(b).compareTo(bp(a));
        if (byAccuracy != 0) return byAccuracy;
        return (b['decisions'] as int).compareTo(a['decisions'] as int);
      });
    return week.take(limit).toList();
  }

  /// Seat a rival on the board.
  void addPlayer(String id, String name, int profit,
      {int hands = 50, int decisions = 0, int correct = 0}) {
    rows.add({
      'player_id': id,
      'week_key': LeaderboardService.weekKey(),
      'display_name': name,
      'profit': profit,
      'hands_played': hands,
      'decisions': decisions,
      'correct_decisions': correct,
    });
  }
}

void main() {
  late _FakeBackend backend;
  var clock = DateTime(2026, 9, 1, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({'online_player_name': 'Zed'});
    backend = _FakeBackend();
    clock = DateTime(2026, 9, 1, 12);
    WeeklyBoardService.resetForTest();
    WeeklyBoardService.backendOverride = backend;
    WeeklyBoardService.now = () => clock;
  });

  tearDown(WeeklyBoardService.resetForTest);

  /// Play [hands] hands winning [each] chips apiece.
  Future<void> play({required int hands, int each = 100}) async {
    for (var i = 0; i < hands; i++) {
      await LeaderboardService.recordHand(each);
    }
  }

  group('The board ranks real players', () {
    test('it sorts by profit and marks who you are', () async {
      backend.addPlayer('rival1', 'Ann', 900);
      backend.addPlayer('rival2', 'Bo', 300);
      await play(hands: 5, each: 100); // 500

      final board = await WeeklyBoardService.fetch();

      expect(board.status, BoardStatus.live);
      expect(board.entries.map((e) => e.name).toList(), ['Ann', 'Zed', 'Bo']);
      expect(board.entries.map((e) => e.rank).toList(), [1, 2, 3]);
      expect(board.playerCount, 3);

      final me = board.entries.firstWhere((e) => e.isCurrentUser);
      expect(me.name, 'Zed');
      expect(me.profit, 500);
      expect(me.rank, 2);
      expect(me.handsPlayed, 5);
    });

    test('it says exactly how far you are from the player above', () async {
      backend.addPlayer('rival1', 'Ann', 900);
      await play(hands: 5, each: 100); // 500

      final board = await WeeklyBoardService.fetch();
      expect(board.gapToNextRank, 400,
          reason: 'the number that makes someone play one more round');
    });

    test('the leader is chasing nobody', () async {
      backend.addPlayer('rival1', 'Ann', 100);
      await play(hands: 5, each: 100);

      final board = await WeeklyBoardService.fetch();
      expect(board.entries.first.isCurrentUser, isTrue);
      expect(board.gapToNextRank, isNull);
    });

    test('there are no invented competitors any more', () async {
      await play(hands: 3);
      final board = await WeeklyBoardService.fetch();

      expect(board.entries.length, 1,
          reason: 'the board used to pad itself with 25 fake names');
      expect(board.entries.single.isCurrentUser, isTrue);
      expect(board.playerCount, 1);
    });

    test('a player outside the fetched rows is still shown, unranked',
        () async {
      backend.addPlayer('rival1', 'Ann', 900);
      await play(hands: 4, each: 100);
      // Our push lands under a different id than the one we read back as.
      await WeeklyBoardService.push(force: true);
      backend.userId = 'someone-else';

      final board = await WeeklyBoardService.fetch();
      expect(board.entries.any((e) => e.isCurrentUser), isFalse);
      expect(board.me, isNotNull);
      expect(board.me!.profit, 400);
      expect(board.me!.rank, 0, reason: 'unranked renders as a dash, not #0');
    });

    test('nobody has played yet, so the board is genuinely empty', () async {
      final board = await WeeklyBoardService.fetch();
      expect(board.entries, isEmpty);
      expect(board.playerCount, 0);
      expect(board.isEmpty, isTrue);
    });
  });

  group('Submitting a score', () {
    test('it writes the week, the name, and the totals', () async {
      await play(hands: 4, each: 250);
      expect(await WeeklyBoardService.push(force: true), isTrue);

      final row = backend.rows.single;
      expect(row['player_id'], 'me');
      expect(row['week_key'], LeaderboardService.weekKey());
      expect(row['display_name'], 'Zed');
      expect(row['profit'], 1000);
      expect(row['hands_played'], 4);
    });

    test('a name too long for the column is trimmed', () async {
      SharedPreferences.setMockInitialValues(
          {'online_player_name': 'ThisNameIsFarTooLong'});
      await play(hands: 1);
      await WeeklyBoardService.push(force: true);
      expect((backend.rows.single['display_name'] as String).length, 12);
    });

    test('it says nothing before the player has played a hand', () async {
      expect(await WeeklyBoardService.push(force: true), isFalse);
      expect(backend.rows, isEmpty);
    });

    test('an unchanged score is not written again', () async {
      await play(hands: 3);
      expect(await WeeklyBoardService.push(force: true), isTrue);
      expect(backend.submits, 1);

      expect(await WeeklyBoardService.push(force: true), isFalse,
          reason: 'nothing has changed since the last write');
      expect(backend.submits, 1);
    });

    test('a changed score waits out the throttle', () async {
      await play(hands: 3);
      await WeeklyBoardService.push(force: true);
      expect(backend.submits, 1);

      await play(hands: 1);
      expect(await WeeklyBoardService.push(), isFalse, reason: 'too soon');
      expect(backend.submits, 1);

      clock = clock.add(WeeklyBoardService.pushInterval * 2);
      expect(await WeeklyBoardService.push(), isTrue);
      expect(backend.submits, 2);
      expect(backend.rows.single['hands_played'], 4);
    });

    test('a failed write never throws at the caller', () async {
      backend.submitError = const SocketException('down');
      await play(hands: 2);
      expect(await WeeklyBoardService.push(force: true), isFalse);
    });
  });

  group('When the board cannot be reached', () {
    test('a missing table falls back to your own week', () async {
      backend.fetchError =
          const PostgrestException(message: 'relation missing', code: '42P01');
      await play(hands: 3, each: 100);

      final board = await WeeklyBoardService.fetch();
      expect(board.status, BoardStatus.notConfigured);
      expect(board.entries.single.isCurrentUser, isTrue);
      expect(board.entries.single.profit, 300);
      expect(board.diagnostic, contains('weekly_rankings.sql'));
    });

    test('anonymous sign-ins being off is reported as a setup problem',
        () async {
      backend.identifyError = const AuthException('Anonymous sign-ins disabled');
      await play(hands: 2);

      final board = await WeeklyBoardService.fetch();
      expect(board.status, BoardStatus.notConfigured);
      expect(board.diagnostic, contains('Anonymous sign-ins'));
    });

    test('a network failure is reported as offline, not as bad setup',
        () async {
      backend.fetchError = const SocketException('no route');
      await play(hands: 2);

      final board = await WeeklyBoardService.fetch();
      expect(board.status, BoardStatus.offline);
      expect(board.isLive, isFalse);
    });

    test('with no backend at all you still see your own week', () async {
      WeeklyBoardService.backendOverride = null;
      await play(hands: 6, each: 50);

      final board = await WeeklyBoardService.fetch();
      expect(board.status, BoardStatus.offline);
      expect(board.me!.profit, 300);
      expect(board.me!.handsPlayed, 6);
    });

    test('setup problems and outages are told apart', () {
      expect(
        WeeklyBoardService.isSetupProblem(
            const PostgrestException(message: 'x', code: '42P01')),
        isTrue,
      );
      expect(
        WeeklyBoardService.isSetupProblem(
            const PostgrestException(message: 'x', code: '42501')),
        isTrue,
      );
      expect(WeeklyBoardService.isSetupProblem(const AuthException('x')), isTrue);
      expect(
        WeeklyBoardService.isSetupProblem(const SocketException('x')),
        isFalse,
      );
      expect(
        WeeklyBoardService.describeFailure(TimeoutException('x')),
        contains('Network'),
      );
    });
  });

  group('Weeks roll over', () {
    test('a new week starts everyone from zero', () async {
      await play(hands: 4, each: 100);
      expect(await LeaderboardService.readWeeklyProfit(), 400);

      // Simulate the stored week going stale.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lb_week_id', 'W1');

      expect(await LeaderboardService.readWeeklyProfit(), 0);
      expect(await LeaderboardService.readHandsPlayed(), 0);
    });

    test('scores are filed under the current week only', () async {
      backend.rows.add({
        'player_id': 'old',
        'week_key': 'W1',
        'display_name': 'LastWeek',
        'profit': 99999,
        'hands_played': 100,
      });
      await play(hands: 2, each: 100);

      final board = await WeeklyBoardService.fetch();
      expect(board.entries.map((e) => e.name), isNot(contains('LastWeek')));
      expect(board.entries.single.isCurrentUser, isTrue);
    });
  });

  group('The accuracy league', () {
    Future<void> decide(int total, int correct) async {
      for (var i = 0; i < total; i++) {
        await LeaderboardService.recordDecision(correct: i < correct);
      }
    }

    test('your decisions are sent with your score', () async {
      await play(hands: 3);
      await decide(10, 9);
      await WeeklyBoardService.push(force: true);
      final row = backend.rows.single;
      expect(row['decisions'], 10);
      expect(row['correct_decisions'], 9);
    });

    test('a new decision alone is worth a new push', () async {
      await play(hands: 3);
      await WeeklyBoardService.push(force: true);
      await decide(1, 1);
      expect(await WeeklyBoardService.push(force: true), isTrue);
    });

    test('it ranks by accuracy, needs 50 decisions, and breaks ties on volume',
        () async {
      backend.addPlayer('a', 'Ann', 900, decisions: 100, correct: 91);
      backend.addPlayer('b', 'Bo', 100, decisions: 60, correct: 60);
      backend.addPlayer('c', 'Cy', 50, decisions: 40, correct: 40);
      backend.addPlayer('d', 'Di', 10, decisions: 200, correct: 182);
      await play(hands: 30);
      await decide(80, 76); // 95%

      final board = await WeeklyBoardService.fetchAccuracy();
      expect(board.isLive, isTrue);
      expect([for (final e in board.entries) e.name],
          ['Bo', 'Zed', 'Di', 'Ann'],
          reason: 'Cy has too few decisions; Di beats Ann on volume at 91%');
      expect(board.me!.rank, 2);
      expect(board.me!.accuracyPercent, 95);
    });

    test('below the minimum you are shown but not ranked', () async {
      backend.addPlayer('a', 'Ann', 900, decisions: 100, correct: 91);
      await play(hands: 5);
      await decide(10, 10);
      final board = await WeeklyBoardService.fetchAccuracy();
      expect(board.entries.map((e) => e.name), ['Ann']);
      expect(board.me!.isCurrentUser, isTrue);
      expect(board.me!.rank, 0);
      expect(board.me!.decisions, 10);
    });

    test('a database without the accuracy migration reads as being set up',
        () async {
      backend.accuracyError = const PostgrestException(
          message: 'column weekly_rankings.accuracy_bp does not exist',
          code: '42703');
      await play(hands: 30);
      await decide(60, 57);
      final board = await WeeklyBoardService.fetchAccuracy();
      expect(board.status, BoardStatus.notConfigured);
      expect(board.me!.decisions, 60);
      expect(board.entries.single.isCurrentUser, isTrue);
    });

    test('accuracy is floored: 99.9% is not 100%', () {
      const e = LeaderboardEntry(
          name: 'x', profit: 0, decisions: 1000, correctDecisions: 999);
      expect(e.accuracyPercent, 99);
    });

    test('the missing-schema codes are recognised', () {
      for (final code in ['PGRST202', '42883', '42703', 'PGRST204']) {
        expect(
            SupabaseBoardBackend.isMissingSchema(
                PostgrestException(message: 'x', code: code)),
            isTrue,
            reason: code);
      }
      expect(
          SupabaseBoardBackend.isMissingSchema(
              const PostgrestException(message: 'x', code: '22023')),
          isFalse,
          reason: 'a rejected score is a real error, not a missing schema');
    });

    test('decisions reset with the week', () async {
      await decide(5, 5);
      expect((await LeaderboardService.readWeeklyDecisions()).decisions, 5);
      SharedPreferences.setMockInitialValues({
        'lb_week_id': 'W1',
        'lb_weekly_decisions': 99,
        'lb_weekly_correct': 90,
      });
      final fresh = await LeaderboardService.readWeeklyDecisions();
      expect(fresh.decisions, 0);
      expect(fresh.correct, 0);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blackjack_app/features/leaderboard/leaderboard_providers.dart';
import 'package:blackjack_app/features/leaderboard/leaderboard_screen.dart';
import 'package:blackjack_app/features/leaderboard/weekly_board_service.dart';

void main() {
  LeaderboardEntry entry(
    String name,
    int profit, {
    int rank = 0,
    bool me = false,
    int hands = 40,
  }) =>
      LeaderboardEntry(
        name: name,
        profit: profit,
        rank: rank,
        isCurrentUser: me,
        handsPlayed: hands,
      );

  Future<void> pumpBoard(WidgetTester tester, WeeklyBoard board) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weeklyBoardProvider.overrideWith((ref) async => board),
        ],
        child: const MaterialApp(home: LeaderboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a live board shows real players and where you stand',
      (tester) async {
    await pumpBoard(
      tester,
      WeeklyBoard(
        status: BoardStatus.live,
        playerCount: 4,
        entries: [
          entry('Ann', 900, rank: 1),
          entry('Zed', 500, rank: 2, me: true),
          entry('Bo', 300, rank: 3),
          entry('Cy', 100, rank: 4),
        ],
        me: entry('Zed', 500, rank: 2, me: true),
        gapToNextRank: 400,
      ),
    );

    expect(find.text('Ann'), findsWidgets);
    expect(find.text('Cy'), findsOneWidget);
    expect(find.text('4 PLAYERS THIS WEEK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it tells you exactly what it costs to move up', (tester) async {
    await pumpBoard(
      tester,
      WeeklyBoard(
        status: BoardStatus.live,
        playerCount: 2,
        entries: [
          entry('Ann', 900, rank: 1),
          entry('Zed', 500, rank: 2, me: true),
        ],
        me: entry('Zed', 500, rank: 2, me: true),
        gapToNextRank: 400,
      ),
    );

    // The banner emphasises the amount, so it is a RichText.
    expect(
      find.textContaining('to pass the player above you', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('\$400', findRichText: true),
      findsOneWidget,
      reason: 'the amount is a span inside the banner, not its whole text',
    );
  });

  testWidgets('the leader is not chasing anyone', (tester) async {
    await pumpBoard(
      tester,
      WeeklyBoard(
        status: BoardStatus.live,
        playerCount: 1,
        entries: [entry('Zed', 500, rank: 1, me: true)],
        me: entry('Zed', 500, rank: 1, me: true),
      ),
    );

    expect(
      find.textContaining('to pass the player above you', findRichText: true),
      findsNothing,
    );
    expect(find.text('THIS WEEK'), findsOneWidget);
  });

  testWidgets('an empty week invites you to take the top spot',
      (tester) async {
    await pumpBoard(
      tester,
      const WeeklyBoard(status: BoardStatus.live),
    );

    expect(find.text('The board is wide open'), findsOneWidget);
    expect(find.textContaining('the top spot is yours'), findsOneWidget);
  });

  testWidgets('a board that is not set up says so without losing your score',
      (tester) async {
    await pumpBoard(
      tester,
      WeeklyBoard(
        status: BoardStatus.notConfigured,
        playerCount: 1,
        entries: [entry('Zed', 250, rank: 1, me: true)],
        me: entry('Zed', 250, rank: 1, me: true),
        diagnostic: 'Postgrest 42P01',
      ),
    );

    expect(find.textContaining('Rankings are being set up'), findsOneWidget);
    expect(find.textContaining('Your score is saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('being offline is worded differently to being unconfigured',
      (tester) async {
    await pumpBoard(
      tester,
      WeeklyBoard(
        status: BoardStatus.offline,
        playerCount: 1,
        entries: [entry('Zed', 250, rank: 1, me: true)],
        me: entry('Zed', 250, rank: 1, me: true),
      ),
    );

    expect(find.textContaining("Can't reach the rankings"), findsOneWidget);
  });

  testWidgets('a player off the bottom of the board is still pinned',
      (tester) async {
    await pumpBoard(
      tester,
      WeeklyBoard(
        status: BoardStatus.live,
        playerCount: 3,
        entries: [
          entry('Ann', 900, rank: 1),
          entry('Bo', 800, rank: 2),
          entry('Cy', 700, rank: 3),
        ],
        // Outside the fetched rows: rank 0 renders as a dash, never "#0".
        me: entry('Zed', 10, rank: 0, me: true),
      ),
    );

    expect(find.text('Zed'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the accuracy league ranks by decisions, not chips',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    LeaderboardEntry acc(String name, int d, int c,
            {int rank = 0, bool me = false}) =>
        LeaderboardEntry(
          name: name,
          profit: -100,
          decisions: d,
          correctDecisions: c,
          rank: rank,
          isCurrentUser: me,
        );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        weeklyBoardProvider.overrideWith((ref) async => WeeklyBoard(
              status: BoardStatus.live,
              playerCount: 1,
              entries: [entry('Ann', 900, rank: 1)],
              me: entry('Ann', 900, rank: 1),
            )),
        weeklyAccuracyBoardProvider.overrideWith((ref) async => WeeklyBoard(
              status: BoardStatus.live,
              playerCount: 4,
              entries: [
                acc('Bo', 60, 60, rank: 1),
                acc('Zed', 80, 76, rank: 2, me: true),
                acc('Di', 200, 182, rank: 3),
                acc('Cy', 100, 80, rank: 4),
              ],
              me: acc('Zed', 80, 76, rank: 2, me: true),
            )),
      ],
      child: const MaterialApp(home: LeaderboardScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Top earners this week'), findsOneWidget);

    await tester.tap(find.text('ACCURACY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Best decisions this week'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('95%'), findsOneWidget);
    expect(find.text('4 PLAYERS · 50+ DECISIONS'), findsOneWidget);
    expect(find.textContaining('to pass the player above'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty accuracy league explains how to qualify',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        weeklyBoardProvider.overrideWith(
            (ref) async => const WeeklyBoard(status: BoardStatus.live)),
        weeklyAccuracyBoardProvider.overrideWith((ref) async =>
            const WeeklyBoard(
              status: BoardStatus.live,
              me: LeaderboardEntry(
                  name: 'Zed',
                  profit: 0,
                  decisions: 12,
                  correctDecisions: 11,
                  isCurrentUser: true),
            )),
      ],
      child: const MaterialApp(home: LeaderboardScreen()),
    ));
    await tester.pump();
    await tester.tap(find.text('ACCURACY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Nobody has qualified yet'), findsOneWidget);
    expect(find.textContaining('Make 50 decisions'), findsOneWidget);
    expect(find.text('YOUR RANK'), findsOneWidget,
        reason: 'your own progress is still shown');
    expect(tester.takeException(), isNull);
  });
}

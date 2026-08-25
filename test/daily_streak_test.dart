import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/progress/daily_streak.dart';

void main() {
  var clock = DateTime(2026, 9, 1, 10);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 9, 1, 10);
    DailyStreak.now = () => clock;
  });

  tearDown(DailyStreak.resetForTest);

  void advanceDays(int days, {int atHour = 10}) {
    final next = clock.add(Duration(days: days));
    clock = DateTime(next.year, next.month, next.day, atHour);
  }

  test('a new player has day one waiting for them', () async {
    final state = await DailyStreak.read();
    expect(state.streak, 0);
    expect(state.claimedToday, isFalse);
    expect(state.todayReward, DailyStreak.rewards.first);
    expect(state.dayInCycle, 1);
  });

  test('claiming grants the day-one reward and starts the run', () async {
    expect(await DailyStreak.claim(), DailyStreak.rewards[0]);

    final state = await DailyStreak.read();
    expect(state.streak, 1);
    expect(state.best, 1);
    expect(state.claimedToday, isTrue);
    expect(state.tomorrowReward, DailyStreak.rewards[1]);
  });

  test('the same day cannot be claimed twice', () async {
    await DailyStreak.claim();
    expect(await DailyStreak.claim(), 0);

    // Not even later the same day.
    clock = DateTime(clock.year, clock.month, clock.day, 23, 59);
    expect(await DailyStreak.claim(), 0);
    expect((await DailyStreak.read()).streak, 1);
  });

  test('coming back the next day climbs the ladder', () async {
    for (var day = 0; day < DailyStreak.rewards.length; day++) {
      expect(await DailyStreak.claim(), DailyStreak.rewards[day],
          reason: 'day ${day + 1}');
      advanceDays(1);
    }
    final state = await DailyStreak.read();
    expect(state.streak, DailyStreak.rewards.length);
    expect(state.best, DailyStreak.rewards.length);
  });

  test('the ladder repeats its top rung rather than growing forever',
      () async {
    for (var i = 0; i < DailyStreak.rewards.length; i++) {
      await DailyStreak.claim();
      advanceDays(1);
    }
    // Day 8 comes back around to the start of the cycle.
    expect(await DailyStreak.claim(), DailyStreak.rewards.first);
    expect((await DailyStreak.read()).dayInCycle, 1);
    expect((await DailyStreak.read()).streak, DailyStreak.rewards.length + 1);
  });

  test('missing a day starts the ladder again, but keeps your best', () async {
    await DailyStreak.claim();
    advanceDays(1);
    await DailyStreak.claim();
    advanceDays(1);
    await DailyStreak.claim(); // three-day run
    expect((await DailyStreak.read()).streak, 3);

    advanceDays(3); // life happened
    final before = await DailyStreak.read();
    expect(before.claimedToday, isFalse);
    expect(before.streakBroken, isTrue);
    expect(before.todayReward, DailyStreak.rewards.first,
        reason: 'back to day one');

    expect(await DailyStreak.claim(), DailyStreak.rewards.first);
    final after = await DailyStreak.read();
    expect(after.streak, 1);
    expect(after.best, 3, reason: 'your best run is never taken away');
  });

  test('crossing midnight counts as a new day, not 24 hours later', () async {
    clock = DateTime(2026, 9, 1, 23, 30);
    await DailyStreak.claim();

    // Half an hour later, but a different date.
    clock = DateTime(2026, 9, 2, 0, 5);
    final state = await DailyStreak.read();
    expect(state.claimedToday, isFalse);
    expect(await DailyStreak.claim(), DailyStreak.rewards[1],
        reason: 'the run continued into day two');
  });

  test('the pips cycle 1..7 as the streak climbs', () async {
    final seen = <int>[];
    for (var i = 0; i < 9; i++) {
      await DailyStreak.claim();
      seen.add((await DailyStreak.read()).dayInCycle);
      advanceDays(1);
    }
    expect(seen, [1, 2, 3, 4, 5, 6, 7, 1, 2]);
  });

  test('rewards never decrease within a cycle', () {
    for (var i = 1; i < DailyStreak.rewards.length; i++) {
      expect(DailyStreak.rewards[i], greaterThan(DailyStreak.rewards[i - 1]));
    }
  });

  group('The seven pips read correctly', () {
    test('a brand-new player sees day one on offer and nothing earned',
        () async {
      final state = await DailyStreak.read();
      expect(state.pipIsToday(1), isTrue);
      expect(
        [for (var d = 1; d <= DailyStreak.cycleLength; d++) state.pipFilled(d)],
        everyElement(isFalse),
      );
    });

    test('after claiming, today is filled and nothing is on offer', () async {
      await DailyStreak.claim();
      final state = await DailyStreak.read();
      expect(state.pipFilled(1), isTrue);
      expect(state.pipFilled(2), isFalse);
      expect(
        [for (var d = 1; d <= DailyStreak.cycleLength; d++) state.pipIsToday(d)],
        everyElement(isFalse),
      );
    });

    test('mid-run, the earned days are filled and the next is highlighted',
        () async {
      await DailyStreak.claim();
      advanceDays(1);
      await DailyStreak.claim();
      advanceDays(1);

      final state = await DailyStreak.read();
      expect(state.pipFilled(1), isTrue);
      expect(state.pipFilled(2), isTrue);
      expect(state.pipFilled(3), isFalse);
      expect(state.pipIsToday(3), isTrue);
    });

    test('a broken streak puts day one back on offer', () async {
      await DailyStreak.claim();
      advanceDays(1);
      await DailyStreak.claim();
      advanceDays(5);

      final state = await DailyStreak.read();
      expect(state.streakBroken, isTrue);
      expect(state.pipIsToday(1), isTrue);
      expect(state.pipFilled(1), isFalse);
    });

    test('completing a cycle rolls the pips back to a fresh week', () async {
      for (var i = 0; i < DailyStreak.cycleLength; i++) {
        await DailyStreak.claim();
        advanceDays(1);
      }
      final state = await DailyStreak.read();
      expect(state.streak, DailyStreak.cycleLength);
      expect(state.pendingDayInCycle, 1, reason: 'a new week begins');
      expect(state.pipIsToday(1), isTrue);
      expect(state.pipFilled(1), isFalse);
    });
  });
}

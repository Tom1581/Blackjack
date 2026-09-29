// Regression tests for the 2026-09 table audit. Each group names the defect
// it guards: most were reproduced against the old code before being fixed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:blackjack_app/core/engine/deck_manager.dart';
import 'package:blackjack_app/core/engine/game_engine.dart';
import 'package:blackjack_app/core/engine/hi_lo_counter.dart';
import 'package:blackjack_app/core/models/card_model.dart';
import 'package:blackjack_app/core/models/game_state.dart';
import 'package:blackjack_app/core/models/hand_model.dart';
import 'package:blackjack_app/core/progress/player_stats.dart';
import 'package:blackjack_app/core/rules/rule_set.dart';
import 'package:blackjack_app/core/settings/table_prefs.dart';
import 'package:blackjack_app/core/strategy/strategy_coach.dart';
import 'package:blackjack_app/features/table/table_provider.dart';
import 'package:blackjack_app/features/table/table_screen.dart';

const _k = CardModel(suit: Suit.spades, rank: Rank.king);
const _ace = CardModel(suit: Suit.spades, rank: Rank.ace);
const _six = CardModel(suit: Suit.hearts, rank: Rank.six);
const _nine = CardModel(suit: Suit.clubs, rank: Rank.nine);
const _four = CardModel(suit: Suit.clubs, rank: Rank.four);
const _holeSeven =
    CardModel(suit: Suit.hearts, rank: Rank.seven, faceUp: false);
const _holeFour = CardModel(suit: Suit.hearts, rank: Rank.four, faceUp: false);

/// A table notifier that starts from a given state instead of a fresh shoe.
class _Seeded extends TableNotifier {
  _Seeded(this.seed);
  final GameState seed;

  @override
  GameState build() {
    super.build();
    return seed;
  }
}

GameState _midHand({
  required List<HandModel> hands,
  required HandModel dealer,
  int bankroll = 900,
  int sideBet = 0,
  int activeHandIndex = 0,
  InsuranceState insurance = InsuranceState.notOffered,
}) {
  final staked = hands.fold<int>(0, (a, h) => a + h.bet);
  return GameState(
    phase: GamePhase.playerTurn,
    playerHands: hands,
    activeHandIndex: activeHandIndex,
    dealerHand: dealer,
    bankroll: bankroll,
    currentBet: staked,
    spotBets: [for (final h in hands) h.bet],
    sideBet: sideBet,
    handResults: List<GameResult?>.filled(hands.length, null),
    insuranceState: insurance,
  );
}

Future<void> _pumpTable(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size size = const Size(420, 920),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: TableScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablePrefs.resetForTest();
    StrategyCoach.resetForTest();
  });

  group('The dealer badge never gives the hole card away', () {
    test('visibleValue leaves out a locally dealt face-down card', () {
      const dealer = HandModel(cards: [_k, _holeSeven]);
      expect(dealer.value, 17, reason: 'the engine still sees it, to peek');
      expect(dealer.visibleValue, 10);
      expect(dealer.hasFaceDown, isTrue);
      expect(dealer.revealAll().hasFaceDown, isFalse);
    });

    testWidgets('mid-hand the badge reads "10 + ?", not the full 17',
        (tester) async {
      final seed = _midHand(
        hands: const [HandModel(cards: [_nine, _six], bet: 100)],
        dealer: const HandModel(cards: [_k, _holeSeven]),
      );
      await _pumpTable(tester, overrides: [
        tableProvider.overrideWith(() => _Seeded(seed)),
      ]);
      expect(find.text('10 + ?'), findsOneWidget);
      expect(find.text('17'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('A dealer ace against a natural', () {
    testWidgets('does not throw building the action bar', (tester) async {
      // Every hand is a natural, so there is no active hand — and the
      // insurance question is still open.
      final seed = _midHand(
        hands: const [HandModel(cards: [_ace, _k], bet: 100)],
        dealer: const HandModel(cards: [_ace, _holeSeven]),
        activeHandIndex: 1,
        insurance: InsuranceState.offered,
      );
      await _pumpTable(tester, overrides: [
        tableProvider.overrideWith(() => _Seeded(seed)),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.text('INSURANCE?'), findsOneWidget);
      expect(find.text('Hit'), findsNothing, reason: 'nothing to act on');
    });

    test('actions are refused while insurance is open', () {
      final seed = _midHand(
        hands: const [HandModel(cards: [_nine, _six], bet: 100)],
        dealer: const HandModel(cards: [_ace, _holeSeven]),
        insurance: InsuranceState.offered,
      );
      final c = ProviderContainer(overrides: [
        tableProvider.overrideWith(() => _Seeded(seed)),
      ]);
      addTearDown(c.dispose);
      c.read(tableProvider.notifier).hit();
      expect(c.read(tableProvider).activeHand.cards, hasLength(2));
      expect(c.read(strategyHintProvider), isNull);
      expect(c.read(canDoubleProvider), isFalse);
    });
  });

  group('Changing the table mid-round', () {
    testWidgets('keeps the live round and its stake, then applies next hand',
        (tester) async {
      final seed = _midHand(
        hands: const [HandModel(cards: [_nine, _six], bet: 100)],
        dealer: const HandModel(cards: [_k, _holeSeven]),
      );
      final c = ProviderContainer(overrides: [
        tableProvider.overrideWith(() => _Seeded(seed)),
      ]);
      addTearDown(c.dispose);
      c.read(tableProvider);

      c.read(rulesProvider.notifier).state = RuleSet.sixFive;
      c.read(shoeModeProvider.notifier).state = ShoeMode.twoDeck;

      final during = c.read(tableProvider);
      expect(during.phase, GamePhase.playerTurn,
          reason: 'the round used to be wiped here, stake and all');
      expect(during.bankroll, 900);
      expect(during.activeHand.cards, hasLength(2));
      expect(c.read(tableRulesProvider), RuleSet.sixDeckH17,
          reason: 'the felt and coach describe the round being played');

      c.read(tableProvider.notifier).stand();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final settled = c.read(tableProvider);
      expect(settled.phase, GamePhase.result);
      expect(settled.bankroll, greaterThanOrEqualTo(900));

      c.read(tableProvider.notifier).nextHand();
      final next = c.read(tableProvider);
      expect(next.phase, GamePhase.betting);
      expect(next.freshShoe, isTrue, reason: 'the count restarts — say so');
      expect(c.read(tableRulesProvider), RuleSet.sixFive);
      expect(c.read(tableEngineProvider).numDecks, 2);
      expect(next.bankroll, settled.bankroll);
      await tester.pump(const Duration(milliseconds: 1)); // flush Riverpod
    });

    test('while betting it applies at once — including the first change',
        () {
      // The first rules change after launch used to leave the dealer on the
      // old rules while the coach graded against the new ones.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(tableProvider);
      c.read(rulesProvider.notifier).state = RuleSet.sixDeckS17;
      final engine = c.read(tableEngineProvider);
      expect(engine.rules, RuleSet.sixDeckS17);
      const soft17 = GameState(
        dealerHand: HandModel(cards: [_ace, _six]),
      );
      expect(engine.dealerShouldHit(soft17), isFalse,
          reason: 'an S17 dealer stands on soft 17');
    });
  });

  group('The felt prints the rules actually in play', () {
    test('payout line', () {
      expect(feltPayoutLine(RuleSet.sixDeckH17), 'BLACKJACK PAYS 3 TO 2');
      expect(feltPayoutLine(RuleSet.sixFive), 'BLACKJACK PAYS 6 TO 5');
    });

    test('soft 17 line', () {
      expect(feltRulesLine(RuleSet.sixDeckH17), contains('Hit on Soft 17'));
      expect(feltRulesLine(RuleSet.sixDeckS17), contains('Stand on All 17s'));
    });
  });

  group('A decided round is not played out by the dealer', () {
    final engine = GameEngine();

    test('every hand bust and no side bet: the dealer stops', () {
      final s = _midHand(
        hands: const [
          HandModel(cards: [_k, _six, _nine], bet: 10),
        ],
        dealer: const HandModel(cards: [_k, _four]),
      );
      expect(engine.dealerMustPlay(s), isFalse);
    });

    test('a live hand, a side bet, or a split 21 keeps the dealer drawing',
        () {
      final live = _midHand(
        hands: const [HandModel(cards: [_k, _six], bet: 10)],
        dealer: const HandModel(cards: [_k, _four]),
      );
      expect(engine.dealerMustPlay(live), isTrue);

      final bustWithSide = _midHand(
        hands: const [HandModel(cards: [_k, _six, _nine], bet: 10)],
        dealer: const HandModel(cards: [_k, _four]),
        sideBet: 10,
      );
      expect(engine.dealerMustPlay(bustWithSide), isTrue,
          reason: 'the bust side bet is decided by the draw');

      final split21 = _midHand(
        hands: const [
          HandModel(cards: [_ace, _k], bet: 10, fromSplit: true),
        ],
        dealer: const HandModel(cards: [_k, _four]),
      );
      expect(engine.dealerMustPlay(split21), isTrue,
          reason: 'a split 21 is an ordinary 21 and can be pushed');
    });

    test('naturals only: nothing to draw for', () {
      final s = _midHand(
        hands: const [HandModel(cards: [_ace, _k], bet: 10)],
        dealer: const HandModel(cards: [_k, _four]),
      );
      expect(engine.dealerMustPlay(s), isFalse);
    });

    testWidgets('at the table the dealer turns the hole card and stops',
        (tester) async {
      final seed = _midHand(
        hands: const [HandModel(cards: [_k, _six, _nine], bet: 100)],
        dealer: const HandModel(cards: [_k, _holeFour]),
      );
      final c = ProviderContainer(overrides: [
        tableProvider.overrideWith(() => _Seeded(seed)),
      ]);
      addTearDown(c.dispose);
      c.read(tableProvider.notifier).stand();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      final s = c.read(tableProvider);
      expect(s.phase, GamePhase.result);
      expect(s.dealerHand.cards, hasLength(2),
          reason: 'a dealer on 14 used to draw against a busted hand');
      expect(s.dealerHand.hasFaceDown, isFalse, reason: 'hole still shown');
    });
  });

  group('REBET', () {
    final engine = GameEngine();

    test('puts last round\'s bets back, side bet included', () {
      const s = GameState(
        spotBets: [0, 0],
        lastSpotBets: [25, 50],
        lastSideBet: 10,
        bankroll: 1000,
      );
      final next = engine.rebet(s);
      expect(next.spotBets, [25, 50]);
      expect(next.currentBet, 75);
      expect(next.sideBet, 10);
    });

    test('drops the side bet first when chips are short', () {
      const s = GameState(
        spotBets: [0],
        lastSpotBets: [100],
        lastSideBet: 25,
        bankroll: 110,
      );
      final next = engine.rebet(s);
      expect(next.currentBet, 100);
      expect(next.sideBet, 0);
    });

    test('is unavailable when the main bet cannot be covered', () {
      const s = GameState(
        spotBets: [0],
        lastSpotBets: [500],
        bankroll: 300,
      );
      expect(engine.rebetFor(s), isNull);
    });

    test('follows the number of spots open today', () {
      const s = GameState(
        spotBets: [0],
        lastSpotBets: [25, 50, 75],
        bankroll: 1000,
      );
      expect(engine.rebet(s).spotBets, [25]);
    });

    test('the deal records what to repeat', () {
      final dealt = engine.dealInitial(const GameState(
        spotBets: [40],
        currentBet: 40,
        sideBet: 5,
        bankroll: 1000,
      ));
      expect(dealt.lastSpotBets, [40]);
      expect(dealt.lastSideBet, 5);
    });
  });

  group('The reshuffle is announced', () {
    test('a reshuffle flags the next betting phase, and only that one', () {
      final engine = GameEngine(numDecks: 2);
      var s = const GameState(spotBets: [10], currentBet: 10);
      var flagged = 0;
      for (var i = 0; i < 40; i++) {
        s = engine.dealInitial(s.copyWith(
          phase: GamePhase.betting,
          spotBets: [10],
          currentBet: 10,
          bankroll: 1000,
        ));
        s = engine.newHand(s);
        if (s.freshShoe) {
          flagged++;
          expect(s.runningCount, 0, reason: 'fresh shoe, fresh count');
          expect(s.cardsRemaining, 104);
        }
      }
      expect(flagged, greaterThan(0));
    });

    test('a continuous shuffler does not announce every hand', () {
      final engine = GameEngine(continuous: true);
      final s = engine.newHand(const GameState());
      expect(s.freshShoe, isFalse);
    });
  });

  group('True count', () {
    test('divides by decks left to the nearest half deck', () {
      expect(HiLoCounter.estimateDecks(75, maxDecks: 6), 1.5);
      expect(HiLoCounter.estimateDecks(312, maxDecks: 6), 6);
      expect(HiLoCounter.estimateDecks(10, maxDecks: 6), 0.5,
          reason: 'never divides by less than half a deck');
    });

    test('late in the shoe the true count is no longer understated', () {
      final counter = HiLoCounter(totalDecks: 6);
      for (var i = 0; i < 6; i++) {
        counter.update(_six);
      }
      counter.updateDecksRemaining(75);
      expect(counter.trueCount, 4.0,
          reason: 'rounding decks up used to report +3 here');
    });
  });

  test('an empty shoe is rebuilt instead of throwing', () {
    final deck = DeckManager(numDecks: 1);
    for (var i = 0; i < 52; i++) {
      deck.draw();
    }
    expect(deck.isEmpty, isTrue);
    expect(() => deck.draw(), returnsNormally);
    expect(deck.remaining, 51);
  });

  group('Stats are actually recorded', () {
    test('a settled round is written where the stats screen reads it',
        () async {
      await PlayerStatsStore.recordRound(
        results: const [GameResult.blackjack, GameResult.bust],
        roundNet: 50,
        trueCountAtDeal: 2.5,
      );
      await PlayerStatsStore.recordRound(
        results: const [GameResult.push],
        roundNet: 0,
        trueCountAtDeal: -1,
      );
      final s = await PlayerStatsStore.read();
      expect(s.hands, 3);
      expect(s.wins, 1);
      expect(s.blackjacks, 1);
      expect(s.losses, 1);
      expect(s.pushes, 1);
      expect(s.tableNet, 50);
      expect(s.biggestWin, 50);
      expect(s.winRate, 0.5, reason: 'pushes are neither');
      expect(s.trueCountHistory, [2.5, -1.0]);
    });

    test('the true-count history keeps only the latest rounds', () async {
      for (var i = 0; i < PlayerStatsStore.historyLength + 5; i++) {
        await PlayerStatsStore.recordRound(
          results: const [GameResult.win],
          roundNet: 10,
          trueCountAtDeal: i.toDouble(),
        );
      }
      final s = await PlayerStatsStore.read();
      expect(s.trueCountHistory, hasLength(PlayerStatsStore.historyLength));
      expect(s.trueCountHistory.last,
          (PlayerStatsStore.historyLength + 4).toDouble());
    });
  });

  group('Strategy mastery', () {
    setUp(() => StrategyCoach.reset());

    test('decisions are split by category and misses are ranked', () async {
      await StrategyCoach.record(
          correct: false,
          category: StrategyCategory.soft,
          spot: 'Soft 18 vs 9');
      await StrategyCoach.record(
          correct: false,
          category: StrategyCategory.soft,
          spot: 'Soft 18 vs 9');
      await StrategyCoach.record(
          correct: false, category: StrategyCategory.pair, spot: '9,9 vs 7');
      await StrategyCoach.record(
          correct: true, category: StrategyCategory.hard);

      final m = await StrategyCoach.readMastery();
      expect(m.of(StrategyCategory.soft).total, 2);
      expect(m.of(StrategyCategory.soft).correct, 0);
      expect(m.of(StrategyCategory.hard).accuracyPercent, 100);
      expect(m.topMisses.first.spot, 'Soft 18 vs 9');
      expect(m.topMisses.first.count, 2);
      expect((await StrategyCoach.read()).total, 4,
          reason: 'the overall record still counts everything');
    });

    test('chart labels treat faces as tens and name pairs by rank', () {
      expect(
        chartSpotLabel(
          const HandModel(cards: [_k, _six]),
          const CardModel(suit: Suit.clubs, rank: Rank.queen),
          StrategyCategory.hard,
        ),
        'Hard 16 vs 10',
      );
      expect(
        chartSpotLabel(
          const HandModel(cards: [_ace, _six]),
          _ace,
          StrategyCategory.soft,
        ),
        'Soft 17 vs A',
      );
      expect(
        chartSpotLabel(
          const HandModel(cards: [_k, CardModel(suit: Suit.hearts, rank: Rank.jack)]),
          _six,
          StrategyCategory.pair,
        ),
        '10,10 vs 6',
      );
    });
  });

  group('Count check quiz', () {
    test('asks every few rounds while the HUD is hidden', () async {
      final c = ProviderContainer(overrides: [
        showCountProvider.overrideWith((ref) => false),
      ]);
      addTearDown(c.dispose);
      final n = c.read(tableProvider.notifier);
      for (var i = 0; i < countCheckEvery - 1; i++) {
        n.nextHand();
        expect(c.read(countCheckProvider), isNull);
      }
      n.nextHand();
      final check = c.read(countCheckProvider);
      expect(check, isNotNull);
      expect(check!.answer, c.read(tableProvider).runningCount);

      expect(n.answerCountCheck(check.answer + 1), isFalse);
      n.dismissCountCheck();
      expect(c.read(countCheckProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      final stats = await PlayerStatsStore.read();
      expect(stats.countChecks, 1);
      expect(stats.countChecksCorrect, 0);
    });

    test('never asks while the HUD is showing the answer', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(tableProvider.notifier);
      for (var i = 0; i < countCheckEvery * 3; i++) {
        n.nextHand();
      }
      expect(c.read(countCheckProvider), isNull);
    });

    testWidgets('the quiz takes an answer and reveals the count',
        (tester) async {
      await _pumpTable(tester, overrides: [
        countCheckProvider.overrideWith((ref) => const CountCheck(2)),
      ]);
      expect(find.text('COUNT CHECK'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(find.text('+1'), findsOneWidget);
      await tester.tap(find.text('CHECK'));
      await tester.pump();
      expect(find.textContaining('The running count is +2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Insurance coaching', () {
    GameState insuranceSeed() => _midHand(
          hands: const [HandModel(cards: [_nine, _six], bet: 100)],
          dealer: const HandModel(cards: [_ace, _holeSeven]),
          insurance: InsuranceState.offered,
        );

    testWidgets('names the counter\'s index with the HUD on', (tester) async {
      await _pumpTable(tester, overrides: [
        tableProvider.overrideWith(() => _Seeded(insuranceSeed())),
      ]);
      expect(find.textContaining('+3 or higher'), findsOneWidget);
      expect(find.textContaining('True count now'), findsOneWidget);
    });

    testWidgets('does not leak the count with the HUD hidden',
        (tester) async {
      await _pumpTable(tester, overrides: [
        tableProvider.overrideWith(() => _Seeded(insuranceSeed())),
        showCountProvider.overrideWith((ref) => false),
      ]);
      expect(find.textContaining('+3 or higher'), findsOneWidget);
      expect(find.textContaining('True count now'), findsNothing);
    });
  });

  group('Settings survive a restart', () {
    test('HUD, shoe, hands and count check are remembered', () async {
      await TablePrefs.setShowCount(false);
      await TablePrefs.setShoe(ShoeMode.eightDeck.name);
      await TablePrefs.setSpots(3);
      await TablePrefs.setCountCheck(false);
      TablePrefs.resetForTest();
      await TablePrefs.load();

      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(showCountProvider), isFalse);
      expect(c.read(shoeModeProvider), ShoeMode.eightDeck);
      expect(c.read(spotCountProvider), 3);
      expect(c.read(countCheckEnabledProvider), isFalse);
      expect(c.read(tableEngineProvider).numDecks, 8);
    });
  });

  test('bankroll is shown exactly, not rounded to "1.0k"', () {
    expect(formatChips(1049), '1,049');
    expect(formatChips(999), '999');
    expect(formatChips(123456), '123,456');
    expect(formatChips(-2500), '-2,500');
    expect(formatChips(2500000), '2.50M');
  });

  group('The table fits a small phone', () {
    for (final spots in [1, 3]) {
      testWidgets('360 wide, $spots spot(s), big bankroll', (tester) async {
        final seed = _midHand(
          hands: [
            for (var i = 0; i < spots; i++)
              const HandModel(cards: [_nine, _six], bet: 100),
          ],
          dealer: const HandModel(cards: [_k, _holeSeven]),
          bankroll: 1234567,
        );
        await _pumpTable(
          tester,
          size: const Size(360, 740),
          overrides: [tableProvider.overrideWith(() => _Seeded(seed))],
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('360 wide while betting', (tester) async {
      await _pumpTable(tester, size: const Size(360, 740));
      expect(find.text('REBET'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

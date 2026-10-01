import 'dart:math';

import '../../core/engine/hi_lo_counter.dart';
import '../../core/models/card_model.dart';
import '../../core/models/hand_model.dart';
import '../../core/rules/rule_set.dart';
import '../../core/strategy/basic_strategy.dart';
import '../training/drills.dart' show hiLoTag;
import 'hilo_scoring.dart';

// Hi-Lo Training: a dealer runs real rounds at a full table and, at a card the
// player cannot predict, stops to ask for the running count.
//
// Everything here is pure Dart, so the deal, the count and the quiz schedule
// are tested without a widget tree.

enum HiLoPace {
  relaxed('Relaxed', Duration(milliseconds: 1500)),
  steady('Steady', Duration(milliseconds: 1100)),
  brisk('Brisk', Duration(milliseconds: 800)),
  casino('Casino', Duration(milliseconds: 550));

  const HiLoPace(this.label, this.perCard);
  final String label;

  /// How long each card stays the newest thing on the felt.
  final Duration perCard;

  /// The next pace up, or null at the fastest.
  HiLoPace? get faster =>
      index + 1 < HiLoPace.values.length ? HiLoPace.values[index + 1] : null;
}

/// How often the dealer stops to ask. The exact card is drawn at random from
/// the range, so the player can never tell a question is coming.
enum HiLoQuizFrequency {
  often('Often', 5, 12),
  sometimes('Sometimes', 10, 22),
  rarely('Rarely', 20, 40);

  const HiLoQuizFrequency(this.label, this.minCards, this.maxCards);
  final String label;
  final int minCards;
  final int maxCards;

  String get blurb => 'After $minCards–$maxCards cards, at random';
}

class HiLoTrainingConfig {
  static const deckOptions = [2, 6, 8];
  static const playerOptions = [1, 2, 3, 4, 5];
  static const questionOptions = [5, 10, 20];

  final int decks;

  /// Seats in play, not counting the dealer.
  final int players;
  final HiLoPace pace;
  final HiLoQuizFrequency frequency;

  /// Questions in one session.
  final int questions;

  /// After the running count, also ask for the true count — the running
  /// count divided by the decks left, the number a counter's bet is sized
  /// on.
  final bool trueCount;

  const HiLoTrainingConfig({
    this.decks = 6,
    this.players = 3,
    this.pace = HiLoPace.steady,
    this.frequency = HiLoQuizFrequency.sometimes,
    this.questions = 10,
    this.trueCount = false,
  });

  HiLoTrainingConfig copyWith({
    int? decks,
    int? players,
    HiLoPace? pace,
    HiLoQuizFrequency? frequency,
    int? questions,
    bool? trueCount,
  }) =>
      HiLoTrainingConfig(
        decks: decks ?? this.decks,
        players: players ?? this.players,
        pace: pace ?? this.pace,
        frequency: frequency ?? this.frequency,
        questions: questions ?? this.questions,
        trueCount: trueCount ?? this.trueCount,
      );
}

enum HiLoEventKind {
  /// A card dealt face up, to a seat or the dealer.
  card,

  /// The dealer's hole card, dealt face down. It does not count yet.
  holeCard,

  /// The hole card turned over. It counts from now on.
  reveal,

  /// Every hand is finished and the totals are on the felt.
  roundOver,

  /// The round's cards went into the discard tray.
  sweep,

  /// The cut card came out: a fresh shoe, and the count starts again at 0.
  shuffle,
}

class HiLoEvent {
  final HiLoEventKind kind;
  final CardModel? card;

  /// The seat the card went to (0 is first base), or null for the dealer.
  final int? seat;

  const HiLoEvent(this.kind, {this.card, this.seat});
}

/// What most likely went wrong with a wrong answer, so the feedback can name
/// the habit rather than just the number.
enum HiLoSlip {
  none,

  /// Counted the dealer's face-down card.
  countedHoleCard,

  /// Right up to the card that had just landed.
  missedLastCard,

  /// The right size with the wrong sign.
  flippedSign,

  /// Off by some other amount.
  drift,

  /// The answer clock ran out first.
  timeUp,
}

class HiLoQuestion {
  /// The running count of every card seen since the shuffle.
  final int answer;

  /// The dealer's hole card, while it is still face down.
  final CardModel? holeCardDown;

  /// The card that landed just before the question.
  final CardModel? lastCard;
  final int round;

  /// Decks still in the shoe, to the nearest half deck — what a counter
  /// reads off the discard tray to find the true count.
  final double decksLeft;

  const HiLoQuestion({
    required this.answer,
    required this.round,
    this.holeCardDown,
    this.lastCard,
    this.decksLeft = 1,
  });

  /// The true counts accepted for a running count of [runningCount]: the
  /// division rounded down or up, which covers every rounding convention
  /// counters use (floor, truncate, nearest).
  Set<int> acceptedTrueCounts(int runningCount) {
    final exact = runningCount / decksLeft;
    return {exact.floor(), exact.ceil()};
  }
}

class HiLoAnswer {
  final HiLoQuestion question;

  /// Null when the answer clock ran out first.
  final int? given;
  final Duration took;

  /// What the answer scored, in the modes that keep score.
  final HiLoPoints points;

  /// Whether a true count was asked for after the running count.
  final bool trueCountAsked;

  /// The true count given; null if not asked or the clock ran out.
  final int? trueCountGiven;

  const HiLoAnswer({
    required this.question,
    required this.given,
    this.took = Duration.zero,
    this.points = HiLoPoints.none,
    this.trueCountAsked = false,
    this.trueCountGiven,
  });

  /// Whether the running count was right. The true count is judged
  /// separately, by [trueCountCorrect].
  bool get correct => given == question.answer;
  bool get timedOut => given == null;

  /// The running count the true count is worked from: the player's own, so
  /// one slip is not punished twice.
  int get trueCountBasis => given ?? question.answer;

  /// Null when no true count was asked.
  bool? get trueCountCorrect {
    if (!trueCountAsked) return null;
    final tc = trueCountGiven;
    return tc != null &&
        question.acceptedTrueCounts(trueCountBasis).contains(tc);
  }

  HiLoSlip get slip {
    final g = given;
    if (g == null) return HiLoSlip.timeUp;
    return HiLoTrainingSession.diagnose(
      answer: question.answer,
      given: g,
      holeCardDown: question.holeCardDown,
      lastCard: question.lastCard,
    );
  }
}

enum _Phase {
  betweenRounds,
  dealing,
  playing,
  reveal,
  dealerDraw,
  settled,
  sweep
}

/// One training session: the shoe, the table, the count and the questions.
///
/// Call [advance] once per tick; each call makes exactly one visible change
/// to the table and says what it was. Before each tick, check [quizDue]; when
/// it is true, [ask] instead of advancing, then [answer] (or [close], for a
/// game that keeps its own score).
class HiLoTrainingSession {
  /// The dealer hits soft 17 and the seats play the matching chart. The rule
  /// set does not change the count; it only has to be a real table.
  static const rules = RuleSet.sixDeckH17;

  final HiLoTrainingConfig config;
  final Random _rng;

  late List<CardModel> _shoe;
  late List<HandModel> _seats;
  late int _players = config.players;
  int? _pendingPlayers;
  HandModel _dealer = const HandModel();

  _Phase _phase = _Phase.betweenRounds;

  /// Deal order for the opening two cards: a seat index, or [_dealerSlot].
  final List<int> _dealQueue = [];
  static const _dealerSlot = -1;

  /// The seat now playing its hand.
  int _actor = 0;
  bool _dealerNatural = false;

  int _runningCount = 0;
  int _cardsSeen = 0;
  CardModel? _lastSeen;
  int _discarded = 0;
  int _round = 0;
  int _shoeNumber = 1;
  bool _shuffledThisBreak = false;

  late int _nextQuizAt;
  HiLoQuestion? _open;
  int _closed = 0;
  final List<HiLoAnswer> _answers = [];
  int _streak = 0;
  int _bestStreak = 0;

  HiLoTrainingSession(this.config, {Random? rng}) : _rng = rng ?? Random() {
    _shoe = _freshShoe();
    _seats = List.filled(_players, const HandModel());
    _scheduleNextQuiz();
  }

  // ─── The table ──────────────────────────────────────────────────────────

  /// Seat hands, first base first.
  List<HandModel> get seats => List.unmodifiable(_seats);

  /// Seats in play this round.
  int get players => _players;

  /// Seat [count] players from the next round on — Survival fills the table
  /// as it speeds up. A round already dealt keeps its seats.
  void setPlayers(int count) {
    _pendingPlayers = count.clamp(1, HiLoTrainingConfig.playerOptions.last);
  }

  HandModel get dealer => _dealer;

  /// The seat taking cards right now, or null outside that part of a round.
  int? get activeSeat =>
      _phase == _Phase.playing && _actor < _seats.length ? _actor : null;

  /// The Hi-Lo count of every card turned face up since the last shuffle.
  int get runningCount => _runningCount;
  int get round => _round;
  int get shoeNumber => _shoeNumber;
  int get totalCards => config.decks * 52;
  int get cardsLeft => _shoe.length;

  /// How full the discard tray is, 0–1. Cards still on the felt are not in it.
  double get discardFill => _discarded / totalCards;

  /// Between a round's results and the sweep — the totals are final.
  bool get roundFinished => _phase == _Phase.sweep;

  /// The shoe is changed between rounds once fewer cards than this are left:
  /// the usual 75% penetration, or earlier when a full table could otherwise
  /// run the shoe dry mid-round.
  int get reshuffleAt =>
      max(totalCards ~/ 4, 8 * (max(_players, _pendingPlayers ?? 0) + 1));

  // ─── Questions ──────────────────────────────────────────────────────────

  List<HiLoAnswer> get answers => List.unmodifiable(_answers);
  int get correct => _answers.where((a) => a.correct).length;
  int get streak => _streak;
  int get bestStreak => _bestStreak;

  /// Questions asked and closed so far.
  int get questionsClosed => _closed;
  bool get isFinished => _closed >= config.questions;

  /// Cards seen since the session started, across every shoe.
  int get cardsSeen => _cardsSeen;

  /// The card count at which the next question is asked.
  int get nextQuizAt => _nextQuizAt;

  bool get quizDue => _open == null && !isFinished && _cardsSeen >= _nextQuizAt;

  HiLoQuestion? get openQuestion => _open;

  HiLoQuestion ask() {
    final hole = _dealer.cards.length >= 2 && !_dealer.cards[1].faceUp
        ? _dealer.cards[1]
        : null;
    return _open = HiLoQuestion(
      answer: _runningCount,
      round: _round,
      holeCardDown: hole,
      lastCard: _lastSeen,
      decksLeft:
          HiLoCounter.estimateDecks(_shoe.length, maxDecks: config.decks),
    );
  }

  /// Record one answer to the open question and close it. [given] is null
  /// when the answer clock ran out.
  HiLoAnswer answer(
    int? given, {
    Duration took = Duration.zero,
    HiLoPoints points = HiLoPoints.none,
  }) {
    final question = _open;
    if (question == null) {
      throw StateError('answer() called with no question open');
    }
    final result = HiLoAnswer(
      question: question,
      given: given,
      took: took,
      points: points,
    );
    _answers.add(result);
    if (result.correct) {
      _streak++;
      _bestStreak = max(_bestStreak, _streak);
    } else {
      _streak = 0;
    }
    close();
    return result;
  }

  /// Close the open question without recording an answer here — for a game
  /// that keeps its own score, such as a duel with two answers to one
  /// question.
  void close() {
    if (_open == null) {
      throw StateError('close() called with no question open');
    }
    _open = null;
    _closed++;
    _scheduleNextQuiz();
  }

  /// The most likely reason [given] is not [answer]. Checked in order of how
  /// specific the explanation is.
  static HiLoSlip diagnose({
    required int answer,
    required int given,
    CardModel? holeCardDown,
    CardModel? lastCard,
  }) {
    if (given == answer) return HiLoSlip.none;
    final hole = holeCardDown == null ? 0 : hiLoTag(holeCardDown);
    if (hole != 0 && given == answer + hole) return HiLoSlip.countedHoleCard;
    final last = lastCard == null ? 0 : hiLoTag(lastCard);
    if (last != 0 && given == answer - last) return HiLoSlip.missedLastCard;
    if (answer != 0 && given == -answer) return HiLoSlip.flippedSign;
    return HiLoSlip.drift;
  }

  void _scheduleNextQuiz() {
    final f = config.frequency;
    _nextQuizAt =
        _cardsSeen + f.minCards + _rng.nextInt(f.maxCards - f.minCards + 1);
  }

  // ─── Dealing ────────────────────────────────────────────────────────────

  /// Make the next visible change to the table.
  HiLoEvent advance() {
    while (true) {
      switch (_phase) {
        case _Phase.betweenRounds:
          if (!_shuffledThisBreak && _shoe.length < reshuffleAt) {
            _shuffle();
            _shuffledThisBreak = true;
            return const HiLoEvent(HiLoEventKind.shuffle);
          }
          _startRound();

        case _Phase.dealing:
          if (_dealQueue.isEmpty) {
            _afterDeal();
            continue;
          }
          final target = _dealQueue.removeAt(0);
          if (target == _dealerSlot) {
            final isHole = _dealer.cards.isNotEmpty;
            final card = _draw(faceUp: !isHole);
            _dealer = _dealer.addCard(card);
            if (isHole) return HiLoEvent(HiLoEventKind.holeCard, card: card);
            _see(card);
            return HiLoEvent(HiLoEventKind.card, card: card);
          }
          final card = _draw();
          _seats[target] = _seats[target].addCard(card);
          _see(card);
          return HiLoEvent(HiLoEventKind.card, card: card, seat: target);

        case _Phase.playing:
          final event = _playNextSeat();
          if (event != null) return event;
          _phase = _Phase.reveal;

        case _Phase.reveal:
          final hole = _dealer.cards[1].copyWith(faceUp: true);
          _dealer = _dealer.revealAll();
          _see(hole);
          _phase = !_dealerNatural && _anySeatLive
              ? _Phase.dealerDraw
              : _Phase.settled;
          return HiLoEvent(HiLoEventKind.reveal, card: hole);

        case _Phase.dealerDraw:
          if (_dealerHits) {
            final card = _draw();
            _dealer = _dealer.addCard(card);
            _see(card);
            return HiLoEvent(HiLoEventKind.card, card: card);
          }
          _phase = _Phase.settled;

        case _Phase.settled:
          _phase = _Phase.sweep;
          return const HiLoEvent(HiLoEventKind.roundOver);

        case _Phase.sweep:
          _discarded += _dealer.cards.length +
              _seats.fold<int>(0, (n, h) => n + h.cards.length);
          _dealer = const HandModel();
          _seats = List.filled(_players, const HandModel());
          _phase = _Phase.betweenRounds;
          _shuffledThisBreak = false;
          return const HiLoEvent(HiLoEventKind.sweep);
      }
    }
  }

  /// One card round the table from first base, the dealer's up card, then
  /// again with the dealer's second card face down.
  void _startRound() {
    final pending = _pendingPlayers;
    if (pending != null) {
      _players = pending;
      _pendingPlayers = null;
      _seats = List.filled(_players, const HandModel());
    }
    _round++;
    _dealerNatural = false;
    _actor = 0;
    _dealQueue
      ..clear()
      ..addAll([for (var i = 0; i < _players; i++) i])
      ..add(_dealerSlot)
      ..addAll([for (var i = 0; i < _players; i++) i])
      ..add(_dealerSlot);
    _phase = _Phase.dealing;
  }

  /// The dealer peeks under a ten or an ace. A natural ends the round before
  /// anyone plays.
  void _afterDeal() {
    final up = _dealer.cards.first.rank.value;
    if (up >= 10 && _dealer.isBlackjack) {
      _dealerNatural = true;
      _phase = _Phase.reveal;
    } else {
      _phase = _Phase.playing;
    }
  }

  /// The next card the seats take, or null once every seat has finished.
  /// Seats play the chart without splitting, so each keeps one hand.
  HiLoEvent? _playNextSeat() {
    while (_actor < _seats.length) {
      final hand = _seats[_actor];
      if (hand.isNatural || hand.isDoubled || hand.value >= 21) {
        _actor++;
        continue;
      }
      final move = BasicStrategy.best(
        hand: hand,
        dealerUp: _dealer.cards.first,
        canDouble: hand.cards.length == 2,
        canSplit: false,
        rules: rules,
        decks: config.decks,
      );
      if (move != StrategyMove.hit && move != StrategyMove.double) {
        _actor++;
        continue;
      }
      final card = _draw();
      final next = hand.addCard(card);
      _seats[_actor] = move == StrategyMove.double ? next.markDoubled() : next;
      _see(card);
      return HiLoEvent(HiLoEventKind.card, card: card, seat: _actor);
    }
    return null;
  }

  /// Someone is still waiting on the dealer: not bust, not paid a natural.
  bool get _anySeatLive => _seats.any((h) => !h.isBust && !h.isNatural);

  bool get _dealerHits {
    final v = _dealer.value;
    return v < 17 || (v == 17 && _dealer.isSoft && rules.dealerHitsSoft17);
  }

  void _see(CardModel card) {
    _runningCount += hiLoTag(card);
    _cardsSeen++;
    _lastSeen = card;
  }

  CardModel _draw({bool faceUp = true}) {
    // Not reachable in practice — [reshuffleAt] changes the shoe between
    // rounds while it still holds eight cards for every hand — but a deal
    // must never throw.
    if (_shoe.isEmpty) _shuffle();
    return _shoe.removeLast().copyWith(faceUp: faceUp);
  }

  void _shuffle() {
    _shoe = _freshShoe();
    _runningCount = 0;
    _discarded = 0;
    _lastSeen = null;
    _shoeNumber++;
  }

  List<CardModel> _freshShoe() => [
        for (var d = 0; d < config.decks; d++)
          for (final suit in Suit.values)
            for (final rank in Rank.values) CardModel(suit: suit, rank: rank),
      ]..shuffle(_rng);
}

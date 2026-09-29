import '../engine/game_engine.dart';
import '../models/game_state.dart';
import 'basic_strategy.dart';
import 'deviations.dart';

/// What the coach thinks of the hand in front of the player.
class CoachVerdict {
  /// The play to make.
  final StrategyMove best;

  /// What basic strategy alone would say.
  final StrategyMove basic;

  /// The index play that decided [best], when index plays are on and one
  /// governs this hand — whether or not the count moved it off [basic].
  final IndexDecision? index;

  const CoachVerdict({required this.best, required this.basic, this.index});
}

/// The single place the table asks "what is the right play?" — for the hint
/// on the buttons and for grading the decision the player made, so the two
/// can never disagree.
class TableCoach {
  const TableCoach._();

  static CoachVerdict? verdict(
    GameState state,
    GameEngine engine, {
    required bool indexPlays,
  }) {
    if (!state.hasActiveHand) return null;
    final dealer = state.dealerHand;
    if (dealer.cards.isEmpty) return null;
    final hand = state.activeHand;
    if (hand.cards.length < 2) return null;

    final canDouble = engine.canDoubleActiveHand(state);
    final canSplit = engine.canSplitActiveHand(state);
    final canSurrender = engine.canSurrenderActiveHand(state);
    final up = dealer.cards.first;

    final basic = BasicStrategy.best(
      hand: hand,
      dealerUp: up,
      canDouble: canDouble,
      canSplit: canSplit,
      canSurrender: canSurrender,
      rules: engine.rules,
      decks: engine.numDecks,
    );
    if (indexPlays && !engine.continuous) {
      final index = Deviations.lookup(
        hand: hand,
        dealerUp: up,
        trueCount: state.trueCount,
        rules: engine.rules,
        decks: engine.numDecks,
        canDouble: canDouble,
        canSplit: canSplit,
        canSurrender: canSurrender,
      );
      if (index != null) {
        return CoachVerdict(best: index.move, basic: basic, index: index);
      }
    }
    return CoachVerdict(best: basic, basic: basic);
  }

  /// Whether insurance is graded at all: only when index plays are on, on a
  /// counted multi-deck shoe. Flat basic strategy never insures, but that is
  /// exactly the advice a counter learns to break at +3.
  static bool gradesInsurance(GameEngine engine, {required bool indexPlays}) =>
      indexPlays && !engine.continuous && engine.numDecks >= Deviations.minDecks;
}

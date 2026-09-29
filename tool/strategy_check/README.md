# Strategy chart verification

The coach's basic strategy (`lib/core/strategy/basic_strategy.dart`) is checked
two independent ways. Nothing here ships in the app.

## 1. Against a published strategy engine — every cell

`reference_charts.json` holds 48 charts scraped on 2026-09-28 from the
[blackjackinfo.com basic strategy engine](https://www.blackjackinfo.com/blackjack-basic-strategy-engine/)
(US peek), one for every rule combination the app can deal:

- decks 2, 6, 8 · dealer H17 / S17 · DAS yes / no · double any two / 9–11 /
  10–11 · late surrender yes / no

`fetch_reference.sh` re-downloads the HTML, `parse_bji.py` reads the three
tables, and `export_fixture.py` writes `test/fixtures/strategy_reference.dart`.
`test/strategy_reference_test.dart` then asserts every cell (48 × 320).

Before relying on the engine it was checked against the app's existing,
hand-verified 6-deck charts (H17, S17, no-DAS, 9–11 doubles): 0 differences.
6- and 8-deck charts are identical for every combination.

## 2. Against our own expected-value calculation — the cells that changed

`bjcalc.py` is an independent composition-dependent EV calculator: every card
is removed from the shoe as it is dealt, the dealer's peek is modelled exactly
(the player draws from a shoe that still holds the unknown hole card, which is
known not to complete a blackjack), and total-dependent decisions weight each
two-card composition by how likely it is to be dealt. Splits are evaluated as
one split without resplitting.

`crosscheck_cells.py` re-derives every cell where the 2-deck or surrender
charts differ from the 6-deck no-surrender chart, and their neighbours, for
2 and 6 decks × H17/S17 × DAS/no-DAS × with/without surrender: **168 of 168
agree** with the reference (`crosscheck_results.txt`).

One trap worth recording: a first version enumerated the dealer's hole card
explicitly and let the player's later hit/stand choices see it. That made
hitting look far too good against a ten or an ace (16 v 10 hit came out
−0.507 instead of −0.535). Decisions must be made with the hole card unknown.

## Index plays

`lib/core/strategy/deviations.dart` uses the published Illustrious 18 and Fab 4
(Wizard of Odds, six decks S17 DAS LS; and the usual H17 shifts: 11 v A −1,
10 v A +3, 12 v 6 −3, 15 v A surrender −1). Those numbers come from
simulation and depend on the true-count convention; they are not re-derived
here.

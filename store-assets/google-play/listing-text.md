# Hi-Lo Blackjack Trainer — Google Play Listing

> Rewritten for search intent. The old listing never used the phrase
> **"card counting"** — the query this app's audience actually types — and
> predated online multiplayer entirely. Character limits are enforced by Play:
> title 30, short description 80, full description 4000.

## App Name (30 char limit)

**Keep the published name — 23 chars**

```
Hi-Lo Blackjack Trainer
```

It already carries the two highest-value terms, *Blackjack* and *Trainer*, and
"Hi-Lo" makes it distinctive where a generic "Blackjack Card Count Trainer"
would not be. It is also the name attached to the existing listing, reviews and
installs, so changing it throws away what little recognition exists for no
keyword gain.

**"Card counting" belongs in the short description and the opening sentence
instead** — both are indexed, both are read, and neither costs the name.

## Short Description (80 char limit)

**Recommended — 76 chars**

```
Learn card counting. A coach scores every play. Blackjack with friends too.
```

Play indexes this field heavily, and it is the one line most people read. It
now leads with the search term, names the system, and closes on the feature
nothing else in this category has.

## Full Description (4000 char limit)

```
Card counting, taught properly. Hi-Lo Blackjack Trainer is a practice table
built for players who want to drill basic strategy and card counting until both
are automatic — then test them against friends in real time.

A built-in coach scores every decision against the correct play for your
table and tells you when a play was wrong — "16 vs 5, basic strategy says
Stand". Accuracy is tracked by hard totals, soft totals and pairs, and the
hands you miss most are listed so you can drill them.

TRAINING CENTER
- Strategy Drill: flash-card hands with instant feedback, or only your misses
- Strategy Chart: the exact chart the coach grades you on, for your rules
- Daily Count Drill: tag 20 cards +1, 0 or -1 against the clock
- Speed Count: cards flash by at table pace, including the deck countdown
- True Count: convert running count to true count using the discard tray
- Index Plays: the Illustrious 18 and Fab 4, drilled at the counts that matter

PLAY LIKE A COUNTER
- Hi-Lo running count and true count, live as cards are dealt
- Hide the count and the dealer quizzes your running count every 5 hands
- Index plays: turn them on and the coach follows the count, not just the chart
- Bet spread coach: shows the bet the true count calls for, and checks yours
- A discard tray on the felt, so you estimate decks left the way pros do
- Insurance graded against the +3 index

CHOOSE YOUR TABLE
Strategy is not universal. Pick the table you are practising for and the
dealer, the coach, the chart and the felt all follow it:
- 2, 6 or 8 decks, or a continuous shuffler — with the right chart for each
- Dealer hits or stands on soft 17
- Late surrender, double after split, doubling on any two or 9-11 only
- 3:2 or 6:5 blackjack, so you can see exactly what a 6:5 table costs you

PLAY ONLINE WITH FRIENDS
Host a private table and share its room code, or join an open table. Up to
five players share one dealer and one shoe, with the running count on screen.

WEEKLY LEAGUES
- Profit league and an Accuracy league — who made the best decisions
- Hi-Lo Daily: one shared shoe and one ranked attempt each day
- Survival league: your best run of the week earns the rank
- Lifetime stats: hands, win rate, blackjacks, surrenders, net at the table
- Daily bonus streak

Free to play, with ads.

This app is for entertainment and practice only. There is no real-money
gambling, no real-money prizes, no betting with real currency, and no way to
cash out virtual chips. Nothing here is a guarantee of results in a casino.
```

## Release Notes (500 char limit)

```
New in 1.3.1:

- Hi-Lo Daily leaderboard: one shared shoe and one ranked attempt each day
- Weekly Survival leaderboard: your best run earns the rank
- New leaderboard screens for daily and weekly Hi-Lo training
- Better offline handling when rankings cannot be reached
```

## Notes for whoever edits this next

- **Do not A/B test yet.** At ~200 impressions per month a store listing
  experiment cannot reach significance. Make one decisive change, then wait.
- **Translations are the cheapest reach you have.** The listing is short and
  Play will machine-translate it; even five languages meaningfully widens
  who can be shown the app.
- **Screenshots are stale.** They predate online multiplayer. The lobby and a
  five-seat table are the two shots that differentiate this app from every
  other blackjack trainer — they should be first and second.
- **The weekly leaderboard is now real** — the 25 simulated competitors are
  gone and players rank against each other. The listing copy above depends on
  that being switched on: apply
  `supabase/migrations/20260825000000_weekly_rankings.sql` and enable
  anonymous sign-ins **before** you publish this text, or the description
  promises something the app is quietly falling back from.

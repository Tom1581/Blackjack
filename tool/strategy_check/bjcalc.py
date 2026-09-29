"""Independent blackjack EV calculator used to cross-check strategy charts.

Composition-dependent: every card drawn is removed from the shoe, for the
player and the dealer. US peek game, handled exactly: the shoe the player
draws from still contains the dealer's unknown hole card, which is known not
to complete a dealer blackjack. At any point the hole card is a uniformly
random card of what remains, excluding the blackjack rank, so

  P(player draws r) = S[r](N-B-1)/((N-B)(N-1))   for r != blocked rank
                    = S[r]/(N-1)                  for r == blocked rank

where S is the remaining shoe *including* the hole card, N = |S| and
B = S[blocked]. With no peek (dealer 2-9) B = 0 and this is just S[r]/N.
Crucially the player's decisions never see the hole card.

Splits: one split, no resplit (an approximation; see README).
"""
import sys
from functools import lru_cache

sys.setrecursionlimit(10000)

def make_shoe(decks):
    # index 0..9 = ranks 1(ace)..10
    return tuple([4 * decks] * 9 + [16 * decks])

def remove(shoe, r):
    l = list(shoe); l[r - 1] -= 1; assert l[r - 1] >= 0; return tuple(l)

def total(cards):
    t = sum(cards); soft = False
    if 1 in cards and t + 10 <= 21:
        t += 10; soft = True
    return t, soft

def blocked_rank(up):
    return 10 if up == 1 else (1 if up == 10 else None)

@lru_cache(maxsize=None)
def dealer_final(shoe, t_hard, has_ace, h17):
    """Dealer final totals (17,18,19,20,21,bust) from a partial hand."""
    soft = has_ace and t_hard + 10 <= 21
    t = t_hard + (10 if soft else 0)
    if t > 21:
        return (0, 0, 0, 0, 0, 1)
    if t >= 17 and not (h17 and soft and t == 17):
        out = [0] * 6; out[t - 17] = 1; return tuple(out)
    n_cards = sum(shoe)
    acc = [0.0] * 6
    for r in range(1, 11):
        c = shoe[r - 1]
        if not c: continue
        p = c / n_cards
        sub = dealer_final(remove(shoe, r), t_hard + r, has_ace or r == 1, h17)
        for i in range(6): acc[i] += p * sub[i]
    return tuple(acc)

@lru_cache(maxsize=None)
def dealer_dist(shoe, up, h17):
    """Dealer's final distribution; [shoe] still holds the hole card."""
    b = blocked_rank(up)
    n = sum(shoe); nb = n - (shoe[b - 1] if b else 0)
    acc = [0.0] * 6
    for h in range(1, 11):
        c = shoe[h - 1]
        if not c or h == b: continue
        sub = dealer_final(remove(shoe, h), up + h, up == 1 or h == 1, h17)
        for i in range(6): acc[i] += c / nb * sub[i]
    return tuple(acc)

def draw_probs(shoe, up):
    b = blocked_rank(up)
    n = sum(shoe); B = shoe[b - 1] if b else 0
    out = []
    for r in range(1, 11):
        c = shoe[r - 1]
        if not c: continue
        p = c / (n - 1) if r == b else c * (n - B - 1) / ((n - B) * (n - 1))
        out.append((r, p))
    return out

def stand_ev(ptotal, shoe, up, h17):
    if ptotal > 21: return -1.0
    d = dealer_dist(shoe, up, h17)
    ev = d[5]
    for i, dt in enumerate(range(17, 22)):
        if ptotal > dt: ev += d[i]
        elif ptotal < dt: ev -= d[i]
    return ev

@lru_cache(maxsize=None)
def best_after(cards, shoe, up, h17, can_double):
    t, _ = total(cards)
    if t > 21: return -1.0
    best = max(stand_ev(t, shoe, up, h17), hit_ev(cards, shoe, up, h17))
    if can_double:
        best = max(best, double_ev(cards, shoe, up, h17))
    return best

@lru_cache(maxsize=None)
def hit_ev(cards, shoe, up, h17):
    ev = 0.0
    for r, p in draw_probs(shoe, up):
        nc = tuple(sorted(cards + (r,)))
        t, _ = total(nc)
        ev += p * (-1.0 if t > 21 else best_after(nc, remove(shoe, r), up, h17, False))
    return ev

@lru_cache(maxsize=None)
def double_ev(cards, shoe, up, h17):
    ev = 0.0
    for r, p in draw_probs(shoe, up):
        t, _ = total(cards + (r,))
        ev += p * 2 * stand_ev(t, remove(shoe, r), up, h17)
    return ev

def split_ev(pr, shoe, up, h17, das):
    ev = 0.0
    for r, p in draw_probs(shoe, up):
        hand = tuple(sorted((pr, r)))
        s2 = remove(shoe, r)
        sub = stand_ev(total(hand)[0], s2, up, h17) if pr == 1 else best_after(hand, s2, up, h17, das)
        ev += p * sub
    return 2 * ev

def action_evs(cards, shoe, up, h17, das, ls, dbl_ok, pair):
    t, _ = total(cards)
    e = {'S': stand_ev(t, shoe, up, h17), 'H': hit_ev(cards, shoe, up, h17)}
    if dbl_ok: e['D'] = double_ev(cards, shoe, up, h17)
    if pair: e['P'] = split_ev(cards[0], shoe, up, h17, das)
    if ls: e['R'] = -0.5
    return e

def _weighted(kind, value, up, decks, h17, das, ls, dbl):
    shoe0 = remove(make_shoe(decks), up)
    if kind == 'hard':
        comps = [(a, b) for a in range(2, 11) for b in range(a + 1, 11) if a + b == value]
    elif kind == 'soft':
        comps = [(1, value)]
    else:
        comps = [(value, value)]
    evs = {}; wsum = 0.0
    for (a, b) in comps:
        n = sum(shoe0)
        w = shoe0[a - 1] / n * remove(shoe0, a)[b - 1] / (n - 1) * (1 if a == b else 2)
        shoe = remove(remove(shoe0, a), b)
        cards = tuple(sorted((a, b)))
        t, soft = total(cards)
        dbl_ok = dbl == 'all' or (not soft and ((dbl == 'd9' and 9 <= t <= 11) or (dbl == 'd10' and 10 <= t <= 11)))
        for k, v in action_evs(cards, shoe, up, h17, das, ls, dbl_ok, kind == 'pair').items():
            evs[k] = evs.get(k, 0) + w * v
        wsum += w
    return {k: v / wsum for k, v in evs.items()}

def cell(kind, value, up, decks, h17, das, ls, dbl='all'):
    """Total-dependent chart cell, in the reference alphabet H S D d P R r p."""
    evs = _weighted(kind, value, up, decks, h17, das, ls, dbl)
    best = max(evs, key=evs.get)
    def best_without(excl):
        return max((k for k in evs if k not in excl), key=evs.get)
    if best == 'D':
        return 'd' if best_without({'D', 'R'}) == 'S' else 'D'
    if best == 'R':
        return {'H': 'R', 'S': 'r', 'P': 'p'}[best_without({'R', 'D'})]
    return best

def cell_evs(kind, value, up, decks, h17, das, ls, dbl='all'):
    return {k: round(v, 5) for k, v in _weighted(kind, value, up, decks, h17, das, ls, dbl).items()}

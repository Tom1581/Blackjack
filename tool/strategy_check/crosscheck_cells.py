"""Re-derive the cells where the 2-deck and surrender charts differ from the
6-deck no-surrender chart, and compare with the reference engine."""
import json, sys, time
import bjcalc
db = json.load(open('reference_charts.json'))
UPS = [2,3,4,5,6,7,8,9,10,1]
UPL = ['2','3','4','5','6','7','8','9','T','A']
def ref_code(key, kind, value, up):
    col = UPS.index(up)
    if kind == 'hard':
        rows = db[key]['Hard Totals']; name = str(value) if value < 18 else '18+'
    elif kind == 'soft':
        rows = db[key]['Soft Totals']; name = f'A,{value}'
    else:
        rows = db[key]['Pairs']; name = {1:'A',10:'T'}.get(value, str(value)); name = f'{name},{name}'
    for n, acts in rows:
        if n == name: return acts[col]
    raise KeyError(name)
cells = []
for d in (2, 6):
    for s17 in ('h17', 's17'):
        for das in ('dasyes', 'dasno'):
            for surr in ('ns', 'ls'):
                key = f'd{d}_{s17}_{das}_all_{surr}'
                base = [('hard', 9, 2), ('soft', 3, 4), ('hard', 11, 1), ('pair', 6, 7), ('pair', 7, 8), ('pair', 6, 2)]
                if surr == 'ls':
                    base += [('hard', 15, 10), ('hard', 15, 1), ('hard', 16, 9), ('hard', 16, 10), ('hard', 16, 1), ('hard', 17, 1), ('pair', 8, 1), ('hard', 14, 10), ('hard', 15, 9)]
                for c in base: cells.append((key, d, s17 == 'h17', das == 'dasyes', surr == 'ls') + c)
bad = 0
for key, d, h17, das, ls, kind, value, up in cells:
    t = time.time()
    got = bjcalc.cell(kind, value, up, d, h17, das, ls)
    want = ref_code(key, kind, value, up)
    ok = got == want
    bad += not ok
    print(f"{'OK ' if ok else 'BAD'} {key:24} {kind} {value} v {UPL[UPS.index(up)]}: ref {want} calc {got} ({time.time()-t:.0f}s)", flush=True)
print('DONE mismatches:', bad, 'of', len(cells))

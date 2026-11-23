"""Task 5F metrics: baseline and fix, same rows. usage: python3 -I metrics_5f.py BASE.jsonl FIX.jsonl [--claude-part dev|final]

Per row (dump_5f_test.dart): found (the matcher found the expression), asIdiom (the expression's meaning is shown),
conf, fit (review-card path with the expression's own Turkish).
  idiom precision / recall / F1: idiom rows = gold 'idiom'; predicted idiom = asIdiom. Rows not found count as
    "not shown" (recall over all rows).
  literal false positive: gold literal rows shown as idiom.
  wrong sure: gold literal / either / none rows shown as idiom AND sure (the error 5F is about).
  sure coverage: rows shown as idiom with 'sure'.
  card false accept: fit == confirmed on a row whose gold is not 'idiom' (a card would be graded right on a
    wrong reading); card accept on idiom rows: fit == confirmed on gold idiom rows.
Wilson 95 % intervals. McNemar exact (two-sided) for paired changes.
"""
import json, math, sys


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - r) / d, (c + r) / d)


def frac(k, n):
    lo, hi = wilson(k, n)
    return f'{k}/{n} = {100 * k / n if n else 0:.1f} % [{100 * lo:.0f}-{100 * hi:.0f}]'


def mcnemar(b, c):
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    p = sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, 2 * p)


def load(p, part=None):
    rows = [json.loads(l) for l in open(p, encoding='utf-8')]
    return [r for r in rows if part is None or r['part'] == part]


def stats(rows):
    idi = [r for r in rows if r['gold'] == 'idiom']
    non = [r for r in rows if r['gold'] != 'idiom']
    lit = [r for r in rows if r['gold'] == 'literal']
    tp = sum(1 for r in idi if r.get('asIdiom'))
    fp = sum(1 for r in non if r.get('asIdiom'))
    prec = tp / (tp + fp) if tp + fp else 0
    rec = tp / len(idi) if idi else 0
    f1 = 2 * prec * rec / (prec + rec) if prec + rec else 0
    shown_sure = [r for r in rows if r.get('asIdiom') and r.get('conf') == 'sure']
    return {
        'rows': f"{len(idi)} idiom / {len(lit)} literal / {len(non) - len(lit)} other",
        'found (idiom rows)': frac(sum(1 for r in idi if r.get('found')), len(idi)),
        'precision': frac(tp, tp + fp),
        'recall': frac(tp, len(idi)),
        'F1': f'{100 * f1:.1f}',
        'literal shown as idiom': frac(sum(1 for r in lit if r.get('asIdiom')), len(lit)),
        'WRONG SURE (non-idiom shown as sure idiom)': frac(sum(1 for r in non if r.get('asIdiom') and r.get('conf') == 'sure'), len(non)),
        'sure idioms that are wrong': frac(sum(1 for r in shown_sure if r['gold'] != 'idiom'), len(shown_sure)),
        'sure coverage (all rows)': frac(len(shown_sure), len(rows)),
        'card false accept (non-idiom)': frac(sum(1 for r in non if r.get('fit') == 'confirmed'), sum(1 for r in non if 'fit' in r)),
        'card accept (idiom rows)': frac(sum(1 for r in idi if r.get('fit') == 'confirmed'), sum(1 for r in idi if 'fit' in r)),
    }


def main():
    part = sys.argv[sys.argv.index('--claude-part') + 1] if '--claude-part' in sys.argv else None
    a, b = load(sys.argv[1], part), load(sys.argv[2], part)
    assert [r['sentence'] for r in a] == [r['sentence'] for r in b]
    sa, sb = stats(a), stats(b)
    print('| metric | baseline (main) | 5F |\n|---|---|---|')
    for k in sa:
        print(f'| {k} | {sa[k]} | {sb[k]} |')
    def paired(name, f):
        x = sum(1 for r, s in zip(a, b) if f(r) and not f(s))
        y = sum(1 for r, s in zip(a, b) if not f(r) and f(s))
        print(f'| paired: {name} | lost {x}, gained {y} | McNemar p = {mcnemar(x, y):.2g} |')
    paired('idiom rows shown as idiom', lambda r: r['gold'] == 'idiom' and bool(r.get('asIdiom')))
    paired('wrong sure', lambda r: r['gold'] != 'idiom' and bool(r.get('asIdiom')) and r.get('conf') == 'sure')
    paired('card false accept', lambda r: r['gold'] != 'idiom' and r.get('fit') == 'confirmed')
    # literal false positives that stay: why
    ch = [(r, s) for r, s in zip(a, b) if (r.get('conf'), r.get('asIdiom'), r.get('fit')) != (s.get('conf'), s.get('asIdiom'), s.get('fit'))]
    print(f'\nrows changed: {len(ch)}')
    for r, s in ch[:int(sys.argv[sys.argv.index("--show") + 1]) if "--show" in sys.argv else 0]:
        print(f"  [{r['gold']}] {r['phrase']}: {r.get('conf')}/{r.get('asIdiom')}/{r.get('fit')} -> {s.get('conf')}/{s.get('asIdiom')}/{s.get('fit')} | {s.get('reason', '')[:70]}")


main()

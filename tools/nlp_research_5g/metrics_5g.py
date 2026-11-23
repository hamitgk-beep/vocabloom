"""Task 5G metrics: baseline and candidate on the same rows.

usage: python3 -I tools/nlp_research_5g/metrics_5g.py BASE.jsonl CAND.jsonl [--part dev|final] [--show N]

Per row (dump_5g_test.dart): found (the matcher found the expression), asIdiom (the expression's meaning is shown
in the reader), conf, fit (review-card path with the expression's own Turkish).
Four outcomes are kept apart: idiom found / idiom meaning shown / idiom meaning shown as SURE / card auto-accepted.
  literal false positive: gold literal rows whose idiom meaning is shown (the 5G target).
  idiom precision / recall / F1: predicted idiom = asIdiom, over all rows (rows not found are "not shown").
  match recall: idiom rows found by the matcher.
  wrong sure: non-idiom rows shown as a SURE idiom. Sure coverage: rows shown as a sure idiom.
  card false accept: fit == confirmed on a non-idiom row; card accept on idiom rows; manual: fit != confirmed.
Wilson 95 % intervals; McNemar exact two-sided test for paired changes.
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
    return f'{k}/{n} = {100 * k / n if n else 0:.1f} % [{100 * lo:.1f}-{100 * hi:.1f}]'


def mcnemar(b, c):
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n)


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
    sure = [r for r in rows if r.get('asIdiom') and r.get('conf') == 'sure']
    fit_non = [r for r in non if 'fit' in r]
    fit_idi = [r for r in idi if 'fit' in r]
    return {
        'rows': f"{len(idi)} idiom / {len(lit)} literal / {len(non) - len(lit)} other",
        'LITERAL SHOWN AS IDIOM': frac(sum(1 for r in lit if r.get('asIdiom')), len(lit)),
        'literal found by matcher': frac(sum(1 for r in lit if r.get('found')), len(lit)),
        'match recall (idiom rows found)': frac(sum(1 for r in idi if r.get('found')), len(idi)),
        'precision': frac(tp, tp + fp),
        'recall': frac(tp, len(idi)),
        'F1': f'{100 * f1:.1f}',
        'wrong sure (non-idiom, sure idiom)': frac(sum(1 for r in non if r.get('asIdiom') and r.get('conf') == 'sure'), len(non)),
        'sure coverage (all rows)': frac(len(sure), len(rows)),
        'sure that are right': frac(sum(1 for r in sure if r['gold'] == 'idiom'), len(sure)),
        'card false accept (non-idiom)': frac(sum(1 for r in fit_non if r['fit'] == 'confirmed'), len(fit_non)),
        'card accept (idiom rows)': frac(sum(1 for r in fit_idi if r['fit'] == 'confirmed'), len(fit_idi)),
        'card manual (idiom rows, not auto-graded)': frac(sum(1 for r in fit_idi if r['fit'] != 'confirmed'), len(fit_idi)),
    }


def main():
    part = sys.argv[sys.argv.index('--part') + 1] if '--part' in sys.argv else None
    show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 0
    a, b = load(sys.argv[1], part), load(sys.argv[2], part)
    assert [r['sentence'] for r in a] == [r['sentence'] for r in b]
    sa, sb = stats(a), stats(b)
    print('| metric | baseline (5F) | 5G candidate |\n|---|---|---|')
    for k in sa:
        print(f'| {k} | {sa[k]} | {sb[k]} |')

    def paired(name, good):
        x = sum(1 for r, s in zip(a, b) if good(r) and not good(s))
        y = sum(1 for r, s in zip(a, b) if not good(r) and good(s))
        print(f'| paired: {name} | worse {x}, better {y} | McNemar p = {mcnemar(x, y):.2g} |')
    paired('literal row NOT shown as idiom', lambda r: r['gold'] == 'literal' and not r.get('asIdiom'))
    paired('idiom row shown as idiom', lambda r: r['gold'] == 'idiom' and bool(r.get('asIdiom')))
    paired('no wrong sure', lambda r: not (r['gold'] != 'idiom' and r.get('asIdiom') and r.get('conf') == 'sure'))
    paired('no card false accept', lambda r: not (r['gold'] != 'idiom' and r.get('fit') == 'confirmed'))
    paired('right sure kept', lambda r: r['gold'] == 'idiom' and bool(r.get('asIdiom')) and r.get('conf') == 'sure')
    ch = [(r, s) for r, s in zip(a, b) if (r.get('conf'), r.get('asIdiom'), r.get('fit')) != (s.get('conf'), s.get('asIdiom'), s.get('fit'))]
    print(f'\nrows changed: {len(ch)}')
    for r, s in ch[:show]:
        print(f"  [{r['gold']}] {r['phrase']}: {r.get('conf')}/{r.get('asIdiom')}/{r.get('fit')} -> {s.get('conf')}/{s.get('asIdiom')}/{s.get('fit')} | {s.get('reason', '')[:60]}")


main()

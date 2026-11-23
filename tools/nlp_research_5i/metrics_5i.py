"""Task 5I metrics (5H metrics plus the 5I ones): baseline and candidate dumps (dump_5i_test.dart) on the same rows.

usage: python3 -I tools/nlp_research_5i/metrics_5i.py BASE.jsonl CAND.jsonl [--show N]

Kept apart, per row (gold from MAGPIE: idiom / literal):
  (i)   literal shown as idiom: gold literal, the expression's meaning shown (asIdiom).
  (ii)  idiom precision / recall / F1, predicted idiom = asIdiom, over all rows.
  (iii) match recall: gold idiom rows the matcher found.
  (iv)  wrong sure: gold literal shown as a SURE idiom; also gold idiom shown as a SURE word-by-word reading.
  (v)   card false accept: fit == confirmed on a gold literal row (card accept on idiom rows reported too).
  (vi)  empty panel: found, nothing shown (no Turkish); by gold label.
  (vii) right and sourced: gold idiom with the idiom's checked meaning shown (no AI draft, no derived Turkish);
        gold literal with a word-by-word reading shown from a checked source. Whether the word SENSE is the right
        one is not in MAGPIE's labels: that part was read by hand on a sample (see the report).
  Also: wrong "literal" claim (gold idiom, the panel says the words are meant one by one), and a wrong meaning
  shown (gold idiom with a word-by-word Turkish meaning shown).
Wilson 95 % intervals; McNemar exact two-sided test on paired rows.
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


def checked(r):
    return r.get('shown') and not r.get('bestDraft') and not r.get('bestDerived')


PREDS = {
    'literal shown as idiom (i)': (lambda r: r['gold'] == 'literal', lambda r: bool(r.get('asIdiom'))),
    'idiom recall (ii)': (lambda r: r['gold'] == 'idiom', lambda r: bool(r.get('asIdiom'))),
    'match recall (iii)': (lambda r: r['gold'] == 'idiom', lambda r: bool(r.get('found'))),
    'wrong sure idiom (iv)': (lambda r: r['gold'] == 'literal', lambda r: bool(r.get('asIdiom')) and r.get('conf') == 'sure'),
    'wrong sure literal (iv)': (lambda r: r['gold'] == 'idiom', lambda r: bool(r.get('literal')) and r.get('shown') and r.get('conf') == 'sure'),
    'card false accept (v)': (lambda r: r['gold'] == 'literal' and 'fit' in r, lambda r: r.get('fit') == 'confirmed'),
    'card accept, idiom rows': (lambda r: r['gold'] == 'idiom' and 'fit' in r, lambda r: r.get('fit') == 'confirmed'),
    'empty panel, all found (vi)': (lambda r: bool(r.get('found')), lambda r: not r.get('shown')),
    'empty panel, gold literal (vi)': (lambda r: r['gold'] == 'literal' and r.get('found'), lambda r: not r.get('shown')),
    'empty panel, gold idiom (vi)': (lambda r: r['gold'] == 'idiom' and r.get('found'), lambda r: not r.get('shown')),
    'right+sourced, gold idiom (vii)': (lambda r: r['gold'] == 'idiom', lambda r: bool(r.get('asIdiom')) and checked(r)),
    'right+sourced, gold literal (vii)': (lambda r: r['gold'] == 'literal', lambda r: bool(r.get('literal')) and checked(r)),
    'wrong literal claim (gold idiom)': (lambda r: r['gold'] == 'idiom', lambda r: bool(r.get('literal'))),
    'word meaning shown on idiom row': (lambda r: r['gold'] == 'idiom', lambda r: bool(r.get('literal')) and bool(r.get('shown'))),
    'literal claim, gold literal (kept?)': (lambda r: r['gold'] == 'literal', lambda r: bool(r.get('literal'))),
    'sure literal, gold literal (lost?)': (lambda r: r['gold'] == 'literal', lambda r: bool(r.get('literal')) and r.get('shown') and r.get('conf') == 'sure'),
    'word tap: empty panel': (lambda r: 'tap' in r, lambda r: not r['tap']['shown']),
    'word tap: checked Turkish shown': (lambda r: 'tap' in r, lambda r: r['tap']['shown'] and not r['tap']['draft']),
    'word tap: AI-draft Turkish shown': (lambda r: 'tap' in r, lambda r: r['tap']['shown'] and bool(r['tap']['draft'])),
    'word tap: sure, gold idiom': (lambda r: 'tap' in r and r['gold'] == 'idiom', lambda r: r['tap']['shown'] and r['tap']['conf'] == 'sure' and r['tap']['cat'] is None),
    'panel says "cannot tell" (idiomOrWords)': (lambda r: bool(r.get('found')), lambda r: r.get('gap') == 'idiomOrWords'),
    '"cannot tell" on gold idiom (needless?)': (lambda r: r['gold'] == 'idiom' and r.get('found'), lambda r: r.get('gap') == 'idiomOrWords'),
    '"cannot tell" on gold literal': (lambda r: r['gold'] == 'literal' and r.get('found'), lambda r: r.get('gap') == 'idiomOrWords'),
    'needless "cannot tell": checked idiom Tr exists, gold idiom': (lambda r: r['gold'] == 'idiom' and r.get('found') and (r.get('idiomTr') or 0) > 0, lambda r: r.get('gap') == 'idiomOrWords'),
    'idiom shown (any conf), gold literal, found': (lambda r: r['gold'] == 'literal' and r.get('found'), lambda r: bool(r.get('asIdiom'))),
    'word card false accept (gold idiom)': (lambda r: r['gold'] == 'idiom' and 'wfit' in r, lambda r: r.get('wfit') == 'confirmed'),
    'any sure on found row': (lambda r: bool(r.get('found')), lambda r: r.get('conf') == 'sure' and r.get('shown')),
    'UI: word-by-word note on expression card': (lambda r: bool(r.get('found')), lambda r: bool(r.get('literal'))),
    'UI: word-by-word note, gold idiom (wrong note)': (lambda r: r['gold'] == 'idiom' and r.get('found'), lambda r: bool(r.get('literal'))),
    'UI: word-by-word note, gold literal (right note)': (lambda r: r['gold'] == 'literal' and r.get('found'), lambda r: bool(r.get('literal'))),
}


def prf(rows):
    tp = sum(1 for r in rows if r['gold'] == 'idiom' and r.get('asIdiom'))
    fp = sum(1 for r in rows if r['gold'] != 'idiom' and r.get('asIdiom'))
    n = sum(1 for r in rows if r['gold'] == 'idiom')
    p = tp / (tp + fp) if tp + fp else 0
    rc = tp / n if n else 0
    return f'precision {frac(tp, tp + fp)}; F1 {200 * p * rc / (p + rc) if p + rc else 0:.1f}'


def main():
    a = [json.loads(l) for l in open(sys.argv[1], encoding='utf-8')]
    b = [json.loads(l) for l in open(sys.argv[2], encoding='utf-8')]
    show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 0
    assert len(a) == len(b) and all(x['id'] == y['id'] and x['sentence'] == y['sentence'] for x, y in zip(a, b)), 'rows differ'
    print(f"rows: {sum(1 for r in a if r['gold'] == 'idiom')} idiom / {sum(1 for r in a if r['gold'] == 'literal')} literal")
    print('base:', prf(a))
    print('cand:', prf(b))
    for name, (den, num) in PREDS.items():
        pairs = [(x, y) for x, y in zip(a, b) if den(x) or den(y)]
        da = [x for x, _ in pairs if den(x)]
        db = [y for _, y in pairs if den(y)]
        ka, kb = sum(1 for r in da if num(r)), sum(1 for r in db if num(r))
        up = [(x, y) for x, y in zip(a, b) if den(x) and den(y) and not num(x) and num(y)]
        dn = [(x, y) for x, y in zip(a, b) if den(x) and den(y) and num(x) and not num(y)]
        print(f'{name:36s} base {frac(ka, len(da)):34s} cand {frac(kb, len(db)):34s} +{len(up)} -{len(dn)} p={mcnemar(len(up), len(dn)):.3g}')
        for x, y in (up + dn)[:show]:
            print('     ', '+' if (x, y) in up else '-', y['id'], y['phrase'], '|', x.get('tr'), '->', y.get('tr'), '|', y.get('reason', '')[:70])


main()

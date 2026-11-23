"""Task 5J metrics: word cards inside matched expressions, every guard mode against the 5I engine (mode off), paired.

usage: python3 -I tools/nlp_research_5j/metrics_5j.py OUT_DIR/dev.jsonl [OUT_DIR/tune.jsonl ...] [--audit OUT_DIR/audit.jsonl]
       [--show MODE N]   (prints N changed rows of MODE: local use only, the sentences are BNC text)

Unit: one word card = one content word of the matched expression in one MAGPIE sentence (gold idiom / literal by
MAGPIE's annotators). The label says how the EXPRESSION is used, not whether the card's answer is the right sense:
  * gold idiom: the word's own meaning graded as right is treated as a false accept (the main safety metric);
    a share of these can still be right for partly literal idioms (read by hand on a sample, see the report).
  * gold literal: an accept is treated as a right accept; a veto there is a lost accept (an upper bound of the harm:
    some of those accepts were wrong senses anyway).
Cards: first (5I measure: the word's first main meaning, SenseEngine.fit), quiz (ReviewQuiz.answerFor with nothing
saved: graded or a flashcard), saved (the meaning the word panel saves with a new card, then graded or not).
Wilson 95 % intervals; McNemar exact two-sided test on paired cards (changes only go one way: a guard only vetoes).
"""
import json, math, sys

MODES = ['undecided', 'idiom', 'notLiteral', 'undecided+c', 'idiom+c', 'notLiteral+c']


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


def acc(r, mode, kind):
    x = r[mode]
    if kind == 'first':
        return x.get('first') == 'confirmed'
    if kind == 'quiz':
        return bool(x.get('quiz'))
    return bool(x.get('saved'))


def report(rows, title):
    rows = [r for r in rows if r.get('found')]
    print(f'\n## {title}: {len(rows)} word cards '
          f'({sum(r["gold"] == "idiom" for r in rows)} on idiomatic / {sum(r["gold"] == "literal" for r in rows)} on literal sentences, '
          f'{len({(r["set"], r["id"]) for r in rows})} sentences)')
    for kind in ('first', 'quiz', 'saved'):
        print(f'\n### card: {kind}')
        for gold in ('idiom', 'literal'):
            g = [r for r in rows if r['gold'] == gold]
            base = sum(acc(r, 'off', kind) for r in g)
            line = f'  {gold:7s} accepted, off: {frac(base, len(g))}'
            for m in MODES:
                k = sum(acc(r, m, kind) for r in g)
                lost = sum(acc(r, 'off', kind) and not acc(r, m, kind) for r in g)
                gain = sum(acc(r, m, kind) and not acc(r, 'off', kind) for r in g)
                line += f' | {m}: {k} (-{lost}/+{gain}, p={mcnemar(lost, gain):.2g})'
            print(line)
    print('\n### blocked (any card), by gold label and expression reading')
    for gold in ('idiom', 'literal'):
        g = [r for r in rows if r['gold'] == gold]
        print(f'  {gold:7s}: ' + ' | '.join(f'{m}: {frac(sum(r[m]["blocked"] is not None for r in g), len(g))}' for m in MODES))
    reading = {}
    for r in rows:
        e = r['expr']
        k = 'literal' if e['literal'] else 'cannot tell' if e['gap'] == 'idiomOrWords' else f'idiom {e["conf"]}' if e['shown'] and e['cat'] else f'not shown ({e["gap"]})'
        reading.setdefault(k, [0, 0])[0 if r['gold'] == 'idiom' else 1] += 1
    print('  expression reading (idiom rows / literal rows):', {k: tuple(v) for k, v in sorted(reading.items())})
    print('\n### manual load: cards that become flashcards (quiz graded off -> not graded)')
    n = len(rows)
    for m in MODES:
        lost = sum(acc(r, 'off', 'quiz') and not acc(r, m, 'quiz') for r in rows)
        base = sum(acc(r, 'off', 'quiz') for r in rows)
        print(f'  {m}: {lost} of {base} graded cards ({100 * lost / base if base else 0:.1f} %); graded share {base}/{n} -> {base - lost}/{n}')
    print('\n### panel saving a meaning with a new card (savedWouldBe = sure word meaning on the panel)')
    for gold in ('idiom', 'literal'):
        g = [r for r in rows if r['gold'] == gold]
        would = sum(r['off']['savedWouldBe'] is not None for r in g)
        print(f'  {gold:7s}: would save {frac(would, len(g))}; ' + ' | '.join(f'{m}: saved {sum(r[m]["savedTr"] is not None for r in g)}' for m in MODES))
    print('\n### panel (word tap) vs card, same sentence: panel says "cannot tell" / shows nothing, card graded anyway')
    for m in ['off'] + MODES:
        k = sum((not r[m]['tap']['shown']) and acc(r, m, 'quiz') for r in rows)
        k2 = sum(r[m]['tap']['gap'] == 'idiomOrWords' and acc(r, m, 'quiz') for r in rows)
        print(f'  {m}: graded while the panel shows no meaning {k}; while it says "cannot tell" {k2}')
    print('\n### other expressions on the same word (overlap)')
    ov = [r for r in rows if r['others']]
    print(f'  cards with another matched expression on the word: {len(ov)}')


def audit(rows):
    print(f'\n## Review audit (dictionary example sentences of the 1,500 most frequent words): {len(rows)} cards')
    base = [r for r in rows if r['off']['quiz']]
    print(f'  graded, off: {frac(len(base), len(rows))}')
    for m in MODES:
        lost = [r for r in base if not r[m]['quiz']]
        print(f'  {m}: graded {len(base) - len(lost)}; lost {frac(len(lost), len(base))}')
    for kind in ('first',):
        b = sum(r['off'].get('first') == 'confirmed' for r in rows)
        print(f'  first-meaning card confirmed, off: {b}; ' + ' | '.join(f'{m}: {sum(r[m].get("first") == "confirmed" for r in rows)}' for m in MODES))


def main():
    args = sys.argv[1:]
    show = None
    if '--show' in args:
        i = args.index('--show')
        show = (args[i + 1], int(args[i + 2]))
        del args[i:i + 3]
    aud = None
    if '--audit' in args:
        i = args.index('--audit')
        aud = args[i + 1]
        del args[i:i + 2]
    allrows = []
    for p in args:
        rows = [json.loads(l) for l in open(p, encoding='utf-8')]
        allrows += rows
        report(rows, p.rsplit('/', 1)[-1])
    if len(args) > 1:
        report(allrows, 'all sets together')
    if aud:
        arows = [json.loads(l) for l in open(aud, encoding='utf-8')]
        audit(arows)
        if show:
            m, n = show
            for r in [r for r in arows if r['off']['quiz'] and not r[m]['quiz']][:n]:
                print('AUDIT', r['word'], r[m]['blocked'], r['off']['quizTr'], '|', r['sentence'])
    if show:
        m, n = show
        for r in [r for r in allrows if r.get('found') and acc(r, 'off', 'quiz') and not acc(r, m, 'quiz')][:n]:
            print('ROW', r['gold'], r['phrase'], r['word'], r['off']['quizTr'], r['expr'], '|', r['sentence'])


main()

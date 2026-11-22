"""Read-only check of the source order (DictDb.sourcePolicy) against human translations.

usage: python3 tools/own_dict/measure_first_meaning.py assets/dict.db [N]

For the N most frequent words (default 3000) and for every expression that has both an
unreviewed AI draft and a sourced meaning, it asks: does the FIRST meaning shown appear in
the human Turkish translations of the entry's Tatoeba sentences (table exs)? It compares the
order before the policy (AI draft first) with the order after it (ft / expr first).

This is a rough, independent signal, not a measure of correctness: a meaning can be right and
still be missing from a translation, and the match is on the first five letters of each part.
The database is opened read-only; nothing is written.
"""
import json
import re
import sqlite3
import sys

db = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 3000


def parts(t):
    return [p.strip().lower() for p in re.split(r'[,;()]', t or '') if len(p.strip()) > 1]


def found(meaning, translations):
    stems = {p.split()[0][:5] for p in parts(meaning) if p.split()}
    return any(s in t.lower() for t in translations for s in stems)


def report(name, rows):
    n = before = after = 0
    for draft_first, source_first, key in rows:
        trs = [r[0] for r in db.execute('SELECT tr FROM exs WHERE key=?', (key,))]
        if len(trs) < 2:
            continue
        n += 1
        before += found(draft_first, trs)
        after += found(source_first, trs)
    if n:
        print(f'{name}: {n} entries with 2+ translated sentences; first meaning found in them: '
              f'before (AI draft first) {before} ({before / n:.1%}), after (source first) {after} ({after / n:.1%})')


words = []
for (w,) in db.execute("SELECT word FROM wfreq WHERE word NOT GLOB '* *' ORDER BY n DESC LIMIT ?", (limit,)):
    o = db.execute('SELECT senses, reviewed FROM own_word WHERE word=?', (w,)).fetchone()
    f = db.execute('SELECT tr FROM ft WHERE word=?', (w,)).fetchone()
    if o and f and o[1] == 0 and json.loads(o[0]) and json.loads(f[0]):
        words.append((json.loads(o[0])[0].get('tr', ''), json.loads(f[0])[0], f'w:{w}'))
report('words', words)

exprs = []
for p, c, s, tr in db.execute("SELECT o.phrase, o.cat, o.senses, e.tr FROM own_expr o JOIN expr e ON e.phrase=o.phrase AND e.cat=o.cat "
                              "WHERE o.reviewed=0 AND e.tr IS NOT NULL AND e.tr != ''"):
    senses = json.loads(s)
    if senses:
        exprs.append((senses[0].get('tr', ''), tr, f'{p}|{c}'))
report('expressions', exprs)

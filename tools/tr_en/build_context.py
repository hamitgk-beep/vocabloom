"""Adds context data to assets/tr_en.db, so the app can pick the meaning a
Turkish word has in the sentence it is read in.

"Program on yıl sürmüştür": sürmek is "to drive" in most sentences, but with
"yıl" (year) it is "to last". Tatoeba has hundreds of thousands of Turkish
sentences with their English translation. In each one, the English shows
which meaning a Turkish word has ("The war lasted ten years" → the "to last"
meaning of sürmek), and the other Turkish words of the sentence ("yıl",
"savaş") are counted for that meaning. The app adds up those counts for the
words around a tapped word.

  python3 tools/tr_en/build_context.py pairs.tsv assets/tr_en.db

pairs.tsv: id <TAB> turkish <TAB> english (tatoeba_pairs.py). Tables written:
  ctx(lemma, g, word, n)  how often [word] was in a sentence where [lemma] had
                          meaning [g] (meanings counted in order over all senses)
  ctxn(lemma, g, n)       how many sentences had [lemma] with meaning [g]
"""
import json
import math
import re
import sqlite3
import sys
from collections import Counter, defaultdict

pairs_path, db_path = sys.argv[1:3]
db = sqlite3.connect(db_path)


def low(s):
    return s.replace('I', 'ı').replace('İ', 'i').lower()


senses = {}
for w, js in db.execute('SELECT word, senses FROM lemma'):
    gl = [g for s in json.loads(js) for g in s['g']]
    if len(gl) > 1:
        senses[w] = gl
rank = {w: r for w, r in db.execute('SELECT word, rank FROM lemma')}
form = defaultdict(list)
for f, l in db.execute('SELECT form, lemma FROM form'):
    form[f].append(l)


def lemma_of(tok):
    if tok in rank:
        return tok
    c = form.get(tok)
    if not c:
        return None
    return min(c, key=lambda l: rank.get(l, 10 ** 9))


IRREGULAR = {
    'was': 'be', 'were': 'be', 'is': 'be', 'are': 'be', 'been': 'be', 'am': 'be', 'went': 'go', 'gone': 'go', 'took': 'take',
    'taken': 'take', 'came': 'come', 'saw': 'see', 'seen': 'see', 'gave': 'give', 'given': 'give', 'made': 'make', 'got': 'get',
    'gotten': 'get', 'knew': 'know', 'known': 'know', 'thought': 'think', 'told': 'tell', 'said': 'say', 'found': 'find',
    'left': 'leave', 'felt': 'feel', 'kept': 'keep', 'held': 'hold', 'brought': 'bring', 'bought': 'buy', 'began': 'begin',
    'begun': 'begin', 'ran': 'run', 'drove': 'drive', 'driven': 'drive', 'rode': 'ride', 'ridden': 'ride', 'wrote': 'write',
    'written': 'write', 'spoke': 'speak', 'spoken': 'speak', 'broke': 'break', 'broken': 'break', 'fell': 'fall', 'fallen': 'fall',
    'stood': 'stand', 'sat': 'sit', 'lay': 'lie', 'lain': 'lie', 'laid': 'lay', 'paid': 'pay', 'sent': 'send', 'spent': 'spend',
    'built': 'build', 'lost': 'lose', 'met': 'meet', 'led': 'lead', 'read': 'read', 'heard': 'hear', 'understood': 'understand',
    'wore': 'wear', 'worn': 'wear', 'won': 'win', 'threw': 'throw', 'thrown': 'throw', 'grew': 'grow', 'grown': 'grow',
    'drew': 'draw', 'drawn': 'draw', 'flew': 'fly', 'flown': 'fly', 'ate': 'eat', 'eaten': 'eat', 'drank': 'drink',
    'drunk': 'drink', 'sang': 'sing', 'sung': 'sing', 'swam': 'swim', 'chose': 'choose', 'chosen': 'choose', 'forgot': 'forget',
    'forgotten': 'forget', 'hid': 'hide', 'hidden': 'hide', 'bit': 'bite', 'bitten': 'bite', 'shook': 'shake', 'shaken': 'shake',
    'woke': 'wake', 'woken': 'wake', 'struck': 'strike', 'stuck': 'stick', 'hung': 'hang', 'caught': 'catch', 'taught': 'teach',
    'fought': 'fight', 'sought': 'seek', 'sold': 'sell', 'slept': 'sleep', 'swept': 'sweep', 'meant': 'mean', 'dealt': 'deal',
    'dug': 'dig', 'fed': 'feed', 'fled': 'flee', 'froze': 'freeze', 'frozen': 'freeze', 'lit': 'light', 'rose': 'rise',
    'risen': 'rise', 'shot': 'shoot', 'shut': 'shut', 'stole': 'steal', 'stolen': 'steal', 'tore': 'tear', 'torn': 'tear',
    'did': 'do', 'done': 'do', 'does': 'do', 'had': 'have', 'has': 'have', 'children': 'child', 'men': 'man', 'women': 'woman',
    'feet': 'foot', 'teeth': 'tooth', 'mice': 'mouse', 'people': 'person', 'better': 'good', 'best': 'good', 'worse': 'bad',
    'worst': 'bad', 'lives': 'life', 'knives': 'knife', 'wives': 'wife', 'leaves': 'leaf',
}


def stem(w):
    w = w.lower().strip("'")
    if w in IRREGULAR:
        w = IRREGULAR[w]
    else:
        w = _suffix(w)
    # "driv" / "drive", "stopp" / "stop": compare without a final e and doubled letters.
    w = w.rstrip('e')
    if len(w) > 3 and w[-1] == w[-2]:
        w = w[:-1]
    return w


def _suffix(w):
    for suf, rep in (('ies', 'y'), ('ied', 'y'), ('ying', 'y'), ('ing', ''), ('ed', ''), ('es', ''), ('s', ''), ('ly', '')):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            return w[: len(w) - len(suf)] + rep
    return w


STOP = set('''to a an the of in on at for with by from into onto up down out off over be being become one someone something
somebody anyone anything oneself someone's one's or and as not no that this which who whom whose it its make do have get go
take put give set very more most much many some any all other such than so too also just only usually especially
figuratively literally colloquial dated archaic slang informal formal transitive intransitive e.g i.e etc used way
thing kind sort'''.split())


def keywords(gloss):
    g = re.sub(r'\([^)]*\)', ' ', gloss)
    return {stem(w) for w in re.findall(r"[A-Za-z][A-Za-z'-]*", g) if w.lower() not in STOP and len(w) > 2}


gloss_kw = {w: [keywords(g) for g in gl] for w, gl in senses.items()}
# A keyword shared by several meanings tells less.
gloss_wt = {}
for w, kws in gloss_kw.items():
    df = Counter(k for ks in kws for k in ks)
    gloss_wt[w] = [{k: 1 / df[k] for k in ks} for ks in kws]

n_g = Counter()
n_gc = defaultdict(Counter)
seen = 0
for line in open(pairs_path, encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) < 3:
        continue
    tr, en = p[1], p[2]
    toks = re.findall(r"[a-zçğıöşüâîû]+", low(tr))
    lemmas = [lemma_of(t) for t in toks]
    lemmas = [l for l in lemmas if l]
    if len(lemmas) < 2:
        continue
    en_stems = {stem(w) for w in re.findall(r"[A-Za-z][A-Za-z'-]*", en)}
    seen += 1
    for L in set(lemmas):
        if L not in senses:
            continue
        best, best_s = None, 0.0
        for gi, wt in enumerate(gloss_wt[L]):
            s = sum(v for k, v in wt.items() if k in en_stems)
            if s > best_s + 1e-9:
                best, best_s = gi, s
        if best is None:
            continue
        n_g[(L, best)] += 1
        for c in set(lemmas):
            if c != L:
                n_gc[(L, best)][c] += 1

db.executescript('''
DROP TABLE IF EXISTS ctx; DROP TABLE IF EXISTS ctxn;
CREATE TABLE ctx(lemma TEXT, g INTEGER, word TEXT, n INTEGER);
CREATE TABLE ctxn(lemma TEXT, g INTEGER, n INTEGER);
''')
rows = 0
for (L, g), n in n_g.items():
    db.execute('INSERT INTO ctxn VALUES (?,?,?)', (L, g, n))
# Keep a context word only where it says something: seen at least twice, and
# for a word with several meanings, more often with this meaning than its share.
by_lemma = defaultdict(dict)
for (L, g), cs in n_gc.items():
    by_lemma[L][g] = cs
for L, gs in by_lemma.items():
    total = sum(n_g[(L, g)] for g in gs)
    if len(gs) < 2:
        continue  # only one meaning ever seen: nothing to choose
    for g, cs in gs.items():
        share = n_g[(L, g)] / total
        kept = []
        for c, n in cs.items():
            nc = sum(gs[h].get(c, 0) for h in gs)
            if n >= 2 and n / nc > share:
                kept.append((n * math.log(1 + n / nc / share), c, n))
        for _, c, n in sorted(kept, reverse=True)[:60]:
            db.execute('INSERT INTO ctx VALUES (?,?,?,?)', (L, g, c, n))
            rows += 1
db.execute('CREATE INDEX ctx_lemma ON ctx(lemma, word)')
db.execute('CREATE INDEX ctxn_lemma ON ctxn(lemma)')
db.execute("INSERT OR REPLACE INTO meta VALUES ('ctx', ?)", (f'{seen} Tatoeba sentences, {rows} context rows',))
db.commit()
db.execute('VACUUM')

print(f'# Context data\n\n{seen} sentences, {len(n_g)} (word, meaning) pairs, {rows} context rows\n')
for L in ['sürmek', 'çekmek', 'tutmak', 'geçmek', 'çıkmak', 'almak', 'yüz', 'kurmak', 'açmak', 'düşmek']:
    if L not in senses:
        continue
    print(f'## {L}')
    for g, gl in enumerate(senses[L][:8]):
        ctx = db.execute('SELECT word, n FROM ctx WHERE lemma=? AND g=? ORDER BY n DESC LIMIT 12', (L, g)).fetchall()
        print(f'- [{n_g[(L, g)]}] {gl[:70]}: ' + ', '.join(f'{w} {n}' for w, n in ctx))
    print()

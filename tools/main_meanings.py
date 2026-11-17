"""Main Turkish meanings of single English words, from two open dictionaries.

  * Wiktionary translations, as compiled in the Kindle English-Turkish
    dictionary by Murat Uysal (github.com/mybottles/kindle-en-tr-dictionary,
    content CC BY-SA 4.0 / GFDL from English Wiktionary via kaikki.org).
    These come first: they are grouped by sense in Wiktionary's order.
  * damdafayton/eng-tur-dictionary (github.com/damdafayton/eng-tur-dictionary,
    MIT according to its README): only a helper. It decides which Wiktionary
    sense is shown first when they disagree, and fills in words Wiktionary
    lacks.

The FreeDict and KeNet meanings are no longer shown: `ft` holds only these
two sources, and a WordNet sense keeps only the Turkish words these two
sources also give for the word (so the reader can still pick the meaning
that fits the sentence). WordNet itself stays for English definitions,
synonyms and finding a word's base form.

  python3 tools/main_meanings.py extract <english-turkish-dictionary.mobi> <english_turkish.sqlite> tools/data/main_meanings.jsonl.gz
  python3 tools/main_meanings.py apply assets/dict.db      # also run by build_dict.py

`apply` rewrites the `ft` table (word -> list of Turkish meanings), which the
app reads as a word's Turkish meanings everywhere (word panel, lists, quiz).
"""
import gzip
import html
import json
import os
import re
import sqlite3
import sys

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'main_meanings.jsonl.gz')
WORD_RE = re.compile(r"[a-z][a-z'-]*")


def extract(mobi_path, dam_path, out_path):
    import mobi  # pip install mobi
    import shutil
    tmp, book = mobi.extract(mobi_path)
    s = open(book, encoding='utf-8').read()
    shutil.rmtree(tmp, ignore_errors=True)
    wk = {}
    for m in re.finditer(r'<idx:orth value="([^"]+)".*?</idx:orth>(.*?)</idx:entry>', s, re.S):
        w = html.unescape(m.group(1)).lower().strip()
        # Wiktionary paragraphs start with a part of speech ("<i>n.</i>"); the
        # others are FreeDict, which the dictionary already has.
        for _, body in re.findall(r'<p><i>([a-z]+)\.</i>(.*?)</p>', m.group(2), re.S):
            for seg in re.split(r'<i>\[.*?\]</i>', body):
                t = re.sub(r'\s+', ' ', html.unescape(re.sub('<[^>]+>', '', seg))).strip(' ;')
                if t:
                    wk.setdefault(w, []).append(t)
    dm = {}
    c = sqlite3.connect(dam_path)
    for e, t in c.execute('SELECT e.english, t.turkce FROM English e JOIN Turkish t ON t.English_id = e.id'):
        w = (e or '').lower().strip()
        terms = [x.strip() for x in re.split(r'[,;]', t or '') if x.strip()]
        if WORD_RE.fullmatch(w) and terms:
            dm[w] = terms
    words = sorted(set(wk) | set(dm))
    with gzip.open(out_path, 'wt', encoding='utf-8') as f:
        for w in words:
            if not WORD_RE.fullmatch(w):
                continue
            j = {'w': w}
            if w in wk:
                j['wk'] = wk[w]
            if w in dm:
                j['dm'] = dm[w]
            f.write(json.dumps(j, ensure_ascii=False) + '\n')
    print('main meanings: wiktionary', len(wk), 'damdafayton', len(dm), 'words', len(words))


def _terms(item):
    return [x.strip() for x in re.split(r'[,;]', item) if x.strip()]


sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'qa'))
from audit_dict import FT_TAG, english_words  # noqa: E402  (same rules as the quality check)


def _clean(t, word):
    """One Turkish meaning, or None when it is not one: labels such as
    "(müzik)" or "(the ile)" are taken off; English fragments ("We sat on
    the bench"), cross references ("bkz. have") and slang marks are dropped."""
    t = re.sub(r'^(ilg|zf|s|i|f|zam|bağ|ünl|ç)\.\s*', '', t).strip()
    if re.match(r'^(arg|kaba|bkz|bakınız)\b', t, re.I) or '(bkz' in t:
        return None
    t = FT_TAG.sub('', t)
    t = re.sub(r'\((?:[a-z/ ]+|`[^)]*)\s+ile[^)]*\)', '', t)        # "(the ile)", "(for/to ile)"
    t = re.sub(r'\([^)]*\.\.\.[^)]*\)', '', t)                     # "(both ...and ...)"
    t = re.sub(r'\s+', ' ', t).strip(' ,;')
    if not t or t.lower() == word or len(t) > 60 or (t.isupper() and len(t) <= 6):
        return None
    if t.endswith('.') or english_words(t, extra={word} if len(word) > 3 else ()):
        return None
    return t


def merged(word, wk, dm):
    """Meaning lines for [word]: Wiktionary senses (the one damdafayton
    agrees with most first), then damdafayton's other words, each Turkish
    word shown once."""
    dmc = [t for t in (_clean(x, word) for x in dm) if t]
    rank = {t.lower(): i for i, t in reversed(list(enumerate(dmc[:8])))}
    groups = []
    for g in wk:
        ts = [t for t in (_clean(x, word) for x in _terms(g)) if t]
        if ts:
            groups.append(ts)

    def agreement(ix):
        hits = [rank[t.lower()] for t in groups[ix] if t.lower() in rank]
        return (min(hits) if hits else 99, ix)

    if groups and dmc:
        # Only the first line moves; the rest keep Wiktionary's order.
        first = min(range(len(groups)), key=agreement)
        if agreement(first)[0] < 3:
            groups.insert(0, groups.pop(first))
    out, seen = [], set()

    def push(ts):
        ts = [t for t in ts if t.lower() not in seen]
        for t in ts:
            seen.add(t.lower())
        if ts:
            out.append(', '.join(ts))

    for g in groups:
        push(g)
    rest = dmc
    while rest:
        push(rest[:4])
        rest = rest[4:]
    return out


def apply(db):
    if not os.path.exists(DATA):
        print('main meanings: not found, skipped')
        return
    old = {r[0] for r in db.execute('SELECT word FROM ft')}
    known = old | {r[0] for r in db.execute('SELECT DISTINCT lemma FROM sense')}
    forms = {r[0] for r in db.execute('SELECT form FROM exc')}

    def inflected(w):
        if w in forms:
            return True
        for suf, rep in [('ies', 'y'), ('es', ''), ('s', ''), ('ied', 'y'), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e'),
                         ('er', ''), ('est', '')]:
            if w.endswith(suf) and len(w) > len(suf) + 2 and (w[:-len(suf)] + rep) in known:
                return True
        return False

    ft = {}
    with gzip.open(DATA, 'rt', encoding='utf-8') as f:
        for line in f:
            j = json.loads(line)
            w = j['w']
            if w not in known and inflected(w):
                continue  # "went", "books": the reader finds them under go, book
            new = merged(w, j.get('wk', []), j.get('dm', []))
            if new:
                ft[w] = new
    db.execute('DELETE FROM ft')
    db.executemany('INSERT INTO ft(word, tr) VALUES (?, ?)', [(w, json.dumps(t, ensure_ascii=False)) for w, t in ft.items()])
    print('main meanings: words', len(ft), 'kept from before', len(old & set(ft)), 'new', len(set(ft) - old),
          'without a Turkish meaning now', len(old - set(ft)))

    # WordNet senses: keep only Turkish words the new sources also give.
    allowed = {w: {y for line in t for x in _terms(line) for y in [x.strip().lower(), *x.lower().split()] if len(y) > 2}
               for w, t in ft.items()}
    lemmas = {}
    for lemma, syn in db.execute('SELECT lemma, syn_id FROM sense'):
        lemmas.setdefault(syn, []).append(lemma)
    kept = dropped = 0
    rows = []
    for syn, tr in db.execute("SELECT id, tr FROM syn WHERE tr IS NOT NULL AND tr != '[]'").fetchall():
        ok = set()
        for l in lemmas.get(syn, []):
            ok |= allowed.get(l, set())
            if ' ' in l:
                # A compound ("golf course") is checked against its words'
                # meanings, and its English words count ("golf sahası").
                for part in l.split():
                    ok |= allowed.get(part, set()) | {part}
        terms = json.loads(tr)
        # A sense word is kept when it is one of the new meanings or is built
        # on one ("talihsiz kimse" for "talihsiz").
        keep = [t for t in terms if t.strip().lower() in ok or any(x in ok for x in t.lower().split() if len(x) > 2)]
        kept += len(keep)
        dropped += len(terms) - len(keep)
        rows.append((json.dumps(keep, ensure_ascii=False), syn))
    db.executemany('UPDATE syn SET tr = ? WHERE id = ?', rows)
    db.commit()
    print('wordnet sense meanings: kept', kept, 'dropped', dropped)


if __name__ == '__main__':
    if sys.argv[1] == 'extract':
        extract(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else DATA)
    elif sys.argv[1] == 'apply':
        con = sqlite3.connect(sys.argv[2])
        apply(con)
        con.execute('VACUUM')
        con.close()

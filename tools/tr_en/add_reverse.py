"""Adds Turkish words and English meanings to assets/tr_en.db from the
English -> Turkish data the app already has (assets/dict.db), turned around:

  * KeNet Turkish WordNet (CC BY-SA 4.0), linked to Princeton WordNet: each
    Turkish word of a WordNet meaning gets that meaning's English words and
    definition ("kitap" -> "book, volume (physical objects consisting of a
    number of pages bound together)").
  * The English -> Turkish word meanings (dict.db `ft`): each Turkish
    translation gets the English word it translates. Since 2026-11-17 `ft`
    holds Wiktionary (via the Kindle compilation) and damdafayton meanings,
    not FreeDict (tools/main_meanings.py), so these meanings carry the source
    of the `ft` row they came from. Their tag is "rv" (reversed). Databases
    built before 2026-11-22 tag them "fd", which never meant FreeDict
    content (docs/lexicon_remediation/LICENSE_TEXT_CORRECTIONS.md).

The `syn.tr` Turkish also holds 1,766 AI-filled terms (load_syn); the
candidate build (tools/lexicon_remediation/) leaves those out. Only words the
Wiktionary data does not have are added; their meanings are marked with
their source ("s": "wn" or "rv").

  python3 tools/tr_en/add_reverse.py assets/dict.db assets/tr_en.db
"""
import json
import re
import sqlite3
import sys
from collections import defaultdict

dict_path, db_path = sys.argv[1:3]
src = sqlite3.connect(dict_path)
db = sqlite3.connect(db_path)


def low(s):
    return s.replace('I', 'ı').replace('İ', 'i').lower()


POS = {'n': 'noun', 'v': 'verb', 'a': 'adj', 's': 'adj', 'r': 'adv'}
TR_WORD = re.compile(r"[a-zçğıöşüâîû]+(?: [a-zçğıöşüâîû]+)?")

existing = {}
rank = {}
for w, r, js in db.execute('SELECT word, rank, senses FROM lemma'):
    existing[w] = json.loads(js)
    rank[w] = r


forms = {f for (f,) in db.execute('SELECT form FROM form')}


def known_words(senses):
    out = set()
    for s in senses:
        for g in s['g']:
            out.update(x.lower() for x in re.findall(r"[A-Za-z][A-Za-z'-]*", g))
    return out


# KeNet: Turkish word -> pos -> [gloss]
wn = defaultdict(lambda: defaultdict(list))
for pos, gloss, words, tr in src.execute("SELECT pos, gloss, words, tr FROM syn WHERE tr IS NOT NULL AND tr != '[]'"):
    en = [w.replace('_', ' ') for w in json.loads(words or '[]')][:4]
    if not en:
        continue
    text = ', '.join(en) + (f' ({gloss})' if gloss else '')
    for t in json.loads(tr):
        t = t.strip()
        if not t or t[0].isupper():  # names and Latin taxon names
            continue
        t = low(t)
        if TR_WORD.fullmatch(t):
            wn[t][POS.get(pos, '')].append((en[0].lower(), text))

# Reversed ft: Turkish translation -> [English words]
fd = defaultdict(list)
for w, tr in src.execute('SELECT word, tr FROM ft'):
    if not re.fullmatch(r"[A-Za-z][A-Za-z' -]*", w) or len(w) < 2:
        continue
    # Only the first two translations: later ones are loose.
    pieces = [low(p.strip()) for s in json.loads(tr) for p in re.split(r'[,;]', s)][:2]
    for p in pieces:
        if p and TR_WORD.fullmatch(p) and w not in fd[p]:
            fd[p].append(w)

added_words = added_wn = added_fd = 0
next_rank = max(rank.values()) + 1
for t in sorted(set(wn) | set(fd)):
    # Words Wiktionary already has keep its meanings only: the reversed data
    # is looser, so it fills in words that were missing.
    if t in existing or t in forms:
        continue  # (an inflected form of a known word: "onu" is o)
    senses = []
    new = True
    known = known_words(senses)
    groups = []
    for pos, items in wn.get(t, {}).items():
        gl = []
        for head, text in items:
            if head in known or text in gl:
                continue
            gl.append(text)
            known.add(head)
        if gl:
            groups.append({'p': pos, 'g': gl[:8], 's': 'wn'})
            added_wn += len(gl[:8])
    words = [w for w in fd.get(t, []) if w.lower() not in known][:8]
    if words:
        groups.append({'p': '', 'g': ['; '.join(words)], 's': 'rv'})
        added_fd += len(words)
    if not groups:
        continue
    if new:
        db.execute('INSERT INTO lemma(word, rank, senses) VALUES (?,?,?)', (t, next_rank, json.dumps(groups, ensure_ascii=False)))
        next_rank += 1
        added_words += 1
    else:
        db.execute('UPDATE lemma SET senses=? WHERE word=?', (json.dumps(senses + groups, ensure_ascii=False), t))
db.execute("INSERT OR REPLACE INTO meta VALUES ('reverse', ?)", (f'{added_words} words, {added_wn} WordNet meanings, {added_fd} reversed English words (rv)',))
db.commit()
db.execute('VACUUM')
print(f'# Reverse data\n\nnew Turkish words: {added_words}\nWordNet (KeNet) meanings added: {added_wn}\nreversed English words added (rv): {added_fd}\n')
for w in ['kitap', 'okumak', 'göz', 'yüz', 'dekatlon', 'serbestçe', 'kabus']:
    r = db.execute('SELECT senses FROM lemma WHERE word=?', (w,)).fetchone()
    print(f'- {w}: ' + (r[0][:300] if r else '-'))

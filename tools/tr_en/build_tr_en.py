"""Builds assets/tr_en.db: Turkish words with English meanings, from open data only.

usage: python3 build_tr_en.py KAIKKI_TURKISH.jsonl FREQ_tr_full.txt PAIRS.tsv OUT.db

Sources (shown on the app's Privacy and licenses page):
  * Kaikki.org extract of the English Wiktionary, Turkish entries (CC BY-SA 4.0)
  * FrequencyWords, OpenSubtitles 2018 Turkish (CC BY-SA 4.0), only to rank words
  * Tatoeba Turkish-English sentence pairs (CC BY 2.0 FR), example sentences
PAIRS.tsv lines: tatoeba_id <TAB> turkish <TAB> english

Tables:
  lemma(word, rank, senses)  senses = JSON [{"p": pos, "g": [gloss, ...]}]
  form(form, lemma)          inflected form -> base word, only forms seen in the frequency list
  ex(lemma, tr, en, id)      up to 3 Tatoeba examples per word
  meta(key, value)
"""
import collections, json, os, re, sqlite3, sys

kaikki, freq_path, pairs_path, out = sys.argv[1:5]


def low(s):
    return s.replace('I', 'ı').replace('İ', 'i').lower().replace('̇', '')


SKIP_POS = {'character', 'symbol', 'punct', 'suffix', 'prefix', 'infix', 'affix', 'romanization'}
TAG_DROP = {'obsolete', 'archaic', 'rare'}

senses = collections.defaultdict(list)   # lemma -> [(pos, [gloss])]
form_of = collections.defaultdict(set)
for line in open(kaikki, encoding='utf-8'):
    e = json.loads(line)
    if e.get('lang_code') not in (None, 'tr'):
        continue
    w = low(e.get('word', '').strip())
    if not w:
        continue
    pos = e.get('pos', '')
    gl = []
    for s in e.get('senses', []):
        if s.get('form_of') or s.get('alt_of'):
            for f in (s.get('form_of') or []) + (s.get('alt_of') or []):
                if f.get('word'):
                    form_of[w].add(low(f['word']))
            continue
        if TAG_DROP & set(s.get('tags', [])) and gl:
            continue
        g = (s.get('glosses') or [''])[-1].strip()
        if g and g not in gl:
            gl.append(g)
    if gl and pos not in SKIP_POS:
        senses[w].append((pos, gl[:6]))
    for f in e.get('forms', []):
        t = low(f.get('form', '').strip())
        if t and ' ' not in t and t != w and not set(f.get('tags', [])) & {'romanization', 'table-tags', 'inflection-template'}:
            form_of[t].add(w)

rank = {}
for i, line in enumerate(open(freq_path, encoding='utf-8')):
    p = line.split()
    if p:
        rank.setdefault(low(p[0]), i + 1)

BIG = 10 ** 7


def lemma_rank(l):
    r = rank.get(l, BIG)
    # Given names rank last: "Zaman" the name is far rarer than "zaman" the word.
    if all(p == 'name' for p, _ in senses[l]):
        r += BIG
    return r


def resolve(t):
    c = [l for l in form_of.get(t, ()) if l in senses]
    if t in senses:
        c.append(t)
    return sorted(set(c), key=lambda l: (l != t, lemma_rank(l)))


db_path = out + '.tmp'
if os.path.exists(db_path):
    os.remove(db_path)
db = sqlite3.connect(db_path)
db.executescript('''
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE lemma(word TEXT PRIMARY KEY, rank INTEGER, senses TEXT);
CREATE TABLE form(form TEXT, lemma TEXT, PRIMARY KEY(form, lemma));
CREATE TABLE ex(lemma TEXT, tr TEXT, en TEXT, id INTEGER);
''')
for l, ss in senses.items():
    order = sorted(ss, key=lambda x: x[0] == 'name')
    db.execute('INSERT INTO lemma VALUES(?,?,?)', (l, rank.get(l, BIG), json.dumps([{'p': p, 'g': g} for p, g in order], ensure_ascii=False)))
nform = 0
for t, ls in form_of.items():
    if t not in rank or t in senses and len(ls) == 0:
        continue
    for l in ls:
        if l in senses and l != t:
            db.execute('INSERT OR IGNORE INTO form VALUES(?,?)', (t, l))
            nform += 1

examples = collections.defaultdict(list)
pairs = []
for line in open(pairs_path, encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) >= 3 and 8 <= len(p[1]) <= 80:
        pairs.append(p)
pairs.sort(key=lambda p: len(p[1]))
seen_tr = set()
for sid, tr, en in pairs:
    if tr in seen_tr:
        continue
    seen_tr.add(tr)
    for tok in set(re.findall(r"[a-zçğıöşüâîû]+", low(tr))):
        r = resolve(tok)
        if r and len(examples[r[0]]) < 3:
            examples[r[0]].append((tr, en, int(sid) if sid.isdigit() else None))
for l, xs in examples.items():
    for tr, en, sid in xs:
        db.execute('INSERT INTO ex VALUES(?,?,?,?)', (l, tr, en, sid))
db.execute('CREATE INDEX ex_lemma ON ex(lemma)')
meta = {
    'version': '1',
    'sources': 'Kaikki.org / English Wiktionary (CC BY-SA 4.0); FrequencyWords / OpenSubtitles 2018 (CC BY-SA 4.0); Tatoeba (CC BY 2.0 FR)',
    'lemmas': str(len(senses)), 'forms': str(nform), 'examples_lemmas': str(len(examples)),
}
db.executemany('INSERT INTO meta VALUES(?,?)', meta.items())
db.commit()
db.execute('VACUUM')
db.close()
os.replace(db_path, out)

# Coverage report on the frequency list
freq = sorted(rank, key=rank.get)
lines = ['| top N | covered |', '|---|---|']
for n in (1000, 5000, 10000, 20000, 50000):
    top = freq[:n]
    lines.append(f'| {n} | {sum(1 for t in top if resolve(t)) * 100 // n}% |')
miss = [t for t in freq[:3000] if not resolve(t)][:120]
print(json.dumps(meta, ensure_ascii=False, indent=1))
print('\n'.join(lines))
print('Not covered in the top 3,000:', ', '.join(miss))

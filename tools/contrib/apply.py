"""Adds the hand-made dictionary data (tools/contrib/storilex_contrib.json, made
by clean.py) to both dictionaries. Only what is new goes in: a meaning the
dictionary already has (one of its words matches) is left alone, an example
sentence that is already there is not added twice. Running it again changes
nothing.

  Turkish → English (tr_en.db)
    new meanings: a group {"p", "g", "s": "st"} at the end of the word's senses,
                  so the numbers of the existing meanings stay the same
    new words and Turkish phrases: a lemma row
    examples: ex rows (id NULL), shown before the Tatoeba ones
    meaning in context: the sentence's words count toward the meaning it has
                  there (ctx, ctxn), the same counts build_context.py makes

  English → Turkish (dict.db)
    new meanings: a sense at the end of own_word (a new row keeps the
                  dictionary's current meanings in keep_tr)
    examples and context sentences: under the sense they show ("more"), and
                  in exs for the word, shown before the Tatoeba ones
    phrases: own_expr for a known phrase, a new expr row for a new one; a
             phrase from a filter sheet goes in that filter ("cat"); in one of
             the new filters the same phrase can also be in another one, as
             "actually" already is

usage: python3 tools/contrib/apply.py tools/contrib/storilex_contrib.json assets/tr_en.db assets/dict.db
"""
import json
import re
import sqlite3
import sys
from collections import defaultdict

data = json.load(open(sys.argv[1], encoding='utf-8'))
tr_db = sqlite3.connect(sys.argv[2])
en_db = sqlite3.connect(sys.argv[3])
SRC = 'st'          # source label of the new Turkish → English groups
CTX_WEIGHT = 5      # one checked sentence counts as much as five Tatoeba ones
stats = defaultdict(int)
# Same tables as tools/own_dict/db/migrate.py, for a freshly built dict.db.
en_db.executescript('''
CREATE TABLE IF NOT EXISTS own_word(
  word TEXT PRIMARY KEY, senses TEXT NOT NULL, keep_tr TEXT NOT NULL DEFAULT '[]', status TEXT NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0,
  action TEXT, source TEXT, note TEXT);
CREATE TABLE IF NOT EXISTS own_expr(
  phrase TEXT NOT NULL, cat TEXT NOT NULL DEFAULT '', senses TEXT NOT NULL, status TEXT NOT NULL,
  reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT, note TEXT, PRIMARY KEY(phrase, cat));
CREATE VIEW IF NOT EXISTS od AS SELECT word, senses AS json FROM own_word;
''')


def low(s):
    return s.replace('I', 'ı').replace('İ', 'i').lower()


def parts(text):
    """The separate meanings in "to hit, to strike (a ball)": hit, strike."""
    text = re.sub(r'\([^)]*\)', ' ', low(text))
    out = []
    for p in re.split(r'[,;/]|\bor\b', text):
        p = re.sub(r'^\s*(to|a|an|the)\s+', '', p.strip()).strip(' .!?:')
        p = re.sub(r'\s+', ' ', p)
        if p:
            out.append(p)
    return out


def covered(new, existing_texts):
    """Whether one of the meanings in [new] is already in the dictionary's text."""
    hay = ' | '.join(' '.join(parts(t)) + ' | ' + low(t) for t in existing_texts)
    for p in parts(new):
        if re.search(r'(?<![\w])' + re.escape(p) + r'(?![\w])', hay):
            return True
    # "turn out to be" is "turn out (to be)": a longer form of a meaning that is there.
    old = {q for t in existing_texts for q in parts(t) if ' ' in q}
    if any(re.search(r'(?<![\w])' + re.escape(q) + r'(?![\w])', p) for p in parts(new) for q in old):
        return True
    # The same words with another ending: "rezervasyon yapmak" is "rezervasyon yaptırmak".
    def key(p):
        toks = p.split()
        n = 5 if len(toks) == 1 else 3
        return tuple(t[:n] for t in toks)
    have = {key(q) for t in existing_texts for q in parts(t)}
    return any(key(p) in have for p in parts(new) if len(p) >= 5)


# ---------------------------------------------------------------- Turkish → English

def tr_senses(word):
    r = tr_db.execute('SELECT senses FROM lemma WHERE word=?', (word,)).fetchone()
    return None if r is None else json.loads(r[0])


def tr_flat(groups):
    return [g for grp in groups for g in grp['g']]


def tr_save(word, groups, new_word=False):
    js = json.dumps(groups, ensure_ascii=False)
    if new_word:
        tr_db.execute('INSERT INTO lemma(word, rank, senses) VALUES (?,?,?)', (word, 10 ** 7, js))
        if ' ' not in word:
            tr_db.execute('INSERT OR IGNORE INTO form(form, lemma) VALUES (?,?)', (word, word))
            tr_borrow_forms(word)
    else:
        tr_db.execute('UPDATE lemma SET senses=? WHERE word=?', (js, word))


def tr_borrow_forms(word):
    """A new verb takes the endings of a known verb that ends the same way
    (bitirmek: getirmek's getirdim → bitirdim), so its inflected forms find it."""
    if not word.endswith(('mak', 'mek')):
        return
    stem = word[:-3]
    for k in range(min(len(stem), 4), 1, -1):
        cands = tr_db.execute('SELECT word FROM lemma WHERE word LIKE ? AND word != ? ORDER BY rank LIMIT 5',
                              ('%' + word[-3 - k:], word)).fetchall()
        for (model,) in cands:
            mstem = model[:-3]
            forms = [f for (f,) in tr_db.execute('SELECT form FROM form WHERE lemma=?', (model,)) if f.startswith(mstem)]
            if len(forms) >= 20:
                tr_db.executemany('INSERT OR IGNORE INTO form(form, lemma) VALUES (?,?)',
                                  [(stem + f[len(mstem):], word) for f in forms])
                stats['tr forms borrowed'] += len(forms)
                return


def tr_add_meaning(word, pos, meaning):
    """Index (in the flat list of meanings) of [meaning] for [word], added when new."""
    groups = tr_senses(word)
    new_word = groups is None
    groups = groups or []
    flat = tr_flat(groups)
    for i, g in enumerate(flat):
        if covered(meaning, [g]):
            return i
    grp = next((g for g in groups if g.get('s') == SRC and g['p'] == pos), None)
    if grp is None or groups[-1] is not grp:
        grp = {'p': pos, 'g': [], 's': SRC}
        groups.append(grp)
    grp['g'].append(meaning)
    tr_save(word, groups, new_word)
    stats['tr meanings added' if not new_word else 'tr words added'] += 1
    return len(flat)


tr_rank = {w: r for w, r in tr_db.execute('SELECT word, rank FROM lemma')}
tr_form = defaultdict(list)
for f, l in tr_db.execute('SELECT form, lemma FROM form'):
    tr_form[f].append(l)


def tr_lemma_of(tok):
    if tok in tr_rank:
        return tok
    c = tr_form.get(tok)
    return min(c, key=lambda l: tr_rank.get(l, 10 ** 9)) if c else None


tr_new_ex = defaultdict(list)


def tr_example(word, tr, en):
    if not tr or not en:
        return
    have = {t for (t,) in tr_db.execute('SELECT tr FROM ex WHERE lemma=?', (word,))}
    if tr in have or tr in [t for t, _ in tr_new_ex[word]]:
        return
    tr_new_ex[word].append((tr, en))


def tr_context(word, g, sentence):
    toks = re.findall(r"[a-zçğıöşüâîû]+", low(sentence))
    ctx = {l for l in (tr_lemma_of(t) for t in toks) if l and l != word}
    if not ctx:
        return
    key = f'ctx:{word}:{g}:{sentence}'
    if tr_db.execute("SELECT 1 FROM meta WHERE key=?", (key,)).fetchone():
        return  # this sentence already counted
    tr_db.execute('INSERT INTO meta(key, value) VALUES (?, ?)', (key, 'contrib'))
    n = tr_db.execute('SELECT n FROM ctxn WHERE lemma=? AND g=?', (word, g)).fetchone()
    if n:
        tr_db.execute('UPDATE ctxn SET n=n+? WHERE lemma=? AND g=?', (CTX_WEIGHT, word, g))
    else:
        tr_db.execute('INSERT INTO ctxn VALUES (?,?,?)', (word, g, CTX_WEIGHT))
    for c in ctx:
        r = tr_db.execute('SELECT n FROM ctx WHERE lemma=? AND g=? AND word=?', (word, g, c)).fetchone()
        if r:
            tr_db.execute('UPDATE ctx SET n=n+? WHERE lemma=? AND g=? AND word=?', (CTX_WEIGHT, word, g, c))
        else:
            tr_db.execute('INSERT INTO ctx VALUES (?,?,?,?)', (word, g, c, CTX_WEIGHT))
    stats['tr context sentences'] += 1


# ---------------------------------------------------------------- English → Turkish

TR_POS = {'noun': 'isim', 'verb': 'fiil', 'adj': 'sıfat', 'adv': 'zarf', 'pron': 'zamir', 'postp': 'edat',
          'conj': 'bağlaç', 'intj': 'ünlem', 'num': 'sayı', 'phrase': 'deyim'}


def en_row(word):
    r = en_db.execute('SELECT senses, keep_tr FROM own_word WHERE word=?', (word,)).fetchone()
    if r:
        return json.loads(r[0]), json.loads(r[1]), True
    ft = en_db.execute('SELECT tr FROM ft WHERE word=?', (word,)).fetchone()
    return [], (json.loads(ft[0]) if ft else []), False


def en_save(word, senses, keep, exists):
    js = json.dumps(senses, ensure_ascii=False)
    if exists:
        en_db.execute('UPDATE own_word SET senses=? WHERE word=?', (js, word))
    else:
        en_db.execute('INSERT INTO own_word(word, senses, keep_tr, status, reviewed, action, source, note) '
                      'VALUES (?,?,?,?,?,?,?,?)',
                      (word, js, json.dumps(keep, ensure_ascii=False), 'contrib', 1, None, 'storilex_contrib', None))


def en_find(senses, keep, meaning):
    for i, s in enumerate(senses):
        if covered(meaning, [s.get('tr', '')]):
            return i
    return -1 if covered(meaning, keep) else None


def en_add_meaning(word, pos, meaning, note='', ex='', ex_tr=''):
    """Index of [meaning] in the word's own senses (-1: only in keep_tr), added when new."""
    senses, keep, exists = en_row(word)
    i = en_find(senses, keep, meaning)
    if i is not None:
        return i
    s = {'pos': TR_POS.get(pos, pos), 'tr': meaning, 'note': note, 'en': ex, 'ex_tr': ex_tr, 'src': 'storilex'}
    senses.append(s)
    en_save(word, senses, keep, exists)
    stats['en meanings added'] += 1
    return len(senses) - 1


def en_example(word, meaning, en, tr):
    """The example goes under the sense it shows, and to the word's examples."""
    if not en or not tr:
        return
    senses, keep, exists = en_row(word)
    i = en_find(senses, keep, meaning) if meaning else None
    if i is None and meaning:
        pos = next((w['pos'] for w in data['words'] if w['word'] == word and w['meaning'] == meaning), '')
        if not pos and any(x.strip().split(' (')[0].endswith(('mak', 'mek')) for x in meaning.split(',')):
            pos = 'verb'
        i = en_add_meaning(word, pos, meaning, ex=en, ex_tr=tr)
        senses, keep, exists = en_row(word)
    if i is not None and i >= 0:
        s = senses[i]
        if s.get('en') != en and s.get('ex') != en and en not in [m['en'] for m in s.get('more', [])]:
            s.setdefault('more', []).append({'en': en, 'tr': tr})
            en_save(word, senses, keep, exists)
    en_new_exs[f'w:{word}'].append((en, tr))


en_new_exs = defaultdict(list)
# Filters that only the contributors' sheets fill: a phrase can be there and in another filter.
OWN_FILTERS = {'dependent_prepositions', 'similes', 'polite_phrases', 'informal_slang', 'confusables', 'uk_us'}


def en_phrase(p):
    phrase, meaning, ex, ex_tr = p['phrase'].strip(), p['meaning'].strip(), p.get('ex', ''), p.get('ex_tr', '')
    want = p.get('cat')
    if not meaning:
        # An example for a phrase the dictionary has: its meaning stays as it is.
        meaning = None
    if want and want not in OWN_FILTERS and en_db.execute('SELECT 1 FROM expr WHERE phrase=?', (phrase,)).fetchone():
        # A filter the dictionary already fills: the phrase stays where it is.
        want = None
    rows = en_db.execute('SELECT id, cat, tr, entr, ex, extr FROM expr WHERE phrase=?' + (' AND cat=?' if want else ''),
                         (phrase, want) if want else (phrase,)).fetchall()
    if not rows and meaning is None:
        stats['en phrase examples skipped (no such phrase)'] += 1
        return
    if not rows:
        words = phrase.split()
        cat = want or ('phrasal_verbs' if len(words) == 2 and words[1] in {'up', 'down', 'over', 'out', 'off', 'on', 'in', 'away', 'back'} else 'idioms')
        nid = en_db.execute('SELECT max(id) FROM expr').fetchone()[0] + 1
        en_db.execute('INSERT INTO expr(id, phrase, cat, tr, en, forms, ex, entr, extr) VALUES (?,?,?,?,?,?,?,?,?)',
                      (nid, phrase, cat, meaning, None, None, ex or None, None, ex_tr or None))
        stats['en phrases added'] += 1
        if ex and ex_tr:
            en_new_exs[f'{phrase}|{cat}'].append((ex, ex_tr))
        return
    _, cat, tr, entr, ex0, extr0 = rows[0]
    own = en_db.execute('SELECT senses FROM own_expr WHERE phrase=? AND cat=?', (phrase, cat)).fetchone()
    senses = json.loads(own[0]) if own else []
    texts = [s.get('tr', '') for s in senses] + [tr or '']
    exd = en_db.execute('SELECT json FROM exd WHERE phrase=? AND cat=?', (phrase, cat)).fetchone()
    if exd and not own and meaning is not None:
        # The phrase has its own explained senses ("make up": oluşturmak,
        # uydurmak, barışmak …); an own_expr row would take their place.
        texts += [x.get('title_tr', '') for x in json.loads(exd[0])]
        if not covered(meaning, texts):
            stats['en phrase meanings skipped (explained senses)'] += 1
        meaning = None
    if meaning is not None and not covered(meaning, texts):
        if not senses and tr:
            # own_expr takes the place of expr's meaning: keep that one first.
            senses.append({'pos': 'deyim', 'tr': tr, 'note': '', 'en': '', 'ex': ex0 or '', 'ex_tr': extr0 or ''})
        if cat == 'phrasal_verbs' or not senses:
            # A phrasal verb can mean something else entirely (run over: ezmek, taşmak).
            senses.append({'pos': 'deyim', 'tr': meaning, 'note': '', 'en': '', 'ex': ex, 'ex_tr': ex_tr, 'src': 'storilex'})
        else:
            # An idiom has one meaning: the new wording joins it ("aynı fikirde olmak, hemfikir olmak").
            first = senses[0]
            have = parts(first.get('tr', ''))
            extra = [p.strip() for p in re.split(r'[,;]', meaning) if p.strip() and ' '.join(parts(p)) not in have]
            first['tr'] = ', '.join([first.get('tr', '').strip()] + extra).strip(', ')
            first['src'] = 'storilex'
        js = json.dumps(senses, ensure_ascii=False)
        if own:
            en_db.execute('UPDATE own_expr SET senses=? WHERE phrase=? AND cat=?', (js, phrase, cat))
        else:
            en_db.execute('INSERT INTO own_expr(phrase, cat, senses, status, reviewed, action, source, note) VALUES (?,?,?,?,?,?,?,?)',
                          (phrase, cat, js, 'contrib', 1, None, 'storilex_contrib', None))
        stats['en phrase meanings added'] += 1
    if ex and ex_tr:
        en_new_exs[f'{phrase}|{cat}'].append((ex, ex_tr))


# ---------------------------------------------------------------- apply

for w in data['words']:
    if w['lang'] == 'tr':
        tr_add_meaning(w['word'], w['pos'], w['meaning'])
    else:
        en_add_meaning(w['word'], w['pos'], w['meaning'], w.get('note', ''))

for e in data['examples']:
    if e['lang'] == 'tr':
        tr_add_meaning(e['word'], e.get('pos') or ('verb' if e['word'].endswith(('mak', 'mek')) else 'adj'), e['meaning'])
        tr_example(e['word'], e['tr'], e['en'])
    else:
        en_example(e['word'], e['meaning'], e['en'], e['tr'])

for c in data['context']:
    if c['lang'] == 'tr':
        pos = 'verb' if c['lemma'].endswith(('mak', 'mek')) else ''
        g = tr_add_meaning(c['lemma'], pos, c['meaning'])
        tr_context(c['lemma'], g, c['sentence'])
        tr_example(c['lemma'], c['sentence'], c['translation'])
    elif ' ' not in c['lemma']:
        en_example(c['lemma'], c['meaning'], c['sentence'], c['translation'])

for p in data.get('phrase_edits', []):
    # Checked by hand: a wrong meaning replaced, or a phrase that is not one removed.
    phrase = p['phrase']
    if p['action'] == 'rename':
        # "get the best" → "get the best of": the heading in its usual form.
        to = p['to']
        cats = [c for c, in en_db.execute('SELECT cat FROM expr WHERE phrase=?', (phrase,))]
        for t in ('expr', 'own_expr', 'exd', 'exfreq'):
            en_db.execute(f'UPDATE {t} SET phrase=? WHERE phrase=?', (to, phrase))
        for c in cats:
            en_db.execute('UPDATE exs SET key=? WHERE key=?', (f'{to}|{c}', f'{phrase}|{c}'))
        stats['en phrases renamed'] += len(cats)
    elif p['action'] == 'delete':
        cats = [c for c, in en_db.execute('SELECT cat FROM expr WHERE phrase=?', (phrase,))]
        en_db.execute('DELETE FROM expr WHERE phrase=?', (phrase,))
        for t in ('own_expr', 'exd', 'exfreq'):
            en_db.execute(f'DELETE FROM {t} WHERE phrase=?', (phrase,))
        en_db.executemany('DELETE FROM exs WHERE key=?', [(f'{phrase}|{c}',) for c in cats])
        stats['en phrases removed'] += len(cats)
    else:
        for cat, ex, extr in en_db.execute('SELECT cat, ex, extr FROM expr WHERE phrase=?', (phrase,)).fetchall():
            en_db.execute('UPDATE expr SET tr=? WHERE phrase=? AND cat=?', (p['meaning'], phrase, cat))
            own = en_db.execute('SELECT senses FROM own_expr WHERE phrase=? AND cat=?', (phrase, cat)).fetchone()
            senses = json.loads(own[0]) if own else [{'pos': 'deyim', 'tr': '', 'note': '', 'en': '', 'ex': ex or '', 'ex_tr': extr or ''}]
            senses = [dict(senses[0], tr=p['meaning'], src='storilex')]
            en_db.execute('INSERT OR REPLACE INTO own_expr(phrase, cat, senses, status, reviewed, action, source, note) VALUES (?,?,?,?,?,?,?,?)',
                          (phrase, cat, json.dumps(senses, ensure_ascii=False), 'contrib', 1, None, 'storilex_contrib', None))
            stats['en phrase meanings replaced'] += 1

for p in data['phrases']:
    if p['lang'] == 'tr':
        tr_add_meaning(p['phrase'], 'verb' if p.get('cat') == 'tr_compound_verbs' else 'phrase', p['meaning'])
        tr_example(p['phrase'], p.get('ex', ''), p.get('ex_tr', ''))
    else:
        en_phrase(p)

# Hand-checked examples first, then the rest as they were.
for word, new in tr_new_ex.items():
    old = tr_db.execute('SELECT tr, en, id FROM ex WHERE lemma=? ORDER BY rowid', (word,)).fetchall()
    tr_db.execute('DELETE FROM ex WHERE lemma=?', (word,))
    for t, e in new:
        tr_db.execute('INSERT INTO ex(lemma, tr, en, id) VALUES (?,?,?,NULL)', (word, t, e))
    tr_db.executemany('INSERT INTO ex(lemma, tr, en, id) VALUES (?,?,?,?)', [(word, *r) for r in old])
    stats['tr examples added'] += len(new)
for key, new in en_new_exs.items():
    old = en_db.execute('SELECT en, tr FROM exs WHERE key=? ORDER BY rowid', (key,)).fetchall()
    have = {e for e, _ in old}
    new = [x for i, x in enumerate(new) if x[0] not in have and x[0] not in [y[0] for y in new[:i]]]
    if not new:
        continue
    en_db.execute('DELETE FROM exs WHERE key=?', (key,))
    en_db.executemany('INSERT INTO exs(key, en, tr) VALUES (?,?,?)', [(key, *x) for x in new + old])
    stats['en examples added'] += len(new)

src = data['source']
tr_db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('contrib', ?)", (src,))
en_db.execute("INSERT OR REPLACE INTO meta(key, value) VALUES ('contrib', ?)", (src,))
tr_db.commit()
en_db.commit()
if stats:
    tr_db.execute('VACUUM')
    en_db.execute('VACUUM')
for k in sorted(stats):
    print(f'{k}: {stats[k]}')

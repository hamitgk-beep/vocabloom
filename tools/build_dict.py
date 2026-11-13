#!/usr/bin/env python3
"""Build assets/dict.db from open dictionary sources.

Sources (see ASSETS_LICENSES.md):
  - FreeDict eng-tur TEI (GPL-2.0+)
  - Princeton WordNet 3.0 (WordNet license)
  - KeNet Turkish WordNet (CC BY-SA 4.0) linked through CILI (CC BY 4.0)
  - tools/categories.py (hand curated)

Usage: python3 tools/build_dict.py <raw_dir> <out_db>
"""
import gzip
import json
import os
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(__file__))
from categories import CATEGORIES  # noqa: E402

RAW = sys.argv[1]
OUT = sys.argv[2]
TEI_NS = '{http://www.tei-c.org/ns/1.0}'
POS_MAP = {'n': 'n', 'v': 'v', 'a': 'a', 's': 'a', 'r': 'r'}
PARTICLES = {'up', 'down', 'out', 'off', 'in', 'on', 'over', 'away', 'back',
             'through', 'around', 'about', 'along', 'across', 'by', 'forward',
             'ahead', 'apart', 'aside', 'together', 'into', 'with', 'for', 'after'}
PREPS = {'at', 'by', 'in', 'on', 'out', 'under', 'within', 'without', 'beyond',
         'for', 'from', 'up', 'with', 'of', 'to', 'into', 'over', 'behind'}


def clean_tr(s):
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def load_freedict(db):
    path = os.path.join(RAW, 'eng-tur.tei')
    data = {}
    for _, el in ET.iterparse(path, events=('end',)):
        if el.tag != TEI_NS + 'entry':
            continue
        orth = el.find(f'{TEI_NS}form/{TEI_NS}orth')
        if orth is None or not orth.text:
            el.clear()
            continue
        word = orth.text.strip().lower()
        senses = []
        for sense in el.findall(f'{TEI_NS}sense'):
            quotes = [q.text.strip() for q in sense.iter(TEI_NS + 'quote') if q.text]
            if quotes:
                senses.append(clean_tr(', '.join(quotes)))
        if senses:
            # abbreviation senses such as "(kıs.) foreign" go last
            senses.sort(key=lambda x: x.startswith('(kıs.)'))
            data.setdefault(word, []).extend(senses)
        el.clear()
    db.executemany('INSERT INTO ft(word, tr) VALUES (?, ?)',
                   [(w, json.dumps(s, ensure_ascii=False)) for w, s in data.items()])
    print('freedict', len(data))
    return data


def load_kenet():
    """Return pwn30 key 'offset-pos' -> list of Turkish words."""
    ili2pwn = {}
    with open(os.path.join(RAW, 'ili-map-pwn30.tab'), encoding='utf-8') as f:
        for line in f:
            p = line.strip().split('\t')
            if len(p) == 2:
                off, pos = p[1].rsplit('-', 1)
                ili2pwn[p[0]] = f'{off}-{"a" if pos == "s" else pos}'
    entries = {}
    result = {}
    for _, el in ET.iterparse(os.path.join(RAW, 'kenet.xml'), events=('end',)):
        if el.tag == 'LexicalEntry':
            lemma = el.find('Lemma')
            if lemma is not None:
                entries[el.get('id')] = lemma.get('writtenForm')
            el.clear()
        elif el.tag == 'Synset':
            ili = el.get('ili')
            if ili and ili in ili2pwn:
                words = [entries[m] for m in (el.get('members') or '').split() if m in entries]
                words = [w for w in words if w and not w.startswith('(')]
                if words:
                    result.setdefault(ili2pwn[ili], []).extend(words)
            el.clear()
    print('kenet linked synsets', len(result))
    return result


def parse_gloss(g):
    parts = [p.strip() for p in g.split(';')]
    defs, ex = [], []
    for p in parts:
        if p.startswith('"'):
            ex.append(p.strip('"').strip())
        elif p:
            defs.append(p)
    return '; '.join(defs), ex


def load_wordnet(db, kenet):
    wn = os.path.join(RAW, 'wordnet')
    syn_id = 0
    key2id = {}
    rows = []
    multi = []  # (phrase, pos, synid)
    for pos_name in ('noun', 'verb', 'adj', 'adv'):
        with open(os.path.join(wn, f'data.{pos_name}'), encoding='utf-8') as f:
            for line in f:
                if line.startswith(' '):
                    continue
                head, _, gloss = line.partition('|')
                t = head.split()
                off, ss_type = t[0], t[2]
                wcnt = int(t[3], 16)
                words = [re.sub(r'\(.*\)$', '', t[4 + 2 * i]).replace('_', ' ') for i in range(wcnt)]
                d, ex = parse_gloss(gloss.strip())
                pos = POS_MAP[ss_type]
                syn_id += 1
                key2id[f'{off}-{pos}'] = syn_id
                tr = list(dict.fromkeys(kenet.get(f'{off}-{pos}', [])))
                rows.append((syn_id, pos, d, json.dumps(ex, ensure_ascii=False),
                             json.dumps(words, ensure_ascii=False),
                             json.dumps(tr, ensure_ascii=False) if tr else None))
    db.executemany('INSERT INTO syn VALUES (?,?,?,?,?,?)', rows)
    senses = []
    for pos_name, pos in (('noun', 'n'), ('verb', 'v'), ('adj', 'a'), ('adv', 'r')):
        with open(os.path.join(wn, f'index.{pos_name}'), encoding='utf-8') as f:
            for line in f:
                if line.startswith(' '):
                    continue
                t = line.split()
                lemma = t[0].replace('_', ' ')
                cnt = int(t[2])
                offs = t[-cnt:]
                for rank, off in enumerate(offs):
                    sid = key2id.get(f'{off}-{pos}')
                    if sid:
                        senses.append((lemma, pos, rank, sid))
                if ' ' in lemma and rank >= 0:
                    multi.append((lemma, pos, key2id.get(f'{offs[0]}-{pos}')))
    db.executemany('INSERT INTO sense VALUES (?,?,?,?)', senses)
    exc = []
    for pos_name, pos in (('noun', 'n'), ('verb', 'v'), ('adj', 'a'), ('adv', 'r')):
        with open(os.path.join(wn, f'{pos_name}.exc'), encoding='utf-8') as f:
            for line in f:
                t = line.split()
                if len(t) >= 2:
                    exc.append((t[0].replace('_', ' '), t[1].replace('_', ' '), pos))
    db.executemany('INSERT INTO exc VALUES (?,?,?)', exc)
    print('wordnet synsets', syn_id, 'senses', len(senses), 'exc', len(exc))
    return multi


def norm_phrase(p):
    return re.sub(r'\s+', ' ', p.strip().lower().replace('’', "'"))


# Very common words: a Wiktionary entry made only of these ("go to", "you think",
# "like that") would colour ordinary text, so such entries are left out.
COMMON = set('''
a an the and or but if so as than that this these those there here what which who whom whose when where why how
i me my you your he him his she her it its we us our they them their one one's oneself someone something somebody
be am is are was were been being have has had do does did go goes went gone get got say said know knew known think
thought like see saw come came take took make made want look give use find tell ask work seem feel try leave call
can could will would shall should may might must not no yes all some any every each other more most much many
to of in on at by for with from up down out off over about into back just now then too very well way time thing
let put keep mean
'''.split())
WIKT_PV_PARTICLES = {'up', 'down', 'out', 'off', 'in', 'on', 'over', 'away', 'back', 'through', 'around',
                     'about', 'along', 'across', 'by', 'forward', 'ahead', 'apart', 'aside', 'together'}
WIKT_SKIP = {'a', 'an', 'the', 'and', 'or', 'but'}  # too common to colour as their own entry
WIKT_SKIP_RE = re.compile(r"\b(fuck|shit|cunt|dick|cock|piss|ass|arse|bitch|bastard|wank|tits?)\b")


def load_wiktionary(exprs):
    """Adds Wiktionary expressions (tools/wiktionary_extract.py output) to [exprs].

    Fills missing English definitions / Turkish meanings of existing entries and
    adds new entries that no other source has. Returns {(phrase, cat): example}.
    """
    path = os.path.join(RAW, 'wiktionary_phrases.json.gz')
    examples = {}
    if not os.path.exists(path):
        print('wiktionary: not found, skipped')
        return examples
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        items = json.load(f)
    by_phrase = {}
    for (p, cat) in exprs:
        by_phrase.setdefault(p, set()).add(cat)
    added = {}
    for it in items:
        p, cat = norm_phrase(it['p']), it['c']
        toks = p.split()
        if p in WIKT_SKIP or WIKT_SKIP_RE.search(p) or len(toks) > 7:
            continue
        if (p, cat) not in exprs:
            if len(toks) == 1:
                continue  # single words (mostly conjunctions) come from the curated lists
            if all(t in COMMON for t in toks):
                continue
            if cat == 'phrasal_verbs' and (len(toks) != 2 or toks[1] not in WIKT_PV_PARTICLES
                                           or toks[0] in ('be', 'have', 'do')):
                continue
        en = '; '.join(it['en'][:3]) or None
        tr = ', '.join(it['tr'][:4]) or None
        if (p, cat) in exprs:
            e = exprs[(p, cat)]
            if e[0] is None and tr:
                e[0] = tr
            if e[1] is None and en:
                e[1] = en
        elif p in by_phrase:
            continue  # already listed under another category
        else:
            exprs[(p, cat)] = [tr, en, None]
            by_phrase.setdefault(p, set()).add(cat)
            added[cat] = added.get(cat, 0) + 1
        if it.get('ex'):
            examples[(p, cat)] = it['ex']
    print('wiktionary-added expressions', added)
    return examples


def load_exd(db, exprs):
    """The built-in Turkish library made by tools/pretranslate.py (release data-exd)."""
    path = os.path.join(RAW, 'exd.jsonl.gz')
    if not os.path.exists(path):
        print('exd: not found, skipped')
        return
    db.execute('CREATE TABLE exd(phrase TEXT, cat TEXT, json TEXT, PRIMARY KEY(phrase, cat))')
    n = filled = 0
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        for line in f:
            try:
                j = json.loads(line)
            except ValueError:
                continue
            key = (j['p'], j['c'])
            if key not in exprs or not j.get('s'):
                continue
            db.execute('INSERT OR REPLACE INTO exd VALUES (?,?,?)', (j['p'], j['c'], json.dumps(j['s'], ensure_ascii=False)))
            n += 1
            if not exprs[key][0] and j.get('tr'):
                exprs[key][0] = j['tr']
                filled += 1
    print('exd senses', n, 'turkish meanings filled', filled)


TOKEN_RE = re.compile(r"[a-z]+(?:'[a-z]+)?")


def load_tatoeba(db, exprs):
    """Translated example sentences (Tatoeba, CC BY 2.0 FR) for expressions and words."""
    path = os.path.join(RAW, 'tatoeba_en_tr.tsv.gz')
    if not os.path.exists(path):
        print('tatoeba: not found, skipped')
        return
    pairs = []
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        for line in f:
            en, _, tr = line.rstrip('\n').partition('\t')
            if en and tr and len(en) <= 140:
                pairs.append((en, tr))
    pairs.sort(key=lambda x: len(x[0]))  # shorter examples first
    toks = [TOKEN_RE.findall(en.lower().replace('’', "'")) for en, _ in pairs]
    # inflected form -> lemma
    lemma_of = {}
    for form, lemma in db.execute('SELECT form, lemma FROM exc'):
        lemma_of.setdefault(form, lemma)
    known = {r[0] for r in db.execute('SELECT DISTINCT lemma FROM sense')}

    def lemmas(w):
        out = {w}
        if w in lemma_of:
            out.add(lemma_of[w])
        for suf, rep in (('ies', 'y'), ('es', ''), ('s', ''), ('ied', 'y'), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e')):
            if w.endswith(suf) and len(w) > len(suf) + 2:
                b = w[:-len(suf)] + rep
                if b in known:
                    out.add(b)
                if len(b) > 2 and b[-1] == b[-2] and b[:-1] in known:  # stopped -> stop
                    out.add(b[:-1])
        return out

    index = {}
    lem_toks = []
    for i, ts in enumerate(toks):
        ls = [lemmas(t) for t in ts]
        lem_toks.append(ls)
        for l in set().union(*ls) if ls else ():
            lst = index.setdefault(l, [])
            if len(lst) < 4000:
                lst.append(i)
    rows = []
    freq = []  # how often each expression occurs in Tatoeba: a usage-frequency signal
    # expressions: words in order, at most two words in between
    for (p, cat) in exprs:
        words = p.replace("one's", '').replace('someone', '').replace('something', '').split()
        words = [w for w in words if w]
        if len(words) < 2:
            continue
        cand = None
        for w in words:
            c = set(index.get(w, ()))
            cand = c if cand is None else cand & c
            if not cand:
                break
        found = 0
        for i in sorted(cand or ()):
            ls = lem_toks[i]
            pos = -1
            ok = True
            for w in words:
                nxt = next((k for k in range(pos + 1, min(len(ls), pos + 4 if pos >= 0 else len(ls))) if w in ls[k]), None)
                if nxt is None:
                    ok = False
                    break
                pos = nxt
            if ok:
                if found < 4:
                    rows.append((f'{p}|{cat}', pairs[i][0], pairs[i][1]))
                found += 1
                if found >= 300:
                    break
        if found:
            freq.append((p, cat, found))
    n_expr = len(rows)
    # single words: three short examples per dictionary word
    for w in known:
        if "_" in w or ' ' in w:
            continue
        for i in index.get(w, ())[:3]:
            rows.append((f'w:{w}', pairs[i][0], pairs[i][1]))
    db.execute('CREATE TABLE exs(key TEXT, en TEXT, tr TEXT)')
    db.executemany('INSERT INTO exs VALUES (?,?,?)', rows)
    db.execute('CREATE INDEX exs_key ON exs(key)')
    db.execute('CREATE TABLE exfreq(phrase TEXT, cat TEXT, n INTEGER)')
    db.executemany('INSERT INTO exfreq VALUES (?,?,?)', freq)
    print('tatoeba pairs', len(pairs), 'expression examples', n_expr, 'word examples', len(rows) - n_expr)


def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    db = sqlite3.connect(OUT)
    db.executescript('''
      CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
      CREATE TABLE ft(word TEXT PRIMARY KEY, tr TEXT);
      CREATE TABLE syn(id INTEGER PRIMARY KEY, pos TEXT, gloss TEXT, examples TEXT, words TEXT, tr TEXT);
      CREATE TABLE sense(lemma TEXT, pos TEXT, rank INTEGER, syn_id INTEGER);
      CREATE TABLE exc(form TEXT, lemma TEXT, pos TEXT);
      CREATE TABLE famg(id INTEGER PRIMARY KEY, root TEXT, members TEXT, negs TEXT);
      CREATE TABLE fam(word TEXT PRIMARY KEY, gid INTEGER);
      CREATE TABLE expr(id INTEGER PRIMARY KEY, phrase TEXT, cat TEXT, tr TEXT, en TEXT, forms TEXT, ex TEXT);
    ''')
    ft = load_freedict(db)
    kenet = load_kenet()
    multi = load_wordnet(db, kenet)

    exprs = {}  # (phrase, cat) -> [tr, en, forms]
    for cat, text in CATEGORIES.items():
        for line in text.strip().splitlines():
            if '|' not in line:
                continue
            if cat == 'irregular_verbs':
                forms_part, tr = line.rsplit(' | ', 1)
                forms = [norm_phrase(x) for x in forms_part.split('|')]
                exprs[(forms[0], cat)] = [tr.strip(), None, forms]
                continue
            phrase, tr = line.split(' | ', 1)
            exprs[(norm_phrase(phrase), cat)] = [tr.strip(), None, None]

    curated = {p for p, _ in exprs}
    synrow = {r[0]: (r[2], r[5]) for r in db.execute('SELECT id, pos, gloss, examples, words, tr FROM syn')}
    added = {'phrasal_verbs': 0, 'idioms': 0, 'prepositional_phrases': 0}
    for lemma, pos, sid in multi:
        p = norm_phrase(lemma)
        if p in curated or not re.fullmatch(r"[a-z' -]+", p):
            continue
        toks = p.split()
        cat = None
        if pos == 'v' and len(toks) in (2, 3) and toks[1] in PARTICLES and \
                all(t in PARTICLES for t in toks[1:]):
            cat = 'phrasal_verbs'
        elif pos == 'v' and len(toks) >= 3 and any(t in ('the', "one's", 'a', 'oneself') for t in toks):
            cat = 'idioms'
        elif pos == 'r' and len(toks) >= 2 and toks[0] in PREPS:
            cat = 'prepositional_phrases'
        if not cat:
            continue
        gloss, tr = synrow.get(sid, (None, None))
        tr_list = json.loads(tr) if tr else []
        if not tr_list and p in ft:
            tr_list = ft[p][:2]
        exprs[(p, cat)] = [', '.join(tr_list[:4]) if tr_list else None, gloss, None]
        added[cat] += 1
    print('wordnet-derived expressions', added)
    examples = load_wiktionary(exprs)
    load_exd(db, exprs)

    # English gloss for curated items where WordNet knows the phrase.
    rows = []
    for (p, cat), (tr, en, forms) in exprs.items():
        if en is None:
            pref = 'v' if cat in ('phrasal_verbs', 'collocations', 'idioms', 'irregular_verbs', 'modal_verbs') else \
                'r' if cat in ('prepositional_phrases', 'discourse_markers', 'conjunctions', 'chunks', 'binomials') else None
            r = db.execute('SELECT s.gloss FROM sense x JOIN syn s ON s.id=x.syn_id '
                           'WHERE x.lemma=? ORDER BY (x.pos = ?) DESC, x.rank LIMIT 1', (p, pref)).fetchone()
            if r and pref and not db.execute('SELECT 1 FROM sense WHERE lemma=? AND pos=?', (p, pref)).fetchone() \
                    and cat not in ('false_friends', 'proverbs'):
                r = None  # only a different part of speech exists; it would mislead
            en = r[0] if r else None
        rows.append((p, cat, tr, en, json.dumps(forms) if forms else None, examples.get((p, cat))))
    db.executemany('INSERT INTO expr(phrase, cat, tr, en, forms, ex) VALUES (?,?,?,?,?,?)', rows)
    print('expressions total', len(rows))

    load_tatoeba(db, exprs)

    from word_family import build_families
    fams = build_families(os.path.join(RAW, 'wordnet'))
    gid_of = {}
    fam_rows = []
    for w, g in fams.items():
        key = id(g)
        if key not in gid_of:
            gid_of[key] = len(gid_of) + 1
            db.execute('INSERT INTO famg VALUES (?,?,?,?)', (gid_of[key], g[0], json.dumps(g[1]), json.dumps(g[2])))
        fam_rows.append((w, gid_of[key]))
    db.executemany('INSERT INTO fam VALUES (?,?)', fam_rows)
    print('word families', len(gid_of), 'words', len(fam_rows))

    db.executescript('''
      CREATE INDEX sense_lemma ON sense(lemma);
      CREATE INDEX exc_form ON exc(form);
    ''')
    db.execute("INSERT INTO meta VALUES ('version', '1')")
    db.commit()
    db.execute('VACUUM')
    db.close()
    print('size MB', round(os.path.getsize(OUT) / 1e6, 1))


if __name__ == '__main__':
    main()

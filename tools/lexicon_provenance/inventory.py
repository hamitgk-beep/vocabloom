#!/usr/bin/env python3
"""Provenance records for the shipped dictionaries, from the databases and the
build code only. Both databases are opened read-only (immutable) and their
SHA-256 is checked before and after.

  python3 -I tools/lexicon_provenance/inventory.py \
      --dict assets/dict.db --tr-en assets/tr_en.db --repo . \
      [--raw DIR] --out records.jsonl.gz [--stats stats.json]

How each source is found (no text-similarity guessing):
  * ft (word meanings): tools/data/main_meanings.jsonl.gz is the build input;
    tools/main_meanings.merged() is run again for every word and must give the
    stored row exactly. Each Turkish term is then traced to the Kindle
    Wiktionary paragraphs ("wk") or to damdafayton ("dm").
  * tr_en senses marked "fd": add_reverse.py is re-run in memory from the
    current ft; every reference must be reproduced, and takes the ft term's origin.
  * syn, expr (optional, --raw): the build steps of tools/build_dict.py are
    re-run on the raw inputs (kenet.xml, ili-map-pwn30.tab, wordnet/,
    eng-tur.tei, wiktionary_phrases.json.gz). A stored value equal to what one
    step produces is attributed to that step, with confidence "inferred",
    because the raw inputs were downloaded again and may differ from build time.
    Without --raw these fields are "unknown".
  * own_word / own_expr: the row's own status/source columns.
  * Everything else is marked by the table it is in, as written by the build code.
"""
import argparse
import gzip
import hashlib
import json
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from provenance import write_records  # noqa: E402


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def ro(path):
    return sqlite3.connect(f'file:{os.path.abspath(path)}?mode=ro&immutable=1', uri=True)


def src(sid, origin=None, method='derivation', confidence='exact', role='origin', **kw):
    d = {'id': sid, 'role': role, 'method': method, 'confidence': confidence}
    if origin:
        d['origin_record'] = origin
    d.update(kw)
    return d


def rec(db, table, key, field, kind, sources, ai='none', human=None, count=1, transforms=(), notes=(), idx=None):
    rid = f'{db}/{table}/{key}' + (f'#{idx}' if idx is not None else '') + (f':{field}' if field else '')
    r = {'id': rid, 'db': db, 'table': table, 'key': key, 'field': field, 'kind': kind,
         'sources': sources, 'ai': ai, 'human_verified': human, 'count': count}
    if transforms:
        r['transforms'] = list(transforms)
    if notes:
        r['notes'] = list(notes)
    return r


# ---------------------------------------------------------------- dict.db / ft

def ft_records(d, repo, stats):
    sys.path.insert(0, os.path.join(repo, 'tools'))
    import main_meanings as mm
    data = {}
    with gzip.open(os.path.join(repo, 'tools', 'data', 'main_meanings.jsonl.gz'), 'rt', encoding='utf-8') as f:
        for line in f:
            j = json.loads(line)
            data[j['w']] = j
    st = Counter()
    origin_of = {}  # (word, lowered term) -> 'wk' | 'dm'
    for word, tr in d.execute('SELECT word, tr FROM ft'):
        lines = json.loads(tr)
        st['words'] += 1
        j = data.get(word)
        if j is None:
            st['words_not_reproduced'] += 1
            for i, line in enumerate(lines):
                yield rec('dict.db', 'ft', word, 'tr', 'translation', [src('unknown', confidence='unknown')], idx=i,
                          ai='unknown', notes=['ft row not in main_meanings.jsonl.gz'])
            continue
        wk, dm = j.get('wk', []), j.get('dm', [])
        if mm.merged(word, wk, dm) == lines:
            st['words_reproduced'] += 1
        else:
            st['words_not_reproduced'] += 1
        wkset = {t.lower() for g in wk for t in (mm._clean(x, word) for x in mm._terms(g)) if t}
        dmset = {t.lower() for t in (mm._clean(x, word) for x in dm) if t}
        kinds = set()
        alone = mm.merged(word, wk, []) if wk and dm else None
        moved = bool(alone) and bool(lines) and lines[0] != alone[0] and not lines[0].startswith(alone[0])
        if moved:
            st['first_line_moved_by_dm'] += 1
        for i, line in enumerate(lines):
            for k, term in enumerate(mm._terms(line)):
                low = term.lower()
                if low in wkset:
                    sources = [src('kindle_en_tr_wiktionary_part', f'kindle-en-tr:{word}')]
                    if low in dmset:
                        sources.append(src('damdafayton', f'damdafayton:English.english={word}', role='support'))
                        st['terms_wk_and_dm'] += 1
                    else:
                        st['terms_wk_only'] += 1
                    origin_of[(word, low)] = 'wk'
                    kinds.add('wk')
                elif low in dmset:
                    sources = [src('damdafayton', f'damdafayton:English.english={word}')]
                    st['terms_dm_only'] += 1
                    origin_of[(word, low)] = 'dm'
                    kinds.add('dm')
                else:
                    sources = [src('unknown', confidence='unknown')]
                    st['terms_unknown'] += 1
                notes = []
                if i == 0 and k == 0:
                    notes.append('primary meaning')
                    if moved:
                        notes.append('conflict: damdafayton decided which Wiktionary sense is shown first')
                    st['primary_' + ('wk' if low in wkset else 'dm' if low in dmset else 'unknown')] += 1
                yield rec('dict.db', 'ft', word, 'tr', 'translation', sources, idx=f'{i}.{k}',
                          transforms=['main_meanings.extract', 'main_meanings.merged'], notes=notes)
        st['words_' + '_'.join(sorted(kinds) or ['none'])] += 1
    stats['ft'] = dict(st)
    return origin_of


# ---------------------------------------------------------------- raw rebuild (optional)

def rebuild(raw, repo):
    """Runs the first steps of tools/build_dict.py on the raw inputs, in memory.
    Returns syn_id -> (offset key, KeNet words), FreeDict ft, and expression
    values per build stage."""
    tools = os.path.join(repo, 'tools')
    sys.path.insert(0, tools)
    argv = sys.argv
    sys.argv = ['build_dict.py', raw, ':memory:']
    try:
        import build_dict as bd
    finally:
        sys.argv = argv
    mem = sqlite3.connect(':memory:')
    mem.executescript('''
      CREATE TABLE ft(word TEXT PRIMARY KEY, tr TEXT);
      CREATE TABLE syn(id INTEGER PRIMARY KEY, pos TEXT, gloss TEXT, examples TEXT, words TEXT, tr TEXT);
      CREATE TABLE sense(lemma TEXT, pos TEXT, rank INTEGER, syn_id INTEGER);
      CREATE TABLE exc(form TEXT, lemma TEXT, pos TEXT);''')
    out = {}
    if os.path.exists(os.path.join(raw, 'eng-tur.tei')):
        out['freedict'] = bd.load_freedict(mem)
    else:
        out['freedict'] = {}
    kenet = bd.load_kenet()
    multi = bd.load_wordnet(mem, kenet)
    offsets = {}
    sid = 0
    for pos_name in ('noun', 'verb', 'adj', 'adv'):
        with open(os.path.join(raw, 'wordnet', f'data.{pos_name}'), encoding='utf-8') as f:
            for line in f:
                if line.startswith(' '):
                    continue
                t = line.split()
                sid += 1
                offsets[sid] = f'{t[0]}-{bd.POS_MAP[t[2]]}'
    out['syn'] = {r[0]: (offsets[r[0]], json.loads(r[5]) if r[5] else [], r[2])
                  for r in mem.execute('SELECT id, pos, gloss, examples, words, tr FROM syn')}
    # expression stages, as in build_dict.main()
    stage = {}
    exprs = {}
    for cat, text in bd.CATEGORIES.items():
        for line in text.strip().splitlines():
            if '|' not in line:
                continue
            if cat == 'irregular_verbs':
                forms_part, tr = line.rsplit(' | ', 1)
                forms = [bd.norm_phrase(x) for x in forms_part.split('|')]
                key = (forms[0], cat)
                exprs[key] = [tr.strip(), None, forms]
            else:
                phrase, tr = line.split(' | ', 1)
                key = (bd.norm_phrase(phrase), cat)
                exprs[key] = [tr.strip(), None, None]
            stage[key] = {'tr': 'storilex_categories'}
    curated = {p for p, _ in exprs}
    synrow = {k: (v[2], v[1]) for k, v in out['syn'].items()}
    for lemma, pos, sid in multi:
        p = bd.norm_phrase(lemma)
        if p in curated or not re.fullmatch(r"[a-z' -]+", p):
            continue
        toks = p.split()
        cat = None
        if pos == 'v' and len(toks) in (2, 3) and toks[1] in bd.PARTICLES and all(t in bd.PARTICLES for t in toks[1:]):
            cat = 'phrasal_verbs'
        elif pos == 'v' and len(toks) >= 3 and any(t in ('the', "one's", 'a', 'oneself') for t in toks):
            cat = 'idioms'
        elif pos == 'r' and len(toks) >= 2 and toks[0] in bd.PREPS:
            cat = 'prepositional_phrases'
        if not cat:
            continue
        gloss, tr_list = synrow.get(sid, (None, []))
        who = 'kenet' if tr_list else None
        if not tr_list and p in out['freedict']:
            tr_list = out['freedict'][p][:2]
            who = 'freedict_eng_tur'
        exprs[(p, cat)] = [', '.join(tr_list[:4]) if tr_list else None, gloss, None]
        stage[(p, cat)] = {'tr': who, 'en': 'princeton_wordnet' if gloss else None, 'syn': sid}
    before = {k: list(v) for k, v in exprs.items()}
    if os.path.exists(os.path.join(raw, 'wiktionary_phrases.json.gz')):
        bd.load_wiktionary(exprs)
    for k, v in exprs.items():
        s = stage.setdefault(k, {})
        b = before.get(k)
        if b is None:
            s['tr'] = 'wiktionary' if v[0] else None
            s['en'] = 'wiktionary' if v[1] else None
        else:
            if b[0] is None and v[0]:
                s['tr'] = 'wiktionary'
            if b[1] is None and v[1]:
                s['en'] = 'wiktionary'
    out['expr_values'] = {k: (v[0], v[1]) for k, v in exprs.items()}
    out['expr_stage'] = stage
    import expr_fixes
    out['fix_tr'] = {tuple(k.split('|')): v for k, v in expr_fixes.TR.items()}
    out['fix_en'] = {tuple(k.split('|')): v for k, v in expr_fixes.EN.items()}
    return out


# ---------------------------------------------------------------- dict.db / other tables

WIKT = {'wiktionary': 'kaikki'}  # wiktionary_extract.py reads kaikki dumps of English and Turkish Wiktionary


def syn_records(d, raw_info, stats):
    st = Counter()
    syn = (raw_info or {}).get('syn')
    for sid, gloss, tr in d.execute('SELECT id, gloss, tr FROM syn'):
        off = syn[sid][0] if syn else None
        origin = f'pwn30:{off}' if off else f'storilex-syn:{sid} (WordNet 3.0 data order)'
        yield rec('dict.db', 'syn', str(sid), 'gloss+examples+words', 'definition',
                  [src('princeton_wordnet', origin)])
        terms = json.loads(tr) if tr else []
        if not terms:
            continue
        st['synsets_with_tr'] += 1
        if syn is None:
            st['tr_unknown_no_raw'] += len(terms)
            yield rec('dict.db', 'syn', str(sid), 'tr', 'translation',
                      [src('unknown', confidence='unknown', candidates=['kenet', 'ai_pretranslate'])],
                      ai='unknown', count=len(terms), transforms=['main_meanings.apply filter'])
            continue
        kenet_words = {w.lower() for w in syn[sid][1]}
        for t in terms:
            if t.lower() in kenet_words:
                st['tr_kenet'] += 1
                yield rec('dict.db', 'syn', str(sid), 'tr', 'translation',
                          [src('kenet', f'kenet:pwn30={off}', method='rebuild_match', confidence='inferred'),
                           src('cili', f'cili:pwn30={off}', role='support')],
                          transforms=['load_kenet via CILI', 'main_meanings.apply filter'], idx=t)
            else:
                st['tr_ai'] += 1
                yield rec('dict.db', 'syn', str(sid), 'tr', 'translation',
                          [src('ai_pretranslate', f'pretranslate:syn:{sid}', method='rebuild_match', confidence='inferred')],
                          ai='generated', transforms=['load_syn (fills synsets KeNet lacks)', 'main_meanings.apply filter'],
                          idx=t, notes=['not in KeNet for this synset; build_dict.load_syn fills such synsets from AI results'])
    stats['syn'] = dict(st)


def contrib_index(repo):
    path = os.path.join(repo, 'tools', 'contrib', 'storilex_contrib.json')
    with open(path, encoding='utf-8') as f:
        c = json.load(f)
    en_phr = {}
    ex_pairs = set()
    for p in c.get('phrases', []):
        if p.get('lang') != 'tr':
            en_phr[p['phrase'].lower()] = p
            if p.get('ex') and p.get('ex_tr'):
                ex_pairs.add((p['ex'], p['ex_tr']))
    for e in c.get('examples', []):
        if isinstance(e, dict):
            a, b = e.get('ex') or e.get('en'), e.get('ex_tr') or e.get('tr')
            if a and b:
                ex_pairs.add((a, b))
    for w in c.get('words', []):
        if isinstance(w, dict) and w.get('ex') and w.get('ex_tr'):
            ex_pairs.add((w['ex'], w['ex_tr']))
    edits = {}
    for e in c.get('phrase_edits', []):
        if isinstance(e, dict) and e.get('phrase'):
            edits[e['phrase'].lower()] = e
    return en_phr, ex_pairs, edits


def expr_records(d, repo, raw_info, stats):
    st = Counter()
    en_phr, _, edits = contrib_index(repo)
    sys.path.insert(0, os.path.join(repo, 'tools'))
    import expr_fixes
    fix_tr = {tuple(k.split('|')): v for k, v in expr_fixes.TR.items()}
    stage = (raw_info or {}).get('expr_stage', {})
    values = (raw_info or {}).get('expr_values', {})
    import categories
    cat_tr = {}
    for cat, text in categories.CATEGORIES.items():
        for line in text.strip().splitlines():
            if ' | ' in line:
                head, tr = line.rsplit(' | ', 1) if cat == 'irregular_verbs' else line.split(' | ', 1)
                cat_tr[(re.sub(r'\s+', ' ', head.split('|')[0].strip().lower().replace('’', "'")), cat)] = tr.strip()
    for eid, phrase, cat, tr, en, ex, entr, extr in d.execute(
            'SELECT id, phrase, cat, tr, en, ex, entr, extr FROM expr'):
        key = (phrase, cat)
        st['rows'] += 1
        # Turkish meaning
        if tr:
            c = en_phr.get(phrase) or edits.get(phrase)
            if c and (c.get('meaning') or '').strip() == tr.strip():
                s, ai = [src('storilex_contrib', f'storilex_contrib.json:{phrase}', method='input_match')], 'none'
                hv, who = True, 'storilex_contrib'
            elif key in fix_tr and fix_tr[key] == tr:
                s, ai, hv, who = [src('storilex_expr_fixes', f'expr_fixes.TR:{phrase}|{cat}', method='input_match')], 'assisted', None, 'storilex_expr_fixes'
            elif cat_tr.get(key) == tr:
                s, ai, hv, who = [src('storilex_categories', f'categories.py:{cat}:{phrase}', method='input_match')], 'assisted', None, 'storilex_categories'
            elif key in values and values[key][0] == tr and stage.get(key, {}).get('tr'):
                who = stage[key]['tr']
                sid = 'kaikki' if who == 'wiktionary' else who
                origin = f'wiktionary_phrases.json.gz:{phrase}|{cat}' if who == 'wiktionary' else \
                    f'pwn30-syn:{stage[key].get("syn")}' if who == 'kenet' else f'eng-tur.tei:{phrase}'
                s, ai, hv = [src(sid, origin, method='rebuild_match', confidence='inferred')], 'none', None
            elif raw_info is not None:
                who = 'ai_or_unknown'
                s = [src('unknown', confidence='unknown', candidates=['ai_pretranslate (gl-)', 'storilex_contrib', 'kaikki'])]
                ai, hv = 'unknown', None
            else:
                who = 'unknown_no_raw'
                s = [src('unknown', confidence='unknown', candidates=['kaikki', 'kenet', 'freedict_eng_tur', 'ai_pretranslate'])]
                ai, hv = 'unknown', None
            st['tr_' + who] += 1
            yield rec('dict.db', 'expr', f'{phrase}|{cat}', 'tr', 'expression', s, ai=ai, human=hv)
        if en:
            if key in values and values[key][1] == en and stage.get(key, {}).get('en'):
                who = stage[key]['en']
                sid = 'kaikki' if who == 'wiktionary' else who
                s = [src(sid, f'{sid}:{phrase}|{cat}', method='rebuild_match', confidence='inferred')]
                ai = 'none'
            else:
                who = 'unknown'
                s = [src('unknown', confidence='unknown', candidates=['princeton_wordnet', 'kaikki', 'storilex_expr_fixes'])]
                ai = 'unknown'
            st['en_' + who] += 1
            yield rec('dict.db', 'expr', f'{phrase}|{cat}', 'en', 'definition', s, ai=ai)
        if entr:
            st['entr_ai'] += 1
            yield rec('dict.db', 'expr', f'{phrase}|{cat}', 'entr', 'definition',
                      [src('ai_pretranslate', f'gl-:{phrase}|{cat}', method='build_rule')], ai='generated',
                      notes=['only build_dict.load_gloss writes entr'])
        if ex:
            st['ex'] += 1
            c = en_phr.get(phrase)
            if c and c.get('ex') == ex:
                s, ai = [src('storilex_contrib', f'storilex_contrib.json:{phrase}', method='input_match')], 'none'
            else:
                s, ai = [src('unknown', confidence='unknown', candidates=['kaikki'])], 'unknown'
            yield rec('dict.db', 'expr', f'{phrase}|{cat}', 'ex', 'example', s, ai=ai)
    stats['expr'] = dict(st)


def own_records(d, stats):
    st = Counter()
    for table, keycols in (('own_word', 'word'), ('own_expr', "phrase || '|' || cat")):
        for key, senses, status, reviewed, source in d.execute(
                f'SELECT {keycols}, senses, status, reviewed, source FROM {table}'):
            for i, s in enumerate(json.loads(senses)):
                if status == 'contrib' and reviewed == 1:
                    sources, ai, hv = [src('storilex_contrib', f'{table}:{key}#{i}', method='declared')], 'none', True
                    st[f'{table}_contrib'] += 1
                elif s.get('src') == 'storilex':
                    sources, ai, hv = [src('storilex_contrib', f'{table}:{key}#{i}', method='declared')], 'none', None
                    st[f'{table}_storilex_in_draft_row'] += 1
                elif status == 'ai_draft_unreviewed' or source == 'ai_generated':
                    sources, ai, hv = [src('own_dict_ai', f'{table}:{key}#{i}', method='declared')], 'generated', False
                    st[f'{table}_ai'] += 1
                else:
                    sources, ai, hv = [src('unknown', confidence='unknown')], 'unknown', None
                    st[f'{table}_unknown'] += 1
                yield rec('dict.db', table, key, 'sense', 'sense', sources, ai=ai, human=hv, idx=i,
                          notes=['runtime tier: ' + ('verified' if hv else 'draft')])
    stats['own'] = dict(st)


def exs_records(d, repo, stats):
    _, pairs, _ = contrib_index(repo)
    st = Counter()
    for key, en, tr in d.execute('SELECT key, en, tr FROM exs'):
        if (en, tr) in pairs:
            st['contrib'] += 1
            yield rec('dict.db', 'exs', key, 'en+tr', 'example',
                      [src('storilex_contrib', f'storilex_contrib.json:{en[:40]}', method='input_match')], human=True)
        else:
            st['tatoeba'] += 1
            yield rec('dict.db', 'exs', key, 'en+tr', 'example',
                      [src('tatoeba', None, method='build_rule')],
                      notes=['Tatoeba sentence ids, authors and per-sentence licences are not kept (tools/tatoeba_extract.py)'])
    stats['exs'] = dict(st)


def table_records(d, stats):
    """Structural tables: one aggregated record each."""
    n = lambda t: d.execute(f'SELECT count(*) FROM {t}').fetchone()[0]  # noqa: E731
    out = [
        ('sense', 'sense order', 'princeton_wordnet', 'pwn30:index.*'),
        ('exc', 'irregular forms', 'princeton_wordnet', 'pwn30:*.exc'),
        ('fam', 'word family', 'princeton_wordnet', 'tools/word_family.py over WordNet'),
        ('famg', 'word family', 'princeton_wordnet', 'tools/word_family.py over WordNet'),
        ('wfreq', 'frequency', 'tatoeba', 'counted from tatoeba_en_tr.tsv.gz'),
        ('exfreq', 'frequency', 'tatoeba', 'counted from tatoeba_en_tr.tsv.gz'),
    ]
    for t, kind, sid, origin in out:
        c = n(t)
        stats.setdefault('tables', {})[t] = c
        yield rec('dict.db', t, '*', None, kind, [src(sid, origin, method='build_rule')], count=c,
                  notes=['aggregated: one record for the whole table'])
    c = n('exd')
    stats.setdefault('tables', {})['exd'] = c
    for (p, cat) in d.execute('SELECT phrase, cat FROM exd'):
        yield rec('dict.db', 'exd', f'{p}|{cat}', 'json', 'explanation',
                  [src('ai_pretranslate', f'exd:{p}|{cat}', method='build_rule')], ai='generated')


# ---------------------------------------------------------------- tr_en.db

def tr_en_records(t, d, ft_origin, raw_info, stats):
    st = Counter()
    low = lambda s: s.replace('I', 'ı').replace('İ', 'i').lower()  # noqa: E731
    TR_WORD = re.compile(r"[a-zçğıöşüâîû]+(?: [a-zçğıöşüâîû]+)?")
    fd = defaultdict(list)
    piece_origin = {}
    for w, tr in d.execute('SELECT word, tr FROM ft'):
        if not re.fullmatch(r"[A-Za-z][A-Za-z' -]*", w) or len(w) < 2:
            continue
        pieces = [(low(p.strip()), p.strip()) for s in json.loads(tr) for p in re.split(r'[,;]', s)][:2]
        for p, orig in pieces:
            if p and TR_WORD.fullmatch(p) and w not in fd[p]:
                fd[p].append(w)
                piece_origin[(p, w)] = ft_origin.get((w, orig.lower()), 'unknown')
    # wn reverse: text "en words (gloss)" -> syn ids, to see whether the Turkish word is KeNet's
    syn = (raw_info or {}).get('syn')
    wn_text = defaultdict(list)
    for sid, gloss, words, tr in d.execute("SELECT id, gloss, words, tr FROM syn WHERE tr IS NOT NULL AND tr != '[]'"):
        en = [w.replace('_', ' ') for w in json.loads(words or '[]')][:4]
        if en:
            wn_text[', '.join(en) + (f' ({gloss})' if gloss else '')].append((sid, json.loads(tr)))
    for word, rank, senses in t.execute('SELECT word, rank, senses FROM lemma'):
        st['lemmas'] += 1
        for i, s in enumerate(json.loads(senses)):
            tag = s.get('s')
            if tag is None:
                st['senses_kaikki'] += 1
                yield rec('tr_en.db', 'lemma', word, 'sense', 'translation',
                          [src('kaikki_en', f'kaikki-Turkish:{word}', method='build_rule')], idx=i,
                          notes=['Turkish entries of English Wiktionary (tr-en-data.yml)'])
            elif tag == 'st':
                st['senses_contrib'] += 1
                yield rec('tr_en.db', 'lemma', word, 'sense', 'translation',
                          [src('storilex_contrib', f'storilex_contrib.json:{word}', method='declared')], human=True, idx=i)
            elif tag == 'fd':
                for k, e in enumerate(s['g'][0].split('; ')):
                    if e in fd.get(word, []):
                        o = piece_origin.get((word, e), 'unknown')
                        st['fd_refs_reproduced'] += 1
                        st['fd_refs_from_' + o] += 1
                        sid = {'wk': 'kindle_en_tr_wiktionary_part', 'dm': 'damdafayton'}.get(o, 'unknown')
                        sources = [src(sid, f'dict.db/ft/{e}', method='rebuild_match',
                                       confidence='exact' if sid != 'unknown' else 'unknown')]
                    else:
                        st['fd_refs_not_reproduced'] += 1
                        sources = [src('unknown', confidence='unknown', candidates=['freedict_eng_tur', 'damdafayton'])]
                    yield rec('tr_en.db', 'lemma', word, 'sense', 'translation', sources, idx=f'{i}.{k}',
                              transforms=['add_reverse.py (reverse of dict.db ft)'],
                              notes=['conflict: marked "fd" (FreeDict) but rebuilt from dict.db ft, which has held '
                                     'Kindle-Wiktionary + damdafayton meanings since 2026-11-17'])
            elif tag == 'wn':
                for k, g in enumerate(s['g']):
                    hits = wn_text.get(g, [])
                    tw = word
                    kenet = False
                    for sid, terms in hits:
                        if syn is not None and tw in {low(x.strip()) for x in syn[sid][1]}:
                            kenet = True
                    if syn is None or not hits:
                        st['wn_unknown'] += 1
                        sources = [src('princeton_wordnet', 'pwn30 (English side)', role='support'),
                                   src('unknown', confidence='unknown', candidates=['kenet', 'ai_pretranslate'])]
                        a = 'unknown'
                    elif kenet:
                        st['wn_kenet'] += 1
                        sources = [src('kenet', f'dict.db/syn ({len(hits)} synsets)', method='rebuild_match', confidence='inferred'),
                                   src('princeton_wordnet', 'pwn30 (English side)')]
                        a = 'none'
                    else:
                        st['wn_ai'] += 1
                        sources = [src('ai_pretranslate', f'dict.db/syn ({len(hits)} synsets)', method='rebuild_match', confidence='inferred'),
                                   src('princeton_wordnet', 'pwn30 (English side)')]
                        a = 'generated'
                    notes = ['add_reverse.py says "Only open, human-made sources", but syn.tr also holds AI-filled Turkish'] if a == 'generated' else []
                    yield rec('tr_en.db', 'lemma', word, 'sense', 'translation', sources, ai=a, idx=f'{i}.{k}',
                              transforms=['add_reverse.py (reverse of dict.db syn)'], notes=notes)
            else:
                st['senses_unknown_tag'] += 1
                yield rec('tr_en.db', 'lemma', word, 'sense', 'translation', [src('unknown', confidence='unknown')], idx=i, ai='unknown')
    c = t.execute('SELECT count(*) FROM lemma').fetchone()[0]
    yield rec('tr_en.db', 'lemma', '*', 'rank', 'frequency', [src('frequencywords', 'tr_full.txt', method='build_rule')], count=c,
              notes=['aggregated: rank of every lemma'])
    c = t.execute('SELECT count(*) FROM form').fetchone()[0]
    yield rec('tr_en.db', 'form', '*', None, 'inflection',
              [src('kaikki_en', 'kaikki-Turkish forms + FrequencyWords list', method='build_rule', confidence='inferred')], count=c,
              notes=['aggregated; build_tr_en.py keeps only forms seen in the frequency list'])
    for lemma, tr, en, sid in t.execute('SELECT lemma, tr, en, id FROM ex'):
        if sid is None:
            st['ex_contrib'] += 1
            yield rec('tr_en.db', 'ex', lemma, 'tr+en', 'example',
                      [src('storilex_contrib', f'storilex_contrib.json:{lemma}', method='build_rule')], human=True)
        else:
            st['ex_tatoeba'] += 1
            yield rec('tr_en.db', 'ex', lemma, 'tr+en', 'example',
                      [src('tatoeba', f'tatoeba:{sid}', method='build_rule')], idx=sid,
                      notes=['Turkish sentence id kept; English sentence id, authors and licences not kept'])
    for table in ('ctx', 'ctxn'):
        c = t.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
        yield rec('tr_en.db', table, '*', None, 'statistic', [src('tatoeba', 'tur-eng pairs', method='build_rule')], count=c,
                  notes=['aggregated: word counts from Tatoeba pairs'])
    c = t.execute("SELECT count(*) FROM meta WHERE key LIKE 'ctx:%'").fetchone()[0]
    yield rec('tr_en.db', 'meta', 'ctx:*', None, 'example', [src('storilex_contrib', 'tools/contrib context', method='build_rule')],
              human=True, count=c, notes=['aggregated: hand-checked context sentences'])
    stats['tr_en'] = dict(st)


# ---------------------------------------------------------------- main

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dict', default='assets/dict.db')
    ap.add_argument('--tr-en', default='assets/tr_en.db')
    ap.add_argument('--repo', default='.')
    ap.add_argument('--raw', help='directory with kenet.xml, ili-map-pwn30.tab, wordnet/, eng-tur.tei, wiktionary_phrases.json.gz')
    ap.add_argument('--out', required=True)
    ap.add_argument('--stats')
    a = ap.parse_args(argv)
    before = {p: sha256(p) for p in (a.dict, a.tr_en)}
    stats = {'sha256': before}
    raw_info = None
    if a.raw:
        raw_info = rebuild(os.path.abspath(a.raw), os.path.abspath(a.repo))
        stats['raw'] = {f: sha256(os.path.join(a.raw, f)) for f in sorted(os.listdir(a.raw))
                        if os.path.isfile(os.path.join(a.raw, f)) and not f.endswith('.zip')}
    d, t = ro(a.dict), ro(a.tr_en)
    repo = os.path.abspath(a.repo)
    origin = {}

    def all_records():
        nonlocal origin
        gen = ft_records(d, repo, stats)
        while True:
            try:
                yield next(gen)
            except StopIteration as e:
                origin = e.value or {}
                break
        yield from syn_records(d, raw_info, stats)
        yield from expr_records(d, repo, raw_info, stats)
        yield from own_records(d, stats)
        yield from exs_records(d, repo, stats)
        yield from table_records(d, stats)
        yield from tr_en_records(t, d, origin, raw_info, stats)

    n = write_records(a.out, all_records())
    d.close()
    t.close()
    after = {p: sha256(p) for p in (a.dict, a.tr_en)}
    stats['records_written'] = n
    stats['unchanged'] = before == after
    if a.stats:
        with open(a.stats, 'w', encoding='utf-8') as f:
            json.dump(stats, f, ensure_ascii=False, indent=1)
    print(json.dumps({k: v for k, v in stats.items() if k != 'raw'}, ensure_ascii=False, indent=1))
    if before != after:
        print('ERROR: a dictionary file changed during the inventory', file=sys.stderr)
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Integrity and impact check of a candidate built by build_candidate.py
(docs/lexicon_remediation/SAFE_DICTIONARY_BUILD.md, COVERAGE_AND_QUALITY_IMPACT.md).

  python3 -I tools/lexicon_remediation/check_candidate.py --base-dict assets/dict.db --base-tr-en assets/tr_en.db \
      --cand WORK/candidate [--json impact.json]

Integrity (exit 1 when any fails): same schema; untouched tables byte-equal;
no new text anywhere (every kept value was in the base); WordNet sense and
synset ids, expression ids and own-dictionary rows unchanged; every tr_en form,
example and context row points at an existing lemma and gloss; no "fd" tag left.
Impact: what the 24,314 words whose main meaning came only from damdafayton
still show, and what the most frequent words lose.

Exit codes: 0 all checks pass, 1 a check failed, 2 bad input.
"""
import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
from collections import Counter


def ro(path):
    return sqlite3.connect(f'file:{path}?mode=ro&immutable=1', uri=True)


def schema(c):
    return sorted((t, n, s) for t, n, s in c.execute("SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"))


def table_hash(c, table, order):
    h = hashlib.sha256()
    for row in c.execute(f'SELECT * FROM "{table}" ORDER BY {order}'):
        h.update(json.dumps(row, ensure_ascii=False).encode())
    return h.hexdigest()


def terms(line):
    return [x.strip() for x in re.split(r'[,;]', line) if x.strip()]


def flat_glosses(senses):
    return [g for s in senses for g in s['g']]


def check_dict(b, c, problems, facts):
    if c.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
        problems.append('dict.db: integrity_check failed')
    if schema(b) != schema(c):
        problems.append('dict.db: schema differs from the base')
    for table, order in (('sense', 'rowid'), ('exc', 'rowid'), ('fam', 'rowid'), ('famg', 'rowid'), ('exs', 'rowid'),
                         ('wfreq', 'rowid'), ('exfreq', 'rowid'), ('own_word', 'word'), ('own_expr', 'rowid'), ('exd', 'rowid'),
                         ('wd', 'rowid')):
        if table_hash(b, table, order) != table_hash(c, table, order):
            problems.append(f'dict.db: table {table} changed but must not')
    bs = {i: (p, g, e, w, json.loads(t) if t else [], x) for i, p, g, e, w, t, x in b.execute('SELECT id, pos, gloss, examples, words, tr, extr FROM syn')}
    cs = {i: (p, g, e, w, json.loads(t) if t else [], x) for i, p, g, e, w, t, x in c.execute('SELECT id, pos, gloss, examples, words, tr, extr FROM syn')}
    if set(bs) != set(cs):
        problems.append('dict.db: synset ids differ')
    for i, v in cs.items():
        o = bs.get(i)
        if o is None:
            continue
        if v[:4] != o[:4] or v[5] != o[5]:
            problems.append(f'dict.db: syn {i} changed outside tr')
        if not set(v[4]) <= set(o[4]):
            problems.append(f'dict.db: syn {i} has Turkish words that were not there')
    missing = c.execute('SELECT count(*) FROM sense WHERE syn_id NOT IN (SELECT id FROM syn)').fetchone()[0]
    if missing:
        problems.append(f'dict.db: {missing} senses point at no synset')
    be = {r[0]: r for r in b.execute('SELECT id, phrase, cat, tr, en, forms, ex, entr, extr FROM expr')}
    ce = {r[0]: r for r in c.execute('SELECT id, phrase, cat, tr, en, forms, ex, entr, extr FROM expr')}
    if set(be) != set(ce):
        problems.append('dict.db: expression ids differ')
    for i, r in ce.items():
        o = be.get(i)
        if o and (r[:3] != o[:3] or r[4:] != o[4:] or r[3] not in (o[3], None)):
            problems.append(f'dict.db: expr {i} changed beyond removing its tr')
    bft = {w: json.loads(t) for w, t in b.execute('SELECT word, tr FROM ft')}
    cft = {w: json.loads(t) for w, t in c.execute('SELECT word, tr FROM ft')}
    for w, lines in cft.items():
        if w not in bft:
            problems.append(f'dict.db: ft has a new word {w!r}')
            continue
        if not lines or not all(lines):
            problems.append(f'dict.db: ft {w!r} has an empty meaning')
        old = {t.lower() for line in bft[w] for t in terms(line)}
        new = {t.lower() for line in lines for t in terms(line)}
        if not new <= old:
            problems.append(f'dict.db: ft {w!r} has terms that were not there: {sorted(new - old)[:3]}')
    facts['ft_words'] = {'base': len(bft), 'candidate': len(cft), 'removed': len(set(bft) - set(cft)),
                         'changed': sum(1 for w in cft if cft[w] != bft[w]),
                         'primary_changed': sum(1 for w in cft if cft[w][0] != bft[w][0])}
    return bft, cft


def check_tr_en(b, c, problems, facts):
    if c.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
        problems.append('tr_en.db: integrity_check failed')
    if schema(b) != schema(c):
        problems.append('tr_en.db: schema differs from the base')
    bl = {w: (r, json.loads(s)) for w, r, s in b.execute('SELECT word, rank, senses FROM lemma')}
    cl = {w: (r, json.loads(s)) for w, r, s in c.execute('SELECT word, rank, senses FROM lemma')}
    tags = Counter()
    for w, (rank, senses) in cl.items():
        o = bl.get(w)
        if o is None:
            problems.append(f'tr_en.db: new lemma {w!r}')
            continue
        if rank != o[0]:
            problems.append(f'tr_en.db: rank of {w!r} changed')
        if not senses or not any(s['g'] for s in senses):
            problems.append(f'tr_en.db: lemma {w!r} has no meaning')
        old_text = set(flat_glosses(o[1])) | {x for s in o[1] if s.get('s') in ('fd', 'rv') for x in s['g'][0].split('; ')}
        for s in senses:
            tags[s.get('s')] += 1
            if s.get('s') == 'fd':
                problems.append(f'tr_en.db: {w!r} still has an "fd" tag')
            pieces = s['g'][0].split('; ') if s.get('s') == 'rv' else s['g']
            if not set(pieces) <= old_text:
                problems.append(f'tr_en.db: {w!r} has meanings that were not there')
        kept_plain = [s for s in senses if s.get('s') not in ('fd', 'rv', 'wn')]
        if kept_plain != [s for s in o[1] if s.get('s') not in ('fd', 'rv', 'wn')]:
            problems.append(f'tr_en.db: Wiktionary or contributor meanings of {w!r} changed')
    words = set(cl)
    for table in ('form', 'ex', 'ctx', 'ctxn'):
        n = c.execute(f'SELECT count(*) FROM {table} WHERE lemma NOT IN (SELECT word FROM lemma)').fetchone()[0]
        if n:
            problems.append(f'tr_en.db: {n} {table} rows point at no lemma')
    n_g = {w: len(flat_glosses(s)) for w, (_, s) in cl.items()}
    for table in ('ctx', 'ctxn'):
        bad = sum(1 for w, g in c.execute(f'SELECT lemma, g FROM {table}') if w in n_g and not 0 <= g < n_g[w])
        if bad:
            problems.append(f'tr_en.db: {bad} {table} rows point at no gloss')
    for (key,) in c.execute("SELECT key FROM meta WHERE key LIKE 'ctx:%'"):
        _, w, g, _ = key.split(':', 3)
        if w not in words or not 0 <= int(g) < n_g[w]:
            problems.append(f'tr_en.db: meta {key[:40]} points at no gloss')
    facts['tr_en_lemmas'] = {'base': len(bl), 'candidate': len(cl), 'removed': len(set(bl) - words), 'tags': dict(tags)}
    return bl, cl


def ctx_text_check(b, c, bl, cl, problems):
    """Every ctx / ctxn row of the candidate names the same gloss as a row of the
    base with the same counts (an "rv" gloss may have lost some of its words)."""
    def same(new, old):
        return new == old or set(new.split('; ')) <= set(old.split('; '))

    for table, cols in (('ctx', 'lemma, g, word, n'), ('ctxn', 'lemma, g, n')):
        base = {}
        for row in b.execute(f'SELECT {cols} FROM {table}'):
            gl = flat_glosses(bl[row[0]][1]) if row[0] in bl else []
            base.setdefault((row[0],) + tuple(row[2:]), []).append(gl[row[1]] if row[1] < len(gl) else None)
        bad = 0
        for row in c.execute(f'SELECT {cols} FROM {table}'):
            gl = flat_glosses(cl[row[0]][1]) if row[0] in cl else []
            text = gl[row[1]] if 0 <= row[1] < len(gl) else None
            if text is None or not any(o is not None and same(text, o) for o in base.get((row[0],) + tuple(row[2:]), [])):
                bad += 1
        if bad:
            problems.append(f'tr_en.db: {bad} {table} rows now point at another gloss text')


def impact(b, c, bft, cft, facts, records_stats=None):
    """What the words that lose their ft row still show in the app."""
    removed = sorted(set(bft) - set(cft))
    sense_lemmas = {w for (w,) in c.execute('SELECT DISTINCT lemma FROM sense')}
    kenet = {w for (w,) in c.execute("SELECT DISTINCT x.lemma FROM sense x JOIN syn s ON s.id = x.syn_id "
                                     "WHERE s.tr IS NOT NULL AND s.tr != '[]'")}
    own = {w: (st, rv) for w, st, rv in c.execute('SELECT word, status, reviewed FROM own_word')}
    out = Counter()
    for w in removed:
        if w in own and own[w] == ('contrib', 1):
            out['verified_contribution'] += 1
        elif w in kenet:
            out['kenet_sense_turkish'] += 1
        elif w in own:
            out['ai_draft_only'] += 1
        elif w in sense_lemmas:
            out['english_definition_only'] += 1
        else:
            out['nothing'] += 1
    facts['removed_ft_words_now_show'] = dict(out)
    facts['removed_ft_words_not_known_to_lemmatizer'] = sum(1 for w in removed if w not in sense_lemmas)
    freq = [w for (w,) in c.execute('SELECT word FROM wfreq ORDER BY n DESC')] if 'n' in [r[1] for r in c.execute('PRAGMA table_info(wfreq)')] else []
    if freq:
        rm = set(removed)
        facts['frequent_words_losing_ft'] = {str(k): sum(1 for w in freq[:k] if w in rm) for k in (1000, 5000, 10000)}
        facts['frequent_words_losing_ft_examples'] = [w for w in freq[:5000] if w in rm][:40]
    return removed


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--base-dict', default='assets/dict.db')
    ap.add_argument('--base-tr-en', default='assets/tr_en.db')
    ap.add_argument('--cand', required=True)
    ap.add_argument('--json')
    a = ap.parse_args(argv)
    try:
        b, c = ro(a.base_dict), ro(os.path.join(a.cand, 'dict.db'))
        bt, ct = ro(a.base_tr_en), ro(os.path.join(a.cand, 'tr_en.db'))
        problems, facts = [], {}
        bft, cft = check_dict(b, c, problems, facts)
        bl, cl = check_tr_en(bt, ct, problems, facts)
        ctx_text_check(bt, ct, bl, cl, problems)
        impact(b, c, bft, cft, facts)
    except (sqlite3.Error, OSError, KeyError, ValueError) as e:
        print(f'check_candidate: bad input: {e}', file=sys.stderr)
        return 2
    facts['problems'] = problems
    print(json.dumps(facts, ensure_ascii=False, indent=1))
    if a.json:
        with open(a.json, 'w', encoding='utf-8') as f:
            json.dump(facts, f, ensure_ascii=False, indent=1)
    if problems:
        print(f'check_candidate: {len(problems)} problem(s)', file=sys.stderr)
        return 1
    print('check_candidate: all integrity checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())

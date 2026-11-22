#!/usr/bin/env python3
"""Candidate dictionaries without the blocked and mislabelled content (Task 5D,
docs/lexicon_remediation/SAFE_DICTIONARY_BUILD.md).

Reads assets/dict.db and assets/tr_en.db read-only, copies them to OUT and
changes only the copies. Every value that is taken out goes into
OUT/quarantine.db with its reason and its provenance record id; nothing is
deleted without a trace and no new meaning is written.

  python3 -I tools/lexicon_remediation/build_candidate.py --dict assets/dict.db --tr-en assets/tr_en.db \
      --repo . --records base/records.jsonl.gz --records-stats base/inventory.json --out WORK/candidate

--records must come from tools/lexicon_provenance/inventory.py --raw on the same
two files (their SHA-256 is checked against --records-stats).

What changes (profile "blocked-out"):
  dict.db  ft        rebuilt by main_meanings.merged(word, wiktionary, []) - the
                     project's own merge with damdafayton left out. Words with
                     no Wiktionary meaning lose their ft row. Every term kept is
                     checked to be a Wiktionary term of that word.
  dict.db  syn.tr    the Turkish words that are not KeNet's for that synset
                     (AI-filled by build_dict.load_syn) are taken out.
  dict.db  expr.tr   the one meaning traced to FreeDict (GPL-2.0+) is taken out.
  tr_en.db lemma     "fd" groups: damdafayton-origin English words taken out,
                     the rest tagged "rv"; "wn" glosses made from the AI-filled
                     syn.tr words taken out; lemmas left with no meaning are
                     taken out together with their forms, examples and context
                     rows; ctx / ctxn gloss indexes are renumbered.
Unchanged: WordNet senses and ids, expr ids, own_word / own_expr (AI drafts stay
labelled drafts), exs, families, frequencies, Tatoeba examples of kept lemmas.

Exit codes: 0 built, 2 bad input, 3 an input file changed while it was read.
"""
import argparse
import gzip
import hashlib
import json
import os
import shutil
import sqlite3
import sys
from collections import Counter, defaultdict

PROFILE = 'blocked-out'


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def read_records(path):
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                yield json.loads(line)


def origin_ids(r):
    return {s.get('id') for s in r.get('sources', []) if s.get('role', 'origin') == 'origin'}


def index_records(path):
    """What the builder needs from the provenance records, by position."""
    syn_ai = defaultdict(set)        # syn id -> AI-filled Turkish terms
    expr_freedict = set()            # (phrase, cat) whose tr came from FreeDict
    fd_origin = {}                   # (lemma, 'i.k') -> source id of the reversed English word
    wn_bad = set()                   # (lemma, 'i.k') of wn glosses not traced to KeNet
    record_of = {}
    for r in read_records(path):
        db, t, key, field = r['db'], r['table'], r['key'], r.get('field')
        rest = r['id'][len(f'{db}/{t}/{key}'):]
        if field and rest.endswith(':' + field):
            rest = rest[:-len(field) - 1]
        idx = rest[1:] if rest.startswith('#') else None
        o = origin_ids(r)
        if db == 'dict.db' and t == 'syn' and field == 'tr' and r.get('ai') != 'none':
            if idx is None:
                raise ValueError('syn.tr records were made without --raw; KeNet terms cannot be told from AI terms')
            syn_ai[int(key)].add(idx)
            record_of[('syn', key, idx)] = r['id']
        elif db == 'dict.db' and t == 'expr' and field == 'tr' and 'freedict_eng_tur' in o:
            expr_freedict.add(tuple(key.split('|', 1)))
            record_of[('expr', key)] = r['id']
        elif db == 'tr_en.db' and t == 'lemma' and idx and '.' in idx:
            transforms = ' '.join(r.get('transforms', []))
            if 'reverse of dict.db ft' in transforms:
                fd_origin[(key, idx)] = next(iter(o)) if len(o) == 1 else 'unknown'
                record_of[('fd', key, idx)] = r['id']
            elif 'reverse of dict.db syn' in transforms:
                if 'kenet' not in o:
                    wn_bad.add((key, idx))
                    record_of[('wn', key, idx)] = r['id']
    return syn_ai, expr_freedict, fd_origin, wn_bad, record_of


class Quarantine:
    def __init__(self, path):
        if os.path.exists(path):
            os.remove(path)
        self.db = sqlite3.connect(path)
        self.db.execute('CREATE TABLE removed(db TEXT, tbl TEXT, key TEXT, field TEXT, value TEXT, reason TEXT, record_id TEXT)')
        self.db.execute('CREATE TABLE note(key TEXT PRIMARY KEY, value TEXT)')
        self.n = Counter()

    def add(self, db, tbl, key, field, value, reason, record_id=None):
        self.db.execute('INSERT INTO removed VALUES (?,?,?,?,?,?,?)',
                        (db, tbl, key, field, value if isinstance(value, str) else json.dumps(value, ensure_ascii=False), reason, record_id))
        self.n[(db, tbl, reason)] += 1

    def close(self, notes):
        self.db.executemany('INSERT INTO note VALUES (?,?)', [(k, json.dumps(v, ensure_ascii=False)) for k, v in notes.items()])
        self.db.commit()
        self.db.close()


# ------------------------------------------------------------ dict.db

def rebuild_ft(d, repo, q, report):
    sys.path.insert(0, os.path.join(repo, 'tools'))
    import main_meanings as mm
    data = {}
    with gzip.open(os.path.join(repo, 'tools', 'data', 'main_meanings.jsonl.gz'), 'rt', encoding='utf-8') as f:
        for line in f:
            j = json.loads(line)
            data[j['w']] = j
    st = Counter()
    id_map = []  # (old id, new id or '', reason)
    rows = d.execute('SELECT word, tr FROM ft ORDER BY word').fetchall()
    for word, tr in rows:
        old = json.loads(tr)
        j = data.get(word) or {}
        wk = j.get('wk', [])
        if mm.merged(word, wk, j.get('dm', [])) != old:
            raise ValueError(f'ft row {word!r} is not main_meanings.merged of its data; refusing to rebuild it')
        wkset = {t.lower() for g in wk for t in (mm._clean(x, word) for x in mm._terms(g)) if t}
        new = mm.merged(word, wk, []) if wk else []
        # Only Wiktionary terms stay; a term that is not one is never written.
        new = [', '.join(t for t in mm._terms(line) if t.lower() in wkset) for line in new]
        new = [line for line in new if line]
        new_terms = {t.lower(): (i, k) for i, line in enumerate(new) for k, t in enumerate(mm._terms(line))}
        for i, line in enumerate(old):
            for k, t in enumerate(mm._terms(line)):
                pos = new_terms.get(t.lower())
                if pos is None:
                    q.add('dict.db', 'ft', word, 'tr', t, 'damdafayton_only' if t.lower() not in wkset else 'merge_dropped',
                          f'dict.db/ft/{word}#{i}.{k}:tr')
                    st['terms_removed'] += 1
                else:
                    st['terms_kept'] += 1
        for i in range(len(old)):
            nid = ''
            if new and i < len(new) and new[i] == old[i]:
                nid = f'ft:{word}#{i}'
            elif new:
                first = mm._terms(old[i])[0].lower() if mm._terms(old[i]) else None
                hit = next((n for n, line in enumerate(new) if first and first in {t.lower() for t in mm._terms(line)}), None)
                nid = f'ft:{word}#{hit}' if hit is not None else ''
            id_map.append((f'ft:{word}#{i}', nid))
        if not new:
            d.execute('DELETE FROM ft WHERE word = ?', (word,))
            st['words_removed'] += 1
        elif new != old:
            d.execute('UPDATE ft SET tr = ? WHERE word = ?', (json.dumps(new, ensure_ascii=False), word))
            st['words_changed'] += 1
            if new[0] != old[0]:
                st['primary_changed'] += 1
        else:
            st['words_same'] += 1
    report['ft'] = dict(st)
    return id_map


def clean_syn(d, syn_ai, q, record_of, report):
    st = Counter()
    for sid, bad in sorted(syn_ai.items()):
        (tr,) = d.execute('SELECT tr FROM syn WHERE id = ?', (sid,)).fetchone()
        terms = json.loads(tr)
        keep = [t for t in terms if t not in bad]
        for t in terms:
            if t in bad:
                q.add('dict.db', 'syn', str(sid), 'tr', t, 'ai_not_kenet', record_of.get(('syn', str(sid), t)))
                st['terms_removed'] += 1
        d.execute('UPDATE syn SET tr = ? WHERE id = ?', (json.dumps(keep, ensure_ascii=False), sid))
        st['synsets_changed'] += 1
        if not keep:
            st['synsets_left_without_tr'] += 1
    report['syn'] = dict(st)


def clean_expr(d, expr_freedict, q, record_of, report):
    st = Counter()
    for phrase, cat in sorted(expr_freedict):
        row = d.execute('SELECT id, tr FROM expr WHERE phrase = ? AND cat = ?', (phrase, cat)).fetchone()
        if row:
            q.add('dict.db', 'expr', f'{phrase}|{cat}', 'tr', row[1], 'freedict_gpl', record_of.get(('expr', f'{phrase}|{cat}')))
            d.execute('UPDATE expr SET tr = NULL WHERE id = ?', (row[0],))
            st['tr_removed'] += 1
    report['expr'] = dict(st)


# ------------------------------------------------------------ tr_en.db

def clean_tr_en(t, fd_origin, wn_bad, q, record_of, report):
    st = Counter()
    gloss_map = {}  # lemma -> {old flat gloss index: new index}
    removed_lemmas = []
    for word, senses_js in t.execute('SELECT word, senses FROM lemma ORDER BY word').fetchall():
        senses = json.loads(senses_js)
        if not any(s.get('s') in ('fd', 'rv', 'wn') for s in senses):
            continue
        new, mapping, flat_old, flat_new = [], {}, 0, 0
        for i, s in enumerate(senses):
            tag = s.get('s')
            if tag in ('fd', 'rv'):
                words = s['g'][0].split('; ')
                keep = []
                for k, e in enumerate(words):
                    o = fd_origin.get((word, f'{i}.{k}'))
                    if o == 'kindle_en_tr_wiktionary_part':
                        keep.append(e)
                        st['rv_kept'] += 1
                    else:
                        q.add('tr_en.db', 'lemma', word, f'senses[{i}].g[0]', e,
                              'damdafayton_reverse' if o == 'damdafayton' else 'reverse_origin_unknown',
                              record_of.get(('fd', word, f'{i}.{k}')))
                        st['rv_removed_' + (o or 'none')] += 1
                if keep:
                    mapping[flat_old] = flat_new
                    new.append({'p': s.get('p', ''), 'g': ['; '.join(keep)], 's': 'rv'})
                    flat_new += 1
                    st['fd_groups_retagged'] += 1
                flat_old += 1
            elif tag == 'wn':
                g = []
                for k, gl in enumerate(s['g']):
                    if (word, f'{i}.{k}') in wn_bad:
                        q.add('tr_en.db', 'lemma', word, f'senses[{i}].g[{k}]', gl, 'reverse_of_ai_syn_tr',
                              record_of.get(('wn', word, f'{i}.{k}')))
                        st['wn_removed'] += 1
                    else:
                        mapping[flat_old] = flat_new + len(g)
                        g.append(gl)
                    flat_old += 1
                if g:
                    new.append(dict(s, g=g))
                    flat_new += len(g)
            else:
                for _ in s['g']:
                    mapping[flat_old] = flat_new
                    flat_old += 1
                    flat_new += 1
                new.append(s)
        if new == senses:
            continue
        gloss_map[word] = mapping
        if new:
            t.execute('UPDATE lemma SET senses = ? WHERE word = ?', (json.dumps(new, ensure_ascii=False), word))
            st['lemmas_changed'] += 1
        else:
            removed_lemmas.append(word)
    t.execute('CREATE TEMP TABLE rm(w TEXT PRIMARY KEY)')
    t.executemany('INSERT INTO temp.rm VALUES (?)', [(w,) for w in removed_lemmas])
    for word, senses_js in t.execute('SELECT word, senses FROM lemma WHERE word IN (SELECT w FROM temp.rm)').fetchall():
        q.add('tr_en.db', 'lemma', word, 'senses', senses_js, 'no_meaning_left')
    for table in ('form', 'ex', 'ctx', 'ctxn'):
        for word, n in t.execute(f'SELECT lemma, count(*) FROM {table} WHERE lemma IN (SELECT w FROM temp.rm) GROUP BY lemma').fetchall():
            q.add('tr_en.db', table, word, None, str(n), 'lemma_removed')
            st[f'{table}_rows_removed'] += n
        t.execute(f'DELETE FROM {table} WHERE lemma IN (SELECT w FROM temp.rm)')
    for (key,) in t.execute("SELECT key FROM meta WHERE key LIKE 'ctx:%'").fetchall():
        if key.split(':')[1] in set(removed_lemmas):
            t.execute('DELETE FROM meta WHERE key = ?', (key,))
            st['meta_ctx_removed'] += 1
    t.execute('DELETE FROM lemma WHERE word IN (SELECT w FROM temp.rm)')
    st['lemmas_removed'] = len(removed_lemmas)
    t.execute('DROP TABLE temp.rm')
    # Context statistics point at glosses by their flat index.
    gone = set(removed_lemmas)
    for word, mapping in gloss_map.items():
        if word in gone:
            continue
        for table, cols in (('ctx', 'rowid, g'), ('ctxn', 'rowid, g')):
            for rowid, g in t.execute(f'SELECT {cols} FROM {table} WHERE lemma = ?', (word,)).fetchall():
                if g in mapping:
                    if mapping[g] != g:
                        t.execute(f'UPDATE {table} SET g = ? WHERE rowid = ?', (mapping[g], rowid))
                        st[f'{table}_renumbered'] += 1
                else:
                    t.execute(f'DELETE FROM {table} WHERE rowid = ?', (rowid,))
                    st[f'{table}_rows_removed'] += 1
        for key, in t.execute("SELECT key FROM meta WHERE key LIKE ?", (f'ctx:{word}:%',)).fetchall():
            g = int(key.split(':')[2])
            if g not in mapping:
                t.execute('DELETE FROM meta WHERE key = ?', (key,))
                st['meta_ctx_removed'] += 1
            elif mapping[g] != g:
                parts = key.split(':', 3)
                t.execute('UPDATE meta SET key = ? WHERE key = ?', (f'ctx:{word}:{mapping[g]}:{parts[3]}', key))
                st['meta_ctx_renumbered'] += 1
    report['tr_en'] = dict(st)
    return removed_lemmas


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dict', default='assets/dict.db')
    ap.add_argument('--tr-en', default='assets/tr_en.db')
    ap.add_argument('--repo', default='.')
    ap.add_argument('--records', required=True)
    ap.add_argument('--records-stats', required=True)
    ap.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    src = {'dict.db': a.dict, 'tr_en.db': a.tr_en}
    before = {k: sha256(p) for k, p in src.items()}
    out = os.path.abspath(a.out)
    for p in src.values():
        if os.path.dirname(os.path.abspath(p)) == out:
            print('build_candidate: --out must not be the folder of the input files', file=sys.stderr)
            return 2
    with open(a.records_stats, encoding='utf-8') as f:
        rs = json.load(f)
    if sorted(rs.get('sha256', {}).values()) != sorted(before.values()) or 'raw' not in rs:
        print('build_candidate: the records were not made with --raw from these exact files', file=sys.stderr)
        return 2
    os.makedirs(out, exist_ok=True)
    cand = {k: os.path.join(out, k) for k in src}
    for k in src:
        shutil.copyfile(src[k], cand[k])
    try:
        syn_ai, expr_fd, fd_origin, wn_bad, record_of = index_records(a.records)
    except ValueError as e:
        print(f'build_candidate: {e}', file=sys.stderr)
        return 2
    q = Quarantine(os.path.join(out, 'quarantine.db'))
    report = {'profile': PROFILE, 'input_sha256': before, 'records': os.path.basename(a.records),
              'records_sha256': sha256(a.records)}
    d, t = sqlite3.connect(cand['dict.db']), sqlite3.connect(cand['tr_en.db'])
    counts_before = {k: {n: c.execute(f'SELECT count(*) FROM "{n}"').fetchone()[0]
                         for (n,) in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
                     for k, c in (('dict.db', d), ('tr_en.db', t))}
    try:
        id_map = rebuild_ft(d, os.path.abspath(a.repo), q, report)
    except ValueError as e:
        print(f'build_candidate: {e}', file=sys.stderr)
        return 2
    clean_syn(d, syn_ai, q, record_of, report)
    clean_expr(d, expr_fd, q, record_of, report)
    removed_lemmas = clean_tr_en(t, fd_origin, wn_bad, q, record_of, report)
    d.execute("INSERT OR REPLACE INTO meta VALUES ('candidate', ?)",
              (json.dumps({'profile': PROFILE, 'from': before['dict.db'], 'tool': 'tools/lexicon_remediation/build_candidate.py'}),))
    t.execute("INSERT OR REPLACE INTO meta VALUES ('candidate', ?)",
              (json.dumps({'profile': PROFILE, 'from': before['tr_en.db'], 'tool': 'tools/lexicon_remediation/build_candidate.py'}),))
    t.execute("INSERT OR REPLACE INTO meta VALUES ('reverse', ?)",
              (f"{report['tr_en'].get('rv_kept', 0)} reversed English words (rv) from the Wiktionary part of dict.db ft; "
               "KeNet meanings from dict.db syn (KeNet terms only)",))
    for c in (d, t):
        c.commit()
        c.execute('VACUUM')
        c.close()
    after = {k: sha256(p) for k, p in src.items()}
    counts_after = {}
    for k in cand:
        c = sqlite3.connect(f'file:{cand[k]}?mode=ro', uri=True)
        counts_after[k] = {n: c.execute(f'SELECT count(*) FROM "{n}"').fetchone()[0]
                           for (n,) in c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
        c.close()
    with open(os.path.join(out, 'ft_id_map.tsv'), 'w', encoding='utf-8') as f:
        f.write('old_id\tnew_id\n')
        for o, n in id_map:
            f.write(f'{o}\t{n}\n')
    report.update(counts_before=counts_before, counts_after=counts_after, removed_lemmas=len(removed_lemmas),
                  quarantine={f'{a}/{b}/{c}': n for (a, b, c), n in sorted(q.n.items())},
                  output_sha256={k: sha256(p) for k, p in cand.items()},
                  ft_ids_changed=sum(1 for o, n in id_map if o != n), ft_ids_lost=sum(1 for _, n in id_map if not n))
    q.close({'report': report})
    report['quarantine_sha256'] = sha256(os.path.join(out, 'quarantine.db'))
    with open(os.path.join(out, 'build_report.json'), 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print(json.dumps({k: report[k] for k in ('ft', 'syn', 'expr', 'tr_en', 'quarantine', 'output_sha256')}, ensure_ascii=False, indent=1))
    if before != after:
        print('build_candidate: an input file changed while it was read', file=sys.stderr)
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Tatoeba sentence ids, authors and per-sentence licences for the example
sentences (Task 5D, docs/lexicon_remediation/TATOEBA_ATTRIBUTION_PLAN.md).

  python3 -I tools/lexicon_remediation/tatoeba_ids.py pairs sentences_detailed.csv links.csv \
      [--cc0 sentences_CC0.csv] [--export-date YYYY-MM-DD] --out tatoeba_pairs.jsonl.gz
  python3 -I tools/lexicon_remediation/tatoeba_ids.py match tatoeba_pairs.jsonl.gz --dict assets/dict.db \
      --tr-en assets/tr_en.db --out tatoeba_match/

pairs   English-Turkish pairs from the Tatoeba exports with both sentence ids,
        both usernames and both licences: "CC0-1.0" when the sentence is in
        sentences_CC0.csv, else the Tatoeba default "CC-BY-2.0-FR". A sentence
        without a username keeps "user": null (attribution then names
        "Tatoeba contributors" and the sentence id).
match   For each dictionary example (dict.db exs, tr_en.db ex), the Tatoeba pair
        whose English AND Turkish text are exactly the same, and only when that
        pair is the only one; tr_en.db ex rows must also have the same Turkish
        sentence id. No similarity matching: every other row goes to the
        unverified pool (unmatched.tsv / ambiguous.tsv). The databases are opened
        read-only and never changed.

Only the standard library is used.
"""
import argparse
import csv
import gzip
import hashlib
import json
import os
import sqlite3
import sys
from collections import Counter, defaultdict

csv.field_size_limit(1 << 24)


def _rows(path):
    with open(path, encoding='utf-8', newline='') as f:
        for line in f:
            yield line.rstrip('\n').split('\t')


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def build_pairs(detailed, links, cc0=None, export_date=None):
    """sentences_detailed.csv: id, lang, text, username, added, modified (tab separated)."""
    sent = {}
    for p in _rows(detailed):
        if len(p) >= 4 and p[1] in ('eng', 'tur'):
            sent[p[0]] = (p[1], p[2], p[3] if p[3] not in ('', '\\N') else None)
    free = set()
    if cc0:
        free = {p[0] for p in _rows(cc0) if p}
    out = []
    for p in _rows(links):
        if len(p) < 2:
            continue
        a, b = sent.get(p[0]), sent.get(p[1])
        if a and b and a[0] == 'eng' and b[0] == 'tur':
            out.append({'en_id': int(p[0]), 'tr_id': int(p[1]), 'en': a[1], 'tr': b[1],
                        'en_user': a[2], 'tr_user': b[2],
                        'en_license': 'CC0-1.0' if p[0] in free else 'CC-BY-2.0-FR',
                        'tr_license': 'CC0-1.0' if p[1] in free else 'CC-BY-2.0-FR',
                        'export_date': export_date})
    out.sort(key=lambda r: (r['en_id'], r['tr_id']))
    return out


def read_pairs(path):
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                yield json.loads(line)


def match(pairs, dict_path=None, tr_en_path=None):
    by_text = defaultdict(list)
    for r in pairs:
        by_text[(r['en'], r['tr'])].append(r)
    matched, unmatched, ambiguous = [], [], []
    st = Counter()

    def one(table, key, en, tr, tr_id=None):
        hits = by_text.get((en, tr), [])
        if tr_id is not None:
            hits = [h for h in hits if h['tr_id'] == tr_id]
        row = {'table': table, 'key': key, 'en': en, 'tr': tr}
        if len(hits) == 1:
            matched.append(dict(row, **{k: hits[0][k] for k in ('en_id', 'tr_id', 'en_user', 'tr_user', 'en_license', 'tr_license')}))
            st[f'{table}_matched'] += 1
        elif hits:
            ambiguous.append(dict(row, candidates=len(hits)))
            st[f'{table}_ambiguous'] += 1
        else:
            unmatched.append(row)
            st[f'{table}_unmatched'] += 1

    if dict_path:
        c = sqlite3.connect(f'file:{dict_path}?mode=ro&immutable=1', uri=True)
        for key, en, tr in c.execute('SELECT key, en, tr FROM exs ORDER BY rowid'):
            one('dict.db/exs', key, en, tr)
        c.close()
    if tr_en_path:
        c = sqlite3.connect(f'file:{tr_en_path}?mode=ro&immutable=1', uri=True)
        for lemma, tr, en, sid in c.execute('SELECT lemma, tr, en, id FROM ex ORDER BY rowid'):
            if sid is not None:
                one('tr_en.db/ex', lemma, en, tr, tr_id=sid)
        c.close()
    return matched, unmatched, ambiguous, dict(st)


def _tsv(path, rows, cols):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, cols, delimiter='\t', extrasaction='ignore')
        w.writeheader()
        w.writerows(rows)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('pairs')
    p.add_argument('detailed')
    p.add_argument('links')
    p.add_argument('--cc0')
    p.add_argument('--export-date')
    p.add_argument('--out', required=True)
    m = sub.add_parser('match')
    m.add_argument('pairs')
    m.add_argument('--dict')
    m.add_argument('--tr-en')
    m.add_argument('--out', required=True)
    a = ap.parse_args(argv)
    if a.cmd == 'pairs':
        rows = build_pairs(a.detailed, a.links, a.cc0, a.export_date)
        with gzip.open(a.out, 'wt', encoding='utf-8') as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + '\n')
        lic = Counter(r['en_license'] for r in rows) + Counter(r['tr_license'] for r in rows)
        print(json.dumps({'pairs': len(rows), 'licences': dict(lic),
                          'inputs': {os.path.basename(x): sha256(x) for x in (a.detailed, a.links, a.cc0) if x}}, indent=1))
        return 0
    os.makedirs(a.out, exist_ok=True)
    matched, unmatched, ambiguous, st = match(read_pairs(a.pairs), a.dict, a.tr_en)
    cols = ['table', 'key', 'en', 'tr', 'en_id', 'tr_id', 'en_user', 'tr_user', 'en_license', 'tr_license', 'candidates']
    _tsv(os.path.join(a.out, 'matched.tsv'), matched, cols)
    _tsv(os.path.join(a.out, 'unmatched.tsv'), unmatched, cols)
    _tsv(os.path.join(a.out, 'ambiguous.tsv'), ambiguous, cols)
    print(json.dumps(st, indent=1))
    return 0


if __name__ == '__main__':
    sys.exit(main())

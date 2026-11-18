"""Builds the final own-dictionary files from the full run and the fill run.

Nothing is sent to any API here. Output (tools/own_dict/dictionary/):
  entries.jsonl.gz      one record per headword, with status, QC flags and the action to take
  invalid_candidates.tsv headwords with no usable meaning; waiting for approval, nothing deleted
  summary.json          counts for the report

usage: python3 tools/own_dict/assemble.py
"""
import collections, gzip, json, os, re, sqlite3, subprocess, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'qc'))
from qc import check  # noqa: E402

OUT = 'tools/own_dict/dictionary'
os.makedirs(OUT, exist_ok=True)


def load(p):
    with gzip.open(p, 'rt', encoding='utf-8') as f:
        return [json.loads(l) for l in f]


recs = load('tools/own_dict/full_out/results.jsonl.gz') + load('tools/own_dict/fill_out/results.jsonl.gz')
# headwords still missing after the fill run: kept as invalid/typo candidates, with their source kind
done = {r['w'] for r in recs}
src = {it['w']: it for it in json.load(open('tools/own_dict/full_items.json', encoding='utf-8'))}
for fn in ('tools/own_dict/full_out/failed.jsonl', 'tools/own_dict/fill_out/failed.jsonl'):
    for line in open(fn, encoding='utf-8'):
        w = json.loads(line).get('w')
        if w and w not in done and w in src:
            done.add(w)
            recs.append({'w': w, 'kind': src[w]['k'], 'group': src[w]['group'], 'freq': src[w].get('freq'),
                         'base': '', 'senses': []})
keys = {(r['w'].lower(), r['kind']) for r in recs}
assert len(keys) == len(recs), 'duplicate headwords'

# what the app already has (main dictionary database)
c = sqlite3.connect('assets/dict.db')
ft = {w.lower(): t for w, t in c.execute('select word, tr from ft')}
expr_tr = collections.defaultdict(list)
for p, t in c.execute('select phrase, tr from expr'):
    expr_tr[p.lower()].append(t)

dup_index = collections.defaultdict(list)
for r in recs:
    dup_index[r['w'].lower()].append(r['kind'])

flags_by = collections.defaultdict(list)
for r in recs:
    for fl in check(r, OUT, dup_index):
        flags_by[(r['w'], r['kind'])].append(fl)

INVALID_NOTE = {
    'accouterments': ('valid_rare', 'Valid spelling variant of "accoutrements"; needs a meaning, not deletion'),
    'babunbaby': ('invalid', 'Not an English word'),
    'capapie': ('invalid', 'Misspelling of "cap-a-pie"'),
    'diagnotor': ('invalid', 'Not an English word'),
    'dieselise': ('valid_rare', 'British spelling of "dieselize"'),
    'rindish': ('invalid', 'Not a standard English word'),
    'ringster': ('uncertain', 'Rare word, meaning unclear; check manually'),
    'dollar out': ('invalid', 'Not a standard expression'),
    'dollar up': ('invalid', 'Not a standard expression'),
    'doodie up': ('invalid', 'Not a standard expression'),
    "monar'chical": ('typo', 'Source typo for "monarchical"; fix headword, then translate'),
    'nonagression': ('typo', 'Misspelling of "nonaggression"; fix headword, then translate'),
}

out_recs = []
stats = collections.Counter()
for r in recs:
    w, kind = r['w'], r['kind']
    lw = w.lower()
    fl = flags_by.get((w, kind), [])
    cats = sorted({f[1] for f in fl if f[0] in ('high', 'medium')})
    if not r['senses']:
        status, action = 'invalid_candidate', 'wait_for_approval'
        verdict, note = INVALID_NOTE.get(lw, ('invalid', 'No meaning returned'))
    elif kind == 'expr' and any(t and t.strip() and 'Türkçesi yok' not in t for t in expr_tr.get(lw, [])):
        status, action = 'auto_generated', 'skip_existing_turkish'
        verdict, note = None, 'Already has Turkish in the app'
    elif kind == 'word':
        status, action = 'auto_generated', 'replaces_source_tr'
        verdict, note = None, f'Replaces damdafayton meaning in app: {ft.get(lw, "")[:120]}'
    else:
        status, action = 'auto_generated', 'add_new'
        verdict, note = None, None
    if lw in INVALID_NOTE and r['senses']:
        verdict, note = INVALID_NOTE[lw]
        status, action = 'invalid_candidate', 'wait_for_approval'
    stats[(kind, action)] += 1
    out_recs.append({
        'w': w, 'kind': kind, 'group': r['group'], 'freq': r.get('freq'), 'base': r.get('base', ''),
        'senses': r['senses'], 'status': status, 'reviewed': False, 'action': action,
        'qc': cats, 'verdict': verdict, 'note': note,
        'source': 'ai_generated', 'inputs': 'English headword and free WordNet hints (WordNet License) only',
    })

with gzip.open(os.path.join(OUT, 'entries.jsonl.gz'), 'wt', encoding='utf-8') as f:
    for rec in out_recs:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')

with open(os.path.join(OUT, 'invalid_candidates.tsv'), 'w', encoding='utf-8') as f:
    f.write('headword\tkind\tverdict\tnote\n')
    for rec in out_recs:
        if rec['status'] == 'invalid_candidate':
            f.write(f"{rec['w']}\t{rec['kind']}\t{rec['verdict']}\t{rec['note']}\n")

summary = {
    'total_items': len(out_recs),
    'by_kind_and_action': {f'{k}/{a}': n for (k, a), n in sorted(stats.items())},
    'with_qc_flag': sum(1 for r in out_recs if r['qc']),
    'qc_categories': dict(collections.Counter(c for r in out_recs for c in r['qc'])),
    'invalid_candidates': sum(1 for r in out_recs if r['status'] == 'invalid_candidate'),
}
json.dump(summary, open(os.path.join(OUT, 'summary.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(json.dumps(summary, ensure_ascii=False, indent=1))

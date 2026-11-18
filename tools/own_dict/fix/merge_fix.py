"""Applies the fix run to the merged dataset. No API call.

- 26 missing gap words: added as new records.
- 8 flagged gap records: the new senses come first; an old sense is kept only if it has a complete example,
  no English words and its Turkish meaning is not already in the new list.
- One remaining English word in a fixed meaning is removed locally.
Writes tools/own_dict/fix/merged_v2.jsonl.gz and tools/own_dict/fix/fix_log.jsonl.
"""
import gzip, json, re, sys
sys.path.insert(0, 'tools/own_dict/qc')
from qc import english_words

merged = [json.loads(l) for l in gzip.open('tools/own_dict/gap/merged_entries.jsonl.gz', 'rt', encoding='utf-8')]
fix = {}
for l in gzip.open('tools/own_dict/fix/fix_out/results.jsonl.gz', 'rt', encoding='utf-8'):
    r = json.loads(l)
    fix[r['w'].lower()] = r
index = {(r['w'].lower(), r['kind']): i for i, r in enumerate(merged)}
log = open('tools/own_dict/fix/fix_log.jsonl', 'w', encoding='utf-8')


def toks(t):
    return {re.sub(r'\s+', ' ', x.strip().lower()) for x in re.split(r'[;,|]', t or '') if x.strip()}


added = replaced = 0
for w, n in fix.items():
    if not n['senses']:
        continue
    key = (w, 'word')
    if key in index:
        rec = merged[index[key]]
        old = rec['senses']
        new_tok = {t for s in n['senses'] for t in toks(s['tr'])}
        keep = [s for s in old if s.get('tr', '').strip() and (s.get('ex_tr') or '').strip() and (s.get('en') or '').strip()
                and not english_words(s['tr']) and not (toks(s['tr']) & new_tok)]
        senses = [dict(s, src='fix') for s in n['senses']] + [dict(s, src='kept') for s in keep]
        log.write(json.dumps({'w': w, 'change': 'replaced_with_fix', 'old': [s['tr'] for s in old],
                              'new': [s['tr'] for s in n['senses']], 'kept': [s['tr'] for s in keep]},
                             ensure_ascii=False) + '\n')
        rec['senses'] = senses
        rec['status'] = 'auto_generated'
        rec['qc'] = []
        replaced += 1
    else:
        merged.append({'w': n['w'], 'kind': 'word', 'group': n['group'], 'freq': n.get('freq'), 'base': n.get('base', ''),
                       'senses': [dict(s, src='fix') for s in n['senses']], 'status': 'auto_generated', 'reviewed': False,
                       'action': 'replaces_damdafayton_part', 'app_meaning_today_wiktionary_first': True,
                       'damdafayton_part_today': '', 'qc': [], 'source': 'ai_generated',
                       'inputs': 'English headword and WordNet hints only'})
        log.write(json.dumps({'w': w, 'change': 'added_missing', 'new': [s['tr'] for s in n['senses']]},
                             ensure_ascii=False) + '\n')
        added += 1

# remaining English words in Turkish meanings: removed locally (only where the rest of the meaning is Turkish)
local = 0
for rec in merged:
    for s in rec['senses']:
        if english_words(s['tr']) and s.get('src') == 'fix':
            keep = [t.strip() for t in s['tr'].split(',') if t.strip() and not english_words(t)]
            if keep:
                log.write(json.dumps({'w': rec['w'], 'change': 'english_token_removed', 'before': s['tr'],
                                      'after': ', '.join(keep)}, ensure_ascii=False) + '\n')
                s['tr'] = ', '.join(keep)
                local += 1
log.close()
with gzip.open('tools/own_dict/fix/merged_v2.jsonl.gz', 'wt', encoding='utf-8') as f:
    for rec in merged:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')
keys = {}
for rec in merged:
    keys.setdefault((rec['w'].lower(), rec['kind']), 0)
    keys[(rec['w'].lower(), rec['kind'])] += 1
print(json.dumps({'records': len(merged), 'replaced': replaced, 'added': added, 'local_english_removed': local,
                  'duplicate_keys': sum(1 for v in keys.values() if v > 1)}))

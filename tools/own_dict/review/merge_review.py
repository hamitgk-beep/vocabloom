"""Merges the re-translated headwords into the reviewed entries. No API call.

For a re-translated headword: the new senses come first; an old sense is kept only if its Turkish
meaning is not already in the new list and its example is complete. Every change goes to change_log.jsonl.
Writes tools/own_dict/review/entries_final.jsonl.gz.
"""
import gzip, json, re

D = 'tools/own_dict/review'
recs = [json.loads(l) for l in gzip.open(f'{D}/entries_reviewed.jsonl.gz', 'rt', encoding='utf-8')]
new = {}
for l in gzip.open(f'{D}/review_out/results.jsonl.gz', 'rt', encoding='utf-8'):
    r = json.loads(l)
    new[(r['w'].lower(), r['kind'])] = r
log = open(f'{D}/change_log.jsonl', 'a', encoding='utf-8')


def norm(x):
    return re.sub(r'\s+', ' ', x.strip().lower())


def toks(text):
    return {norm(p) for p in re.split(r'[;,|]', text or '') if norm(p)}


existing = {(r['w'].lower(), r['kind']) for r in recs if not r.get('corrected_w') and r['senses']}
done = 0
for rec in recs:
    if not rec.get('api_pending'):
        continue  # only the queued headwords are merged; others are left as they were
    key_w = (rec.get('corrected_w') or rec['w']).lower()
    n = new.get((key_w, rec['kind']))
    if not n or not n['senses']:
        continue
    if rec.get('corrected_w') and (key_w, rec['kind']) in existing:
        # the correct spelling is already in the dictionary: do not import a second copy
        rec['status'] = 'invalid_candidate'
        rec['verdict'] = 'duplicate'
        rec['note'] = f"Duplicate of existing headword {key_w}; not imported (original spelling kept)"
        rec['alt_senses'] = n['senses']
        rec.pop('api_pending', None)
        log.write(json.dumps({'w': rec['original_w'], 'kind': rec['kind'], 'change': 'typo_duplicate',
                              'corrected': key_w}, ensure_ascii=False) + '\n')
        continue
    done += 1
    old = rec['senses']
    new_tok = {t for s in n['senses'] for t in toks(s['tr'])}
    keep_old = [s for s in old if s.get('tr', '').strip() and (s.get('ex_tr') or '').strip()
                and not (toks(s['tr']) & new_tok)]
    merged = [dict(s, src='api_review') for s in n['senses']] + [dict(s, src='kept') for s in keep_old]
    dropped = [s['tr'] for s in old if s not in keep_old]
    log.write(json.dumps({'w': rec['w'], 'kind': rec['kind'], 'change': 'api_retranslated',
                          'dropped_old_senses': dropped, 'kept_old_senses': [s['tr'] for s in keep_old]},
                         ensure_ascii=False) + '\n')
    rec['senses'] = merged
    rec['status'] = 'auto_generated'
    rec['reviewed'] = False
    rec.pop('api_pending', None)
    if rec.get('corrected_w'):
        rec['w'] = rec['corrected_w']
        rec['action'] = 'replaces_source_tr'
        rec['note'] = f"Headword corrected from {rec['original_w']}; was invalid_candidate"
log.close()
with gzip.open(f'{D}/entries_final.jsonl.gz', 'wt', encoding='utf-8') as f:
    for rec in recs:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')
print('re-translated headwords merged:', done, 'of', len(new))

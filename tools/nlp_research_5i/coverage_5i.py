"""Task 5I: where the context panel shows no Turkish, and why, by source status. Read-only.

usage: python3 -I tools/nlp_research_5i/coverage_5i.py RECORDS.jsonl.gz OUT_DIR DUMP.jsonl [DUMP.jsonl ...]

RECORDS: tools/lexicon_provenance/inventory.py output (run WITHOUT --raw here, so expression and WordNet Turkish
is "unknown" unless a Storilex input reproduces it; that is reported as unknown, never guessed).
DUMP: dump_5i_test.dart rows (any set). Only rows where the expression was found are counted.

Per row with no Turkish shown in the expression panel (or the "cannot tell" note), one reason:
  ranking     the expression has a CHECKED (non-draft) Turkish meaning, but a word-by-word reading led
  draft_only  the expression has Turkish only in an unreviewed AI draft
  no_tr       the expression has no Turkish at all (checked or draft)
And the source of the expression's checked Turkish: storilex_contrib / storilex_categories / storilex_expr_fixes
/ unknown (no raw rebuild: kaikki, KeNet, FreeDict or an AI pre-translation cannot be told apart here).
Writes OUT_DIR/review_queue_5i.tsv (top phrases, most frequent first). Writes nothing else; never approves data.
MAGPIE sentences are not written (BNC licence): only phrase names, counts and MAGPIE labels.
"""
import collections, gzip, json, os, sys

rec_path, out = sys.argv[1], sys.argv[2]
dumps = sys.argv[3:]
os.makedirs(out, exist_ok=True)
expr_src = {}
for l in gzip.open(rec_path, 'rt', encoding='utf-8'):
    r = json.loads(l)
    if r['table'] == 'expr' and r['field'] == 'tr':
        expr_src[r['key']] = '+'.join(sorted({s['id'] for s in r['sources']}))

rows = []
for p in dumps:
    for l in open(p, encoding='utf-8'):
        r = json.loads(l)
        if r.get('found'):
            rows.append(r)

agg = collections.defaultdict(lambda: collections.Counter())
reasons = collections.Counter()
by_src = collections.Counter()
for r in rows:
    if r.get('shown'):
        continue
    if (r.get('idiomTr') or 0) > 0:
        why = 'ranking'
    elif (r.get('idiomDraftTr') or 0) > 0:
        why = 'draft_only'
    else:
        why = 'no_tr'
    src = expr_src.get(f"{r['phrase']}|{r['cat']}", 'no_expr_tr')
    reasons[(why, r['gold'])] += 1
    by_src[(why, src)] += 1
    a = agg[(r['phrase'], r['cat'])]
    a['n'] += 1
    a[why] += 1
    a['gold_' + r['gold']] += 1
    a['cannot_tell'] += r.get('gap') == 'idiomOrWords'
    a['src:' + src] += 1
    a['lit:' + str(r.get('bestLit'))] += 1

with open(os.path.join(out, 'review_queue_5i.tsv'), 'w', encoding='utf-8') as f:
    f.write('# Task 5I review queue (read-only analysis; nothing approved or written to any DB). '
            'reason: ranking = checked Turkish exists but a word-by-word reading led; draft_only = only an unreviewed AI '
            'draft; no_tr = no Turkish. source = provenance of the expression\'s checked Turkish (unknown = not traceable '
            'without the raw build inputs).\n')
    f.write('phrase\tcategory\tempty_panels\tranking\tdraft_only\tno_tr\tgold_idiom\tgold_literal\tcannot_tell\tsource\tleading_word_lemma\n')
    for (ph, cat), a in sorted(agg.items(), key=lambda kv: (-kv[1]['n'], kv[0]))[:100]:
        src = ','.join(k[4:] for k in a if k.startswith('src:'))
        lit = ','.join(k[4:] for k, _ in collections.Counter({k: v for k, v in a.items() if k.startswith('lit:')}).most_common(2))
        f.write(f"{ph}\t{cat}\t{a['n']}\t{a['ranking']}\t{a['draft_only']}\t{a['no_tr']}\t{a['gold_idiom']}\t{a['gold_literal']}\t{a['cannot_tell']}\t{src}\t{lit}\n")

print('rows found:', len(rows), '| empty:', sum(reasons.values()), '| phrases:', len(agg))
for k, v in sorted(reasons.items()):
    print('reason', k, v)
for k, v in sorted(by_src.items()):
    print('source', k, v)

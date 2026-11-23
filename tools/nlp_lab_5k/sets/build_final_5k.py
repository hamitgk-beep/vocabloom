"""Task 5K: a NEW locked MAGPIE final for idiomatic-vs-literal decisions, disjoint from every earlier set.

usage: python3 -I tools/nlp_lab_5k/sets/build_final_5k.py assets/dict.db MAGPIE_unfiltered.jsonl \
           MAGPIE_filtered_split_random.jsonl SETS_DIR OUT_DIR
SETS_DIR holds the earlier sets rebuilt with their own scripts (5f/ 5g/ 5h/ 5i/ 5j/); every lock is checked.

Source: MAGPIE (Haagsma, Bos, Nissim 2020, commit 7fa677b of github.com/hslh/magpie-corpus). Labels: CC BY 4.0,
crowd annotators (people). Sentences are mostly BNC, which may not be redistributed: the set is LOCAL ONLY and
never committed; only its SHA-256 (final5k_LOCKED.sha256) is, written before any system ran on it.

Independence
  * sentences in NO earlier set (5F dev/final, 5G dev/tune/final, 5H dev/tune/final, 5I final, 5J final/hold);
  * idiom TYPES: a type-disjoint set was tried first and is not possible: 5F-5J used almost every dictionary idiom
    of MAGPIE (14 usable rows were left, see --type-disjoint). So the idioms are those of the earlier FINAL sets
    (5F/5G finals = 5H/5I/5J final idioms: measured, never tuned on); idioms of 5H dev/tune and 5J hold are excluded.
    A new-sentence set, not a new-idiom set;
  * only rows of MAGPIE's random-split TEST part (the split DISC's released checkpoint was trained against), so a
    DISC checkpoint trained on that split's training part would not have seen them;
  * annotator confidence >= 0.70 INCLUDING 1.0: the 0.70-0.99 rows of these idioms are used up by 5F-5J. Risk:
    5A/5B/5E (diagnostics, no tuning sets) drew some agreement-1.0 rows; their lists are local only and lost;
  * the three 5E regression sentences are excluded.
Natural label mix: at most CAP rows per idiom drawn at random regardless of label (no per-label balancing).
Output columns: idiom, label (i/l), dict category, MAGPIE id, sentence, idiom char spans "a:b,c:d" in the sentence,
variant type, confidence.
"""
import hashlib, json, os, random, re, sqlite3, sys

dbp, magpie, magpie_rand, sets, out = sys.argv[1:6]
os.makedirs(out, exist_ok=True)
SEED = 20261123
CAP = 3
TYPE_DISJOINT = '--type-disjoint' in sys.argv
KNOWN = {'circle the wagons', 'poacher turned gamekeeper', "she'll be right"}
KNOWN_IDS = {'51620', '32520', '50299'}
LOCKS = {
    '5f/final5f_magpie.tsv': '6874e6501b4b42aa88349601b0ff0f5efa06b518be25521298a79a8bc592b38a',
    '5g/final5g_magpie.tsv': 'ce55c3bb456d41ec60dcfec18bb5a9fe3d93985c882f5856f2bc2983c6faea60',
    '5h/dev5h_magpie.tsv': '5e81b1beb5a11cb1e656d057d5dcbcf50cf1cf90213e918e18d5cdaab21829cd',
    '5h/tune5h_magpie.tsv': '197f7faf2a76fe7675ecb083e752b59c433f88ff005a422731209e4d40b20707',
    '5h/final5h_magpie.tsv': 'd479d256a72bc4bffb4d77f210dda711517d96230fd616453e88da99dd88e22c',
    '5i/final5i_magpie.tsv': 'a50d77ca95384f9e83098b95f7923180f2865d15e9b03d2d3dbb51e3f8b446a0',
    '5j/final5j_magpie.tsv': '27034bd80f1b2e575dabe3516293be4988bba3ec7a841d9d475b3577812198c7',
    '5j/hold5j_magpie.tsv': '1cd67546d67532503d7e48fddce9e4c71f48ec32e267dd5be0cc5ef8bff469ca',
}
ALL = ['5f/dev5f', '5f/final5f', '5g/dev5g', '5g/tune5g', '5g/final5g', '5h/dev5h', '5h/tune5h', '5h/final5h',
       '5i/final5i', '5j/final5j', '5j/hold5j']


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


for p, h in LOCKS.items():
    assert sha(os.path.join(sets, p)) == h, f'{p} does not match its lock'
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)
used, used_idioms, final_idioms = set(), set(), set()
for n in ALL:
    for l in open(os.path.join(sets, n + '_magpie.tsv'), encoding='utf-8'):
        if l.startswith('#') or not l.strip():
            continue
        p = l.rstrip('\n').split('\t')
        used.add(p[3])
        used_idioms.add(p[0])
        if n in ('5f/final5f', '5g/final5g'):
            final_idioms.add(p[0])
devtune_idioms = used_idioms - final_idioms
# random-split part of each (document, sentence, idiom)
split = {}
for line in open(magpie_rand, encoding='utf-8'):
    j = json.loads(line)
    split[(j['document_id'], j['sentence_no'], j['idiom'], tuple(map(tuple, j['offsets'])))] = j['split']


def detok_spans(sent, offsets):
    """Storilex-style detokenised sentence and the idiom's character spans in it."""
    words, starts, pos = [], [], 0
    for w in sent.split(' '):
        words.append(w)
        starts.append(pos)
        pos += len(w) + 1
    gold = {k for k, st in enumerate(starts) for a, b in offsets if st < b and a < st + len(words[k])}
    s = ' '.join(words)
    s = re.sub(r" ([,.;:!?%)])", r"\1", s)
    s = re.sub(r"([(]) ", r"\1", s)
    s = re.sub(r" (n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    s = s.replace('`` ', '"').replace(" ''", '"').replace('``', '"').replace("''", '"')
    spans, at = [], 0
    for k, w in enumerate(words):
        w2 = w.replace('``', '"').replace("''", '"')
        i = s.find(w2, at)
        if i < 0:
            return None, None
        if k in gold:
            spans.append((i, i + len(w2)))
        at = i + len(w2)
    return ' '.join(s.split(' ')) if '  ' not in s else None, spans


pool, stats = {}, {'not_test_split': 0, 'used_idiom': 0, 'used_sentence': 0}
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    idiom, i = j['idiom'], str(j['id'])
    if j['label'] not in ('i', 'l') or not 0.70 <= j['confidence'] <= 1.0:
        continue
    if idiom not in dict_phr or idiom in KNOWN or i in KNOWN_IDS:
        continue
    if (idiom in used_idioms) if TYPE_DISJOINT else (idiom not in final_idioms):
        stats['used_idiom'] += 1
        continue
    if i in used:
        stats['used_sentence'] += 1
        continue
    sp = split.get((j['document_id'], j['sentence_no'], idiom, tuple(map(tuple, j['offsets']))))
    if sp != 'test':
        stats['not_test_split'] += 1
        continue
    s, spans = detok_spans(j['context'][2], j['offsets'])
    if s is None or not spans or not 5 <= len(s.split()) <= 40 or '\t' in s:
        continue
    pool.setdefault(idiom, []).append((i, j['label'], s, ','.join(f'{a}:{b}' for a, b in spans), j['variant_type'], f"{j['confidence']:.3f}"))

rnd = random.Random(SEED)
rows = []
for idiom in sorted(pool):
    picks = sorted(pool[idiom])
    rnd.shuffle(picks)
    for i, lab, s, sp, vt, conf in picks[:CAP]:
        rows.append((idiom, lab, dict_phr[idiom], i, s, sp, vt, conf))
p = os.path.join(out, 'typedisjoint5k_magpie.tsv' if TYPE_DISJOINT else 'final5k_magpie.tsv')
with open(p, 'w', encoding='utf-8') as f:
    f.write(f'# Task 5K final5k (MAGPIE random-split test part, type-disjoint, seed {SEED}). BNC text: LOCAL ONLY. '
            'Columns: idiom, label, dict category, MAGPIE id, sentence, idiom spans, variant type, confidence\n')
    for r in rows:
        f.write('\t'.join(r) + '\n')
ids = {r[3] for r in rows}
print('final5k', {l: sum(1 for r in rows if r[1] == l) for l in 'il'}, 'idioms', len({r[0] for r in rows}),
      'cats', {c: sum(1 for r in rows if r[2] == c) for c in sorted({r[2] for r in rows})})
print('sentences in an earlier set:', len(ids & used), '| idioms in an earlier final:', len({r[0] for r in rows} & final_idioms),
      '| idioms in 5H dev/tune or 5J hold:', len({r[0] for r in rows} & devtune_idioms), stats)
print('sha256', sha(p))
json.dump({'inputs': {'MAGPIE_unfiltered.jsonl': sha(magpie), 'MAGPIE_filtered_split_random.jsonl': sha(magpie_rand),
                      'dict.db': sha(dbp), **LOCKS}, 'seed': SEED, 'cap': CAP, 'outputs': {'final5k_magpie.tsv': sha(p)}},
          open(os.path.join(out, 'MANIFEST_5k.json'), 'w'), indent=1)

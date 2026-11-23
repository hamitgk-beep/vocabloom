"""Task 5H: development, tuning and FINAL sets (empty Turkish meanings, idiom variants).

usage: python3 -I tools/nlp_research_5h/build_sets_5h.py assets/dict.db MAGPIE_unfiltered.jsonl SETS5F_DIR SETS5G_DIR OUT_DIR

Source: MAGPIE (Haagsma, Bos, Nissim 2020). Labels CC BY 4.0 (crowd annotators, people); sentences mostly BNC,
whose text may not be redistributed: the sets are LOCAL ONLY and never committed. Only SHA-256 hashes are
committed (final5h_LOCKED.sha256), the final hash written before any system ran on it.

SETS5F_DIR / SETS5G_DIR: the 5F and 5G sets rebuilt with their own scripts; their final hashes are checked here.

Independence
  * FINAL sentences: never in any earlier set. Agreement 0.70-0.99 only (agreement 1.0 sentences were drawn by
    5A/5B/5E, whose lists are local only), and not in the 5F dev/final or the 5G dev/tune/final sets.
  * FINAL idioms: the 5F/5G final idioms. They were only ever measured (5F once, 5G once), never used to design or
    tune anything. Development and tuning use the OTHER idioms only, so no idiom is in both. Idiom TYPES were seen
    by earlier tasks; MAGPIE has no idiom of the dictionary that no earlier task used (reported as a limit).
  * The three 5E regression sentences (MAGPIE ids 51620, 32520, 50299) are in no set.
Dev / tune split: by idiom (sha256 of "5H|" + idiom): 2/3 dev, 1/3 tune. Dev and tune may reuse sentences of the
5G dev/tune sets and agreement-1.0 sentences (development only).
Caps: final at most 4 sentences per idiom and label; dev/tune at most 8. Sentences of 5-40 words; idiom in
dict.db's expr table.
"""
import hashlib, json, os, random, re, sqlite3, sys

dbp, magpie, sets5f, sets5g, out = sys.argv[1:6]
os.makedirs(out, exist_ok=True)
SEED = 20261123
KNOWN = {'circle the wagons', 'poacher turned gamekeeper', "she'll be right"}
KNOWN_IDS = {'51620', '32520', '50299'}
LOCKS = {
    os.path.join(sets5f, 'final5f_magpie.tsv'): '6874e6501b4b42aa88349601b0ff0f5efa06b518be25521298a79a8bc592b38a',
    os.path.join(sets5g, 'final5g_magpie.tsv'): 'ce55c3bb456d41ec60dcfec18bb5a9fe3d93985c882f5856f2bc2983c6faea60',
}


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


for p, h in LOCKS.items():
    assert sha(p) == h, f'{p} does not match its lock'
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)

used, final_idioms = set(), set()
for d, names in ((sets5f, ('dev5f', 'final5f')), (sets5g, ('dev5g', 'tune5g', 'final5g'))):
    for n in names:
        for l in open(os.path.join(d, f'{n}_magpie.tsv'), encoding='utf-8'):
            if l.startswith('#') or not l.strip():
                continue
            p = l.rstrip('\n').split('\t')
            used.add(p[3])
            if n.startswith('final'):
                final_idioms.add(p[0])


def detok(words):
    s = ' '.join(words)
    s = re.sub(r" ([,.;:!?%)])", r"\1", s)
    s = re.sub(r"([(]) ", r"\1", s)
    s = re.sub(r" (n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    return s.replace('`` ', '"').replace(" ''", '"').replace('``', '"').replace("''", '"')


final_pool, dev_pool = {}, {}
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    idiom, i = j['idiom'], str(j['id'])
    if j['label'] not in ('i', 'l') or j['confidence'] < 0.70 or idiom not in dict_phr or idiom in KNOWN or i in KNOWN_IDS:
        continue
    s = ' '.join(detok(j['context'][2].split(' ')).split())
    if not 5 <= len(s.split()) <= 40:
        continue
    row = (i, s, j['variant_type'], f"{j['confidence']:.3f}")
    if idiom in final_idioms:
        if j['confidence'] < 1.0 and i not in used:
            final_pool.setdefault((idiom, j['label']), []).append(row)
    else:
        dev_pool.setdefault((idiom, j['label']), []).append(row)

rnd = random.Random(SEED)
parts = {'dev': [], 'tune': [], 'final': []}
for pool, cap, name in ((dev_pool, 8, None), (final_pool, 4, 'final')):
    for (idiom, label) in sorted(pool):
        part = name or ('tune' if int(hashlib.sha256(('5H|' + idiom).encode()).hexdigest(), 16) % 3 == 0 else 'dev')
        picks = sorted(pool[(idiom, label)])
        rnd.shuffle(picks)
        for i, s, vt, conf in picks[:cap]:
            parts[part].append((idiom, label, dict_phr[idiom], i, s, vt, conf))
manifest = {'inputs': {'MAGPIE_unfiltered.jsonl': sha(magpie), 'dict.db': sha(dbp), **{os.path.basename(k): v for k, v in LOCKS.items()}}, 'outputs': {}}
for part, rows in parts.items():
    p = os.path.join(out, f'{part}5h_magpie.tsv')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(f'# Task 5H {part.upper()} set (MAGPIE, seed {SEED}). BNC text: LOCAL ONLY. '
                'Columns: idiom, label, dict category, MAGPIE id, sentence, variant type, annotator confidence\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    manifest['outputs'][os.path.basename(p)] = sha(p)
    print(part, {l: sum(1 for r in rows if r[1] == l) for l in 'il'}, 'idioms', len({r[0] for r in rows}))
ids = {part: {r[3] for r in rows} for part, rows in parts.items()}
idi = {part: {r[0] for r in rows} for part, rows in parts.items()}
print('final sentences in 5F/5G sets:', len(ids['final'] & used), '| final idioms in dev/tune:', len(idi['final'] & (idi['dev'] | idi['tune'])),
      '| dev-tune idiom overlap:', len(idi['dev'] & idi['tune']))
json.dump(manifest, open(os.path.join(out, 'MANIFEST.json'), 'w'), indent=1)

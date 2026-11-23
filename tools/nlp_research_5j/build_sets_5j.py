"""Task 5J: the FINAL set (word cards inside idioms) and a second held-out set, plus the 5H dev/tune sets reused.

usage: python3 -I tools/nlp_research_5j/build_sets_5j.py assets/dict.db MAGPIE_unfiltered.jsonl SETS5F SETS5G SETS5H SETS5I OUT_DIR

Source: MAGPIE (Haagsma, Bos, Nissim 2020). Labels CC BY 4.0 (crowd annotators, people); sentences mostly BNC,
whose text may not be redistributed: the sets are LOCAL ONLY and never committed. Only SHA-256 hashes are
committed (final5j_LOCKED.sha256), written before any system ran on these sets.

SETS5F..5I: the earlier sets rebuilt with their own scripts; their hashes are checked here.

Independence
  * Both new sets: sentences in NO earlier set (5F dev/final, 5G dev/tune/final, 5H dev/tune/final, 5I final).
    Agreement 0.70-0.99 only (agreement-1.0 sentences were drawn by 5A/5B/5E, whose lists are local only).
  * final5j: idioms of the 5F/5G finals (= 5H/5I final idioms); never in 5H dev/tune, which 5J develops on.
    These idiom TYPES were measured (never tuned on) by 5F-5I: a new-sentence set, not a new-idiom set.
  * hold5j: idioms of 5H dev/tune (tuned on by 5H/5I and by this task's development): new sentences only;
    reported apart, never used to choose.
  * The three 5E regression sentences (MAGPIE ids 51620, 32520, 50299) are in no set.
Caps: at most 8 sentences per idiom and label; sentences of 5-40 words; idiom in dict.db's expr table.
"""
import hashlib, json, os, random, re, shutil, sys

dbp, magpie, s5f, s5g, s5h, s5i, out = sys.argv[1:8]
os.makedirs(out, exist_ok=True)
SEED = 20261125
CAP = 8
KNOWN = {'circle the wagons', 'poacher turned gamekeeper', "she'll be right"}
KNOWN_IDS = {'51620', '32520', '50299'}
LOCKS = {
    os.path.join(s5f, 'final5f_magpie.tsv'): '6874e6501b4b42aa88349601b0ff0f5efa06b518be25521298a79a8bc592b38a',
    os.path.join(s5g, 'final5g_magpie.tsv'): 'ce55c3bb456d41ec60dcfec18bb5a9fe3d93985c882f5856f2bc2983c6faea60',
    os.path.join(s5h, 'dev5h_magpie.tsv'): '5e81b1beb5a11cb1e656d057d5dcbcf50cf1cf90213e918e18d5cdaab21829cd',
    os.path.join(s5h, 'tune5h_magpie.tsv'): '197f7faf2a76fe7675ecb083e752b59c433f88ff005a422731209e4d40b20707',
    os.path.join(s5h, 'final5h_magpie.tsv'): 'd479d256a72bc4bffb4d77f210dda711517d96230fd616453e88da99dd88e22c',
    os.path.join(s5i, 'final5i_magpie.tsv'): 'a50d77ca95384f9e83098b95f7923180f2865d15e9b03d2d3dbb51e3f8b446a0',
}


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


for p, h in LOCKS.items():
    assert sha(p) == h, f'{p} does not match its lock'
import sqlite3
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)

used, final_idioms, devtune_idioms = set(), set(), set()
for d, names in ((s5f, ('dev5f', 'final5f')), (s5g, ('dev5g', 'tune5g', 'final5g')), (s5h, ('dev5h', 'tune5h', 'final5h')), (s5i, ('final5i',))):
    for n in names:
        for l in open(os.path.join(d, f'{n}_magpie.tsv'), encoding='utf-8'):
            if l.startswith('#') or not l.strip():
                continue
            p = l.rstrip('\n').split('\t')
            used.add(p[3])
            if n in ('final5f', 'final5g'):
                final_idioms.add(p[0])
            if n in ('dev5h', 'tune5h'):
                devtune_idioms.add(p[0])
assert not final_idioms & devtune_idioms


def detok(words):
    s = ' '.join(words)
    s = re.sub(r" ([,.;:!?%)])", r"\1", s)
    s = re.sub(r"([(]) ", r"\1", s)
    s = re.sub(r" (n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    return s.replace('`` ', '"').replace(" ''", '"').replace('``', '"').replace("''", '"')


pools = {'final5j': {}, 'hold5j': {}}
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    idiom, i = j['idiom'], str(j['id'])
    if j['label'] not in ('i', 'l') or not 0.70 <= j['confidence'] < 1.0:
        continue
    if idiom not in dict_phr or idiom in KNOWN or i in KNOWN_IDS or i in used:
        continue
    name = 'final5j' if idiom in final_idioms else 'hold5j' if idiom in devtune_idioms else None
    if name is None:
        continue
    s = ' '.join(detok(j['context'][2].split(' ')).split())
    if not 5 <= len(s.split()) <= 40:
        continue
    pools[name].setdefault((idiom, j['label']), []).append((i, s, j['variant_type'], f"{j['confidence']:.3f}"))

manifest = {'inputs': {'MAGPIE_unfiltered.jsonl': sha(magpie), 'dict.db': sha(dbp), **{os.path.basename(k): v for k, v in LOCKS.items()}},
            'outputs': {}, 'seed': SEED}
rnd = random.Random(SEED)
for name in ('final5j', 'hold5j'):
    rows = []
    pool = pools[name]
    for (idiom, label) in sorted(pool):
        picks = sorted(pool[(idiom, label)])
        rnd.shuffle(picks)
        for i, s, vt, conf in picks[:CAP]:
            rows.append((idiom, label, dict_phr[idiom], i, s, vt, conf))
    p = os.path.join(out, f'{name}_magpie.tsv')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(f'# Task 5J {name} set (MAGPIE, seed {SEED}). BNC text: LOCAL ONLY. '
                'Columns: idiom, label, dict category, MAGPIE id, sentence, variant type, annotator confidence\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    manifest['outputs'][f'{name}_magpie.tsv'] = sha(p)
    ids = {r[3] for r in rows}
    print(name, {l: sum(1 for r in rows if r[1] == l) for l in 'il'}, 'idioms', len({r[0] for r in rows}),
          '| sentences in any earlier set:', len(ids & used),
          '| idioms in 5H dev/tune:', len({r[0] for r in rows} & devtune_idioms))
    print('sha256', sha(p))
for n in ('dev5h', 'tune5h'):
    shutil.copyfile(os.path.join(s5h, f'{n}_magpie.tsv'), os.path.join(out, f'{n}_magpie.tsv'))
json.dump(manifest, open(os.path.join(out, 'MANIFEST.json'), 'w'), indent=1)

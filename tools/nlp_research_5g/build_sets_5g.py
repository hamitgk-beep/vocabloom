"""Task 5G: development, tuning and FINAL sets for "idiom or literal here".

usage: python3 -I tools/nlp_research_5g/build_sets_5g.py assets/dict.db MAGPIE_unfiltered.jsonl SETS5F_DIR OUT_DIR

Source: MAGPIE (Haagsma, Bos, Nissim 2020). Labels CC BY 4.0 (crowd annotators, people); sentences mostly BNC,
whose text may not be redistributed: the sets are LOCAL ONLY and never committed. Only SHA-256 hashes are
committed (final5g_LOCKED.sha256, MANIFEST in the report), the final hash written before any system ran on it.

SETS5F_DIR: the 5F sets rebuilt with tools/nlp_research_5f/build_sets_5f.py (dev5f_magpie.tsv, final5f_magpie.tsv;
the final must hash to tools/nlp_research_5f/final5f_LOCKED.sha256, checked here).

Independence
  * Sentences: no sentence of an earlier set is in the 5G FINAL. Earlier draws took agreement-1.0 sentences
    (5A/5B/5E) and, in 5F, at most 2 sentences per idiom and label with agreement 0.70-0.99. The 5G final takes only
    agreement 0.70-0.99 sentences that 5F did not take.
  * Idioms: the 5G final idioms are the 5F FINAL idioms (only measured once in 5F, never used to design or tune
    anything). Development and tuning use the OTHER idioms only (the 5F dev idioms), with all their MAGPIE
    sentences (agreement >= 0.70, also agreement 1.0, i.e. "seen" sentences: allowed for development). So no idiom
    is in both development/tuning and final. Idiom TYPES of 5A/5B/5E sets can be in the final (their lists are
    local only); that is reported as a limit.
  * The three 5E idioms (MAGPIE ids 51620, 32520, 50299) are regression cases: never in any 5G set.
Dev / tune split: by idiom (sha256 of "5G|" + idiom): 2/3 dev (rules, diagnosis, classifier training), 1/3 tune
(choosing among candidates and thresholds). Caps: final at most 3 sentences per idiom and label; dev/tune at most 6.
Sentences of 5-40 words; idiom in dict.db's expr table.
"""
import hashlib, json, os, random, re, sqlite3, sys

dbp, magpie, sets5f, out = sys.argv[1:5]
os.makedirs(out, exist_ok=True)
SEED = 20261124
KNOWN = {'circle the wagons', 'poacher turned gamekeeper', "she'll be right"}
KNOWN_IDS = {'51620', '32520', '50299'}
LOCK5F = '6874e6501b4b42aa88349601b0ff0f5efa06b518be25521298a79a8bc592b38a'


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


assert sha(os.path.join(sets5f, 'final5f_magpie.tsv')) == LOCK5F, '5F final does not match its lock'
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)

used5f, idioms5f = set(), {'dev': set(), 'final': set()}
for part in ('dev', 'final'):
    for l in open(os.path.join(sets5f, f'{part}5f_magpie.tsv'), encoding='utf-8'):
        if l.startswith('#') or not l.strip():
            continue
        p = l.rstrip('\n').split('\t')
        used5f.add(p[3])
        idioms5f[part].add(p[0])


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
    if idiom in idioms5f['final']:
        if j['confidence'] < 1.0 and i not in used5f:
            final_pool.setdefault((idiom, j['label']), []).append(row)
    elif idiom not in idioms5f['final']:
        dev_pool.setdefault((idiom, j['label']), []).append(row)

rnd = random.Random(SEED)
parts = {'dev': [], 'tune': [], 'final': []}
for pool, cap, name in ((dev_pool, 6, None), (final_pool, 3, 'final')):
    for (idiom, label) in sorted(pool):
        part = name or ('tune' if int(hashlib.sha256(('5G|' + idiom).encode()).hexdigest(), 16) % 3 == 0 else 'dev')
        picks = sorted(pool[(idiom, label)])
        rnd.shuffle(picks)
        for i, s, vt, conf in picks[:cap]:
            parts[part].append((idiom, label, dict_phr[idiom], i, s, vt, conf))
manifest = {'inputs': {'MAGPIE_unfiltered.jsonl': sha(magpie), 'dict.db': sha(dbp), 'final5f_magpie.tsv': LOCK5F}, 'outputs': {}}
for part, rows in parts.items():
    p = os.path.join(out, f'{part}5g_magpie.tsv')
    with open(p, 'w', encoding='utf-8') as f:
        f.write(f'# Task 5G {part.upper()} set (MAGPIE, seed {SEED}). BNC text: LOCAL ONLY. '
                'Columns: idiom, label, dict category, MAGPIE id, sentence, variant type, annotator confidence\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    manifest['outputs'][os.path.basename(p)] = sha(p)
    print(part, {l: sum(1 for r in rows if r[1] == l) for l in 'il'}, 'idioms', len({r[0] for r in rows}))
ids = {part: {r[3] for r in rows} for part, rows in parts.items()}
idi = {part: {r[0] for r in rows} for part, rows in parts.items()}
print('final sentences in 5F sets:', len(ids['final'] & used5f), '| final idioms in dev/tune:', len(idi['final'] & (idi['dev'] | idi['tune'])),
      '| dev-tune idiom overlap:', len(idi['dev'] & idi['tune']))
json.dump(manifest, open(os.path.join(out, 'MANIFEST.json'), 'w'), indent=1)

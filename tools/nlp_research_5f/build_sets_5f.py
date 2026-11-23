"""Task 5F: development and FINAL sets for "idiom or literal, and how sure".

usage: python3 -I tools/nlp_research_5f/build_sets_5f.py assets/dict.db MAGPIE_unfiltered.jsonl OUT_DIR

Source: MAGPIE (Haagsma, Bos, Nissim 2020). Labels CC BY 4.0, crowd-annotated by people; sentences mostly BNC,
so the sets are LOCAL ONLY and never committed. Only the SHA-256 of the final set is committed
(final5f_LOCKED.sha256), written before any system is run on it.

Independence from earlier sets: every earlier draw (tools/eval/build_sense_eval.py, build_holdout.py,
build_final.py, Task 5E build_final_5e.py) took only sentences with annotator agreement 1.0. These sets take
only sentences with a clear majority label but agreement below 1.0 (0.70 <= confidence < 1.0), so no sentence of an
earlier set can be here. An idiom TYPE of an earlier set can be (the earlier idiom lists are local only and
cannot be rebuilt exactly here); that is reported, and the 5F rule has no threshold tuned on any of these sets.

Dev / final split: by idiom (sha256 of the idiom), so no idiom has sentences in both. The three idioms of the 5E
finding (circle the wagons, poacher turned gamekeeper, she'll be right) are kept out of the final set: they are
regression cases (test/idiom_confidence_5f_test.dart), not test data.
At most 2 sentences per idiom and label; sentences of 5-40 words; idiom in dict.db's expr table.
"""
import hashlib, json, random, re, sqlite3, sys

dbp, magpie, out = sys.argv[1:4]
SEED = 20261123
KNOWN = {'circle the wagons', 'poacher turned gamekeeper', "she'll be right"}
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)


def detok(words):
    s = ' '.join(words)
    s = re.sub(r" ([,.;:!?%)])", r"\1", s)
    s = re.sub(r"([(]) ", r"\1", s)
    s = re.sub(r" (n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    return s.replace('`` ', '"').replace(" ''", '"').replace('``', '"').replace("''", '"')


pool = {}
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    if j['label'] not in ('i', 'l') or not 0.70 <= j['confidence'] < 1.0 or j['idiom'] not in dict_phr:
        continue
    s = ' '.join(detok(j['context'][2].split(' ')).split())
    if not 5 <= len(s.split()) <= 40:
        continue
    pool.setdefault((j['idiom'], j['label']), []).append((str(j['id']), s, j['variant_type'], f"{j['confidence']:.3f}"))

rnd = random.Random(SEED)
parts = {'dev': [], 'final': []}
for (idiom, label) in sorted(pool):
    part = 'dev' if idiom in KNOWN or int(hashlib.sha256(idiom.encode()).hexdigest(), 16) % 3 == 0 else 'final'
    picks = sorted(pool[(idiom, label)])
    rnd.shuffle(picks)
    for i, s, vt, conf in picks[:2]:
        parts[part].append((idiom, label, dict_phr[idiom], i, s, vt, conf))
for part, rows in parts.items():
    with open(f'{out}/{part}5f_magpie.tsv', 'w', encoding='utf-8') as f:
        f.write(f'# Task 5F {part.upper()} set (MAGPIE, agreement 0.70-0.99, seed {SEED}). BNC text: LOCAL ONLY. '
                'Columns: idiom, label, dict category, MAGPIE id, sentence, variant type, annotator confidence\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    print(part, {l: sum(1 for r in rows if r[1] == l) for l in 'il'}, 'idioms', len({r[0] for r in rows}))
dev_i = {r[0] for r in parts['dev']}
fin_i = {r[0] for r in parts['final']}
print('idioms in both', len(dev_i & fin_i))

# Optional (4th argument "seen"): every agreement-1.0 sentence of a dictionary idiom, the pool every earlier set
# was drawn from (so "seen" data). Only for counting how often an error happens at all; no choice is made on it.
if len(sys.argv) > 4 and sys.argv[4] == 'seen':
    n = 0
    with open(f'{out}/seen5f_conf1.tsv', 'w', encoding='utf-8') as f:
        f.write('# Task 5F: all MAGPIE agreement-1.0 sentences of dict.db idioms (pool of the earlier sets; SEEN). LOCAL ONLY. '
                'Same columns as dev5f_magpie.tsv\n')
        for line in open(magpie, encoding='utf-8'):
            j = json.loads(line)
            if j['label'] not in ('i', 'l') or j['confidence'] != 1.0 or j['idiom'] not in dict_phr:
                continue
            s = ' '.join(detok(j['context'][2].split(' ')).split())
            if not 5 <= len(s.split()) <= 40:
                continue
            f.write('\t'.join((j['idiom'], j['label'], dict_phr[j['idiom']], str(j['id']), s, j['variant_type'], '1.000')) + '\n')
            n += 1
    print('seen pool', n)

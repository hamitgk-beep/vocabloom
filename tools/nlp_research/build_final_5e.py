"""Builds the Task 5E FINAL test sets. Drawn before any Task 5E model or rule was run, never used for tuning.

usage: python3 -I tools/nlp_research/build_final_5e.py assets/dict.db NLTK_DATA_DIR WSD_EVAL_DIR MAGPIE_unfiltered.jsonl PREV_DIR OUT_DIR

PREV_DIR holds every earlier draw (tools/eval/build_sense_eval.py, build_holdout.py, build_final.py). Everything in
them is "seen": their words, their MAGPIE sentences and their idioms are left out here.

  * final5e_wsd.tsv: English all-words WSD gold from the Raganato et al. (2017) unified evaluation framework,
    Senseval-2, Senseval-3, SemEval-2013 and SemEval-2015 (WordNet 3.0 keys). These are NOT SemCor texts, so models
    fine-tuned on SemCor are not tested on their training sentences. SemEval-2007 is left out: it is the usual
    development set of WSD models, and it is our development set too (dev5e_wsd_se07.tsv).
    One row per lemma, lemmas of all earlier draws left out, fixed seed and quotas by part of speech.
    Licence: research data of the Senseval/SemEval tasks; LOCAL ONLY, never committed.
  * final5e_magpie.tsv: MAGPIE (labels CC BY 4.0; sentences mostly BNC: LOCAL ONLY, never committed).
    Only idioms that are in NO earlier draw (type-unseen), annotator agreement 1.0, every variant type
    (identical, inflection, insertion, ...), at most 2 sentences per idiom and label.
    Any idiom classifier trained in Task 5E must leave these idioms out entirely (final5e_magpie_idioms.txt).
  * final5e_pos.jsonl (optional 7th argument, a folder with en_pud-ud-test.conllu and en_gentle-ud-test.conllu):
    English part of speech and base forms, UD English-PUD (CC BY-SA 3.0) and GENTLE (CC BY-NC-SA 4.0), treebanks
    never used before in this project and outside spaCy's training data (OntoNotes). LOCAL ONLY. text_eval format,
    one document a line.
A MANIFEST.json with the SHA-256 of every input and output is written next to the sets.
"""
import glob, hashlib, json, os, random, re, sqlite3, sys
import xml.etree.ElementTree as ET

dbp, nltk_dir, wsd_dir, magpie, prev, out = sys.argv[1:7]
ud_new = sys.argv[7] if len(sys.argv) > 7 else None
os.makedirs(out, exist_ok=True)
repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
import nltk
nltk.data.path.insert(0, nltk_dir)
from nltk.corpus import wordnet as wn

SEED = 20261122 + 5000
QUOTA = {'n': 220, 'v': 170, 'a': 110, 'r': 50}
UPOS = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'}


def rows_of(path):
    return [l.rstrip('\n').split('\t') for l in open(path, encoding='utf-8') if not l.startswith('#') and l.strip()]


used = set()
for f in ('sense_eval_semcor.tsv', 'sense_eval_semcor_dev.tsv', 'sense_eval_semcor_fresh.tsv'):
    used |= {r[0] for r in rows_of(os.path.join(repo, 'test', 'data', f))}
for f in ('holdout_semcor.tsv', 'final_semcor.tsv'):
    used |= {r[0] for r in rows_of(os.path.join(prev, f))}
used |= {'course', 'still', 'bank', 'book', 'through', 'want', 'raise', 'goal', 'delicious', 'recommend', 'simply', 'class', 'stop',
         'break', 'ice', 'spill', 'bean', 'board', 'flow'}

syn = {}
for i, pos, gloss, tr in db.execute('SELECT id, pos, gloss, tr FROM syn'):
    syn[('a' if pos == 's' else pos, gloss)] = (i, json.loads(tr) if tr else [])
freq = {w for (w,) in db.execute('SELECT word FROM wfreq')}


def detok(words):
    s = ' '.join(words)
    s = re.sub(r" ([,.;:!?%)])", r"\1", s)
    s = re.sub(r"([(]) ", r"\1", s)
    s = re.sub(r" (n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    return s.replace('`` ', '"').replace(" ''", '"').replace('``', '"').replace("''", '"')


def wsd_rows(name):
    gold = {}
    for l in open(f'{wsd_dir}/{name}.gold.key.txt', encoding='utf-8'):
        p = l.split()
        gold[p[0]] = p[1:]
    root = ET.parse(f'{wsd_dir}/{name}.data.xml').getroot()
    for s in root.iter('sentence'):
        toks = list(s)
        words = [t.text for t in toks]
        if not 6 <= len(words) <= 40:
            continue
        text = ' '.join(detok(words).split())
        for k, t in enumerate(toks):
            if t.tag != 'instance':
                continue
            pos = UPOS.get(t.get('pos'))
            lemma = t.get('lemma').lower()
            if pos is None or not lemma.isalpha() or len(lemma) < 3 or lemma not in freq or lemma in used:
                continue
            if sum(1 for w in words if w.lower() == words[k].lower()) != 1:
                continue
            if len(wn.synsets(lemma, pos)) < 2:
                continue
            ids, trs = [], []
            for key in gold[t.get('id')]:
                try:
                    ss = wn.lemma_from_key(key).synset()
                except Exception:
                    continue
                hit = syn.get((pos, ss.definition()))
                if hit:
                    ids.append(str(hit[0]))
                    trs.extend(hit[1])
            if not ids:
                continue
            yield lemma, pos, ';'.join(ids), '; '.join(dict.fromkeys(trs)), text, f'{name}:{t.get("id")}'


cands = {p: {} for p in QUOTA}
for name in ('senseval2', 'senseval3', 'semeval2013', 'semeval2015'):
    for r in wsd_rows(name):
        cands[r[1]].setdefault(r[0], []).append(r)
rnd = random.Random(SEED)
rows = []
for pos, n in QUOTA.items():
    names = sorted(cands[pos])
    rnd.shuffle(names)
    for name in names[:n]:
        rows.append(rnd.choice(sorted(cands[pos][name])))
with open(f'{out}/final5e_wsd.tsv', 'w', encoding='utf-8') as f:
    f.write(f'# Task 5E FINAL WSD set (Senseval-2/3, SemEval-2013/15; Raganato et al. 2017), seed {SEED}; LOCAL ONLY. '
            'Columns: lemma, pos, gold dict.db synset ids (;), KeNet Turkish (may be empty), sentence, source\n')
    for r in rows:
        f.write('\t'.join(r) + '\n')
print('wsd final', len(rows), {p: sum(1 for r in rows if r[1] == p) for p in QUOTA}, 'with KeNet Turkish', sum(1 for r in rows if r[3]))

# Development set for WSD models: SemEval-2007 (any lemma, one row per lemma).
dev = {}
for r in wsd_rows('semeval2007'):
    dev.setdefault(r[0], r)
with open(f'{out}/dev5e_wsd_se07.tsv', 'w', encoding='utf-8') as f:
    f.write('# Task 5E DEVELOPMENT WSD set: SemEval-2007 (Raganato et al. 2017); LOCAL ONLY. Same columns as final5e_wsd.tsv\n')
    for r in dev.values():
        f.write('\t'.join(r) + '\n')
print('wsd dev (se07)', len(dev))

# MAGPIE: type-unseen idioms only.
seen_idioms, seen_ids = set(), set()
for f in glob.glob(f'{prev}/sense_eval_magpie_*.tsv'):
    for r in rows_of(f):
        seen_idioms.add(r[0]); seen_ids.add(r[2])
for f in ('holdout_magpie.tsv', 'final_magpie.tsv'):
    for r in rows_of(f'{prev}/{f}'):
        seen_idioms.add(r[0]); seen_ids.add(r[3])
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)
A = {'i': {}, 'l': {}}
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    if j['confidence'] != 1.0 or j['label'] not in A or j['idiom'] not in dict_phr or j['idiom'] in seen_idioms:
        continue
    if str(j['id']) in seen_ids:
        continue
    s = ' '.join(detok(j['context'][2].split(' ')).split())  # one line: a few MAGPIE sentences hold a line break
    if not 5 <= len(s.split()) <= 40:
        continue
    A[j['label']].setdefault(j['idiom'], []).append((s, j['id'], j['variant_type']))
rnd = random.Random(SEED + 1)
mrows = []
for label in ('i', 'l'):
    names = sorted(A[label])
    rnd.shuffle(names)
    for name in names:
        picks = sorted(A[label][name])
        rnd.shuffle(picks)
        for s, i, vt in picks[:2]:
            mrows.append((name, label, dict_phr[name], str(i), s, vt))
# Balance: as many idiomatic as literal sentences (literal is the scarce label).
lit = [r for r in mrows if r[1] == 'l']
idi = [r for r in mrows if r[1] == 'i']
rnd.shuffle(idi)
idi = idi[:max(len(lit), 300)]
mrows = sorted(lit + idi, key=lambda r: (r[0], r[1], r[3]))
with open(f'{out}/final5e_magpie.tsv', 'w', encoding='utf-8') as f:
    f.write('# Task 5E MAGPIE FINAL: type-unseen idioms, agreement 1.0, all variant types. BNC text: LOCAL ONLY. '
            'Columns: idiom, label, dict category, MAGPIE id, sentence, variant type\n')
    for r in mrows:
        f.write('\t'.join(r) + '\n')
with open(f'{out}/final5e_magpie_idioms.txt', 'w', encoding='utf-8') as f:
    f.write('\n'.join(sorted({r[0] for r in mrows})) + '\n')
print('magpie final', {l: sum(1 for r in mrows if r[1] == l) for l in 'il'}, 'idioms', len({r[0] for r in mrows}))


outs_pos = []
if ud_new:
    import importlib.util
    spec = importlib.util.spec_from_file_location('bte', os.path.join(repo, 'tools', 'eval', 'build_text_eval.py'))
    bte = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bte)
    with open(f'{out}/final5e_pos.jsonl', 'w', encoding='utf-8') as f:
        n = 0
        for tb in ('en_pud-ud-test.conllu', 'en_gentle-ud-test.conllu'):
            for para in bte.paragraphs(os.path.join(ud_new, tb)):
                para['genre'] = tb.split('-')[0]
                f.write(json.dumps(para, ensure_ascii=False) + '\n')
                n += 1
    print('pos final documents', n)
    outs_pos = ['final5e_pos.jsonl']


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


ins = [magpie, dbp] + sorted(glob.glob(f'{wsd_dir}/*.xml')) + sorted(glob.glob(f'{wsd_dir}/*.txt')) + (sorted(glob.glob(f'{ud_new}/*.conllu')) if ud_new else [])
outs = ['final5e_wsd.tsv', 'dev5e_wsd_se07.tsv', 'final5e_magpie.tsv', 'final5e_magpie_idioms.txt'] + outs_pos
json.dump({'built_by': 'tools/nlp_research/build_final_5e.py', 'seed': SEED,
           'licences': {'Senseval/SemEval (Raganato 2017 framework)': 'research data, local only',
                        'MAGPIE': 'labels CC BY 4.0; BNC text not redistributable'},
           'inputs': {os.path.basename(p): sha(p) for p in ins},
           'outputs': {p: sha(f'{out}/{p}') for p in outs}},
          open(f'{out}/MANIFEST_5e.json', 'w'), indent=1)

"""Builds the Task 5B FINAL test sets: drawn before any Task 5B change was measured, never used for tuning.

usage: python3 -I tools/eval/build_final.py assets/dict.db NLTK_DATA_DIR MAGPIE_unfiltered.jsonl UD_DIR PREV_DIR OUT_DIR

PREV_DIR holds every earlier draw: sense_eval_magpie_{dev,fresh,fresh2}.tsv (tools/eval/build_sense_eval.py) and
holdout_semcor.tsv / holdout_magpie.tsv (tools/eval/build_holdout.py, Task 5A). Everything in them is "seen".

What is new here, and where it comes from (licence):
  * final_semcor.tsv: SemCor 3.0 words in none of the four earlier SemCor draws, seed 20262022
    (Princeton WordNet/SemCor licence, redistributable with the notice).
  * final_magpie.tsv: MAGPIE (labels CC BY 4.0; sentences mostly BNC: LOCAL ONLY, never committed).
      part A = idioms in no earlier draw (fully unseen);
      part B = literal sentences not drawn before, of idioms that were drawn (sentence unseen, idiom seen):
      reported separately, because MAGPIE has only a few literal idioms left that were never drawn.
  * final_ewt_*.jsonl, text_eval_test.jsonl: UD English-EWT TRAIN split (CC BY-SA 4.0); only dev+test were used before.
  * final_ud_tr.jsonl: UD Turkish BOUN, Kenet and Penn DEV splits (CC BY-SA 4.0); only their test splits were used.
A MANIFEST.json with the SHA-256 of every input and output is written next to the sets.
"""
import glob, hashlib, importlib.util, json, os, random, re, sqlite3, sys

dbp, nltk_dir, magpie, ud, prev, out = sys.argv[1:7]
os.makedirs(out, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
import nltk
nltk.data.path.insert(0, nltk_dir)
from nltk.corpus import semcor, wordnet as wn
from nltk.tree import Tree

SEED = 20261122 + 900
QUOTA = {'n': 120, 'v': 120, 'a': 60, 'r': 40}


def rows_of(path):
    return [l.rstrip('\n').split('\t') for l in open(path, encoding='utf-8') if not l.startswith('#') and l.strip()]


used = set()
for f in ('sense_eval_semcor.tsv', 'sense_eval_semcor_dev.tsv', 'sense_eval_semcor_fresh.tsv'):
    used |= {r[0] for r in rows_of(os.path.join(repo, 'test', 'data', f))}
used |= {r[0] for r in rows_of(os.path.join(prev, 'holdout_semcor.tsv'))}
used |= {'course', 'still', 'bank', 'book', 'through', 'want', 'raise', 'goal', 'delicious', 'recommend', 'simply', 'class', 'stop'}

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


cands = {p: {} for p in QUOTA}
for fid in semcor.fileids():
    for sent in semcor.tagged_sents(fid, tag='sem'):
        words, marks = [], []
        for ch in sent:
            if isinstance(ch, Tree):
                lem = ch.label()
                if hasattr(lem, 'synset') and len(ch.leaves()) == 1:
                    marks.append((len(words), lem))
                words.extend(ch.leaves())
            else:
                words.extend(ch)
        if not 6 <= len(words) <= 24:
            continue
        text = detok(words)
        if '_' in text or not text[0].isupper():
            continue
        for at, lem in marks:
            ss = lem.synset()
            pos = 'a' if ss.pos() == 's' else ss.pos()
            name = lem.name().lower()
            if pos not in QUOTA or name in used or name not in freq or not name.isalpha() or len(name) < 3:
                continue
            if len(wn.synsets(name, ss.pos() if ss.pos() != 's' else 'a')) < 2:
                continue
            hit = syn.get((pos, ss.definition()))
            if not hit or sum(1 for w in words if w.lower() == words[at].lower()) != 1:
                continue
            cands[pos].setdefault(name, []).append((text, hit[0], '; '.join(hit[1]), fid))
rnd = random.Random(SEED)
rows = []
for pos, n in QUOTA.items():
    names = sorted(cands[pos])
    rnd.shuffle(names)
    for name in names[:n]:
        text, sid, tr, fid = rnd.choice(sorted(cands[pos][name]))
        rows.append((name, pos, sid, tr, text, fid))
with open(f'{out}/final_semcor.tsv', 'w', encoding='utf-8') as f:
    f.write(f'# SemCor 3.0 FINAL set for Task 5B, seed {SEED}; words of all earlier draws left out. KeNet Turkish may be empty.\n')
    for r in rows:
        f.write('\t'.join(str(x) for x in r) + '\n')
print('semcor final', len(rows), 'with KeNet Turkish', sum(1 for r in rows if r[3]))

# MAGPIE
seen_idioms, seen_ids = set(), set()
for f in glob.glob(f'{prev}/sense_eval_magpie_*.tsv'):
    for r in rows_of(f):
        seen_idioms.add(r[0])
        seen_ids.add(r[2])
for r in rows_of(f'{prev}/holdout_magpie.tsv'):
    seen_idioms.add(r[0])
    seen_ids.add(r[3])
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)
A = {'i': {}, 'l': {}}
B = {}
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    if j['confidence'] != 1.0 or j['label'] not in A or j['idiom'] not in dict_phr:
        continue
    if j['variant_type'] not in ('identical', 'inflection') or str(j['id']) in seen_ids:
        continue
    s = detok(j['context'][2].split(' '))
    if not 5 <= len(s.split()) <= 30:
        continue
    if j['idiom'] not in seen_idioms:
        A[j['label']].setdefault(j['idiom'], []).append((s, j['id']))
    elif j['label'] == 'l':
        B.setdefault(j['idiom'], []).append((s, j['id']))
rnd = random.Random(SEED + 1)
mrows = []
for label, n in (('i', 150), ('l', 150)):
    names = sorted(A[label])
    rnd.shuffle(names)
    for name in names[:n]:
        s, i = rnd.choice(sorted(A[label][name]))
        mrows.append((name, label, dict_phr[name], i, s, 'A'))
names = sorted(B)
rnd.shuffle(names)
for name in names[:150]:
    s, i = rnd.choice(sorted(B[name]))
    mrows.append((name, 'l', dict_phr[name], i, s, 'B'))
with open(f'{out}/final_magpie.tsv', 'w', encoding='utf-8') as f:
    f.write('# MAGPIE FINAL (Task 5B). BNC text: local only. Columns: idiom, label, dict category, id, sentence, part (A unseen idiom, B unseen sentence of a seen idiom)\n')
    for r in mrows:
        f.write('\t'.join(str(x) for x in r) + '\n')
print('magpie final', {f'{p}{l}': sum(1 for r in mrows if r[5] == p and r[1] == l) for p in 'AB' for l in 'il'})


def conllu(path):
    sent, text = [], None
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('# text ='):
            text = line.split('=', 1)[1].strip()
        elif not line:
            if sent:
                yield text, sent
            sent, text = [], None
        elif not line.startswith('#'):
            c = line.split('\t')
            if '.' in c[0] or '-' in c[0]:
                continue
            sent.append(c)


train = list(conllu(f'{ud}/en_ewt-train.conllu'))
with open(f'{out}/final_ewt_prt.jsonl', 'w', encoding='utf-8') as f:
    g = 0
    for text, sent in train:
        gold = [[sent[int(c[6]) - 1][2].lower(), c[2].lower()] for c in sent if c[7] == 'compound:prt' and sent[int(c[6]) - 1][3] == 'VERB']
        f.write(json.dumps({'text': text, 'gold': gold}, ensure_ascii=False) + '\n')
        g += len(gold)
    print('ewt train sentences', len(train), 'gold verb+particle', g)
with open(f'{out}/final_ewt_propn.jsonl', 'w', encoding='utf-8') as f:
    for text, sent in train:
        pr = [c[1] for c in sent[1:] if c[3] == 'PROPN' and c[1][:1].isupper() and c[1].isalpha()]
        if pr and text:
            f.write(json.dumps({'text': text, 'propn': pr}, ensure_ascii=False) + '\n')

spec = importlib.util.spec_from_file_location('bte', os.path.join(here, 'build_text_eval.py'))
bte = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bte)
paras = bte.paragraphs(f'{ud}/en_ewt-train.conllu')
os.makedirs(f'{out}/text', exist_ok=True)
with open(f'{out}/text/text_eval_test.jsonl', 'w', encoding='utf-8') as f:
    for p in paras:
        f.write(json.dumps(p, ensure_ascii=False) + '\n')
print('ewt train paragraphs', len(paras))

with open(f'{out}/final_ud_tr.jsonl', 'w', encoding='utf-8') as f:
    for tb in ('boun', 'kenet', 'penn'):
        n = t = 0
        for text, sent in conllu(f'{ud}/tr_{tb}-dev.conllu'):
            toks = [[c[1], c[2], c[3]] for c in sent if c[3] in ('NOUN', 'VERB', 'ADJ', 'ADV')]
            f.write(json.dumps({'tb': tb, 'text': text, 'toks': toks}, ensure_ascii=False) + '\n')
            n += 1
            t += len(toks)
        print('tr dev', tb, n, t)


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


man = {'built_by': 'tools/eval/build_final.py', 'seed': SEED,
       'licences': {'SemCor 3.0': 'Princeton WordNet licence (notice kept)', 'MAGPIE': 'labels CC BY 4.0; BNC text not redistributable',
                    'UD English-EWT': 'CC BY-SA 4.0', 'UD Turkish BOUN/Kenet/Penn': 'CC BY-SA 4.0'},
       'inputs': {os.path.basename(p): sha(p) for p in [magpie] + glob.glob(f'{ud}/en_ewt-train.conllu') + glob.glob(f'{ud}/tr_*-dev.conllu')},
       'outputs': {os.path.relpath(p, out): sha(p) for p in sorted(glob.glob(f'{out}/final_*') + [f'{out}/text/text_eval_test.jsonl'])}}
json.dump(man, open(f'{out}/MANIFEST.json', 'w'), indent=1)

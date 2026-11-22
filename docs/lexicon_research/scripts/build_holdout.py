"""Builds the Task 5A hold-out evaluation sets (read-only on dict.db; nothing is written to the repository).

usage: python3 -I build_holdout.py assets/dict.db NLTK_DATA_DIR MAGPIE_unfiltered.jsonl UD_DIR PREV_DIR OUT_DIR

Independence rules (decided before any app output was looked at):
  * SemCor: words that appear in none of test/data/sense_eval_semcor{,_dev,_fresh}.tsv, drawn with a new seed;
    verbs also come from the brownv part of SemCor, which the earlier draws never read.
    Rows whose human-chosen synset has no KeNet Turkish are KEPT (tr = "") so that the English
    sense choice is measured on every row, not only where a Turkish reference exists.
  * MAGPIE: idioms that are in none of the earlier dev/fresh/fresh2 draws (PREV_DIR, regenerated with
    tools/eval/build_sense_eval.py), any dictionary category, with or without Turkish.
    BNC text: local measuring only, never committed.
  * UD English-EWT dev + test (never used before; GUM was) for phrasal verbs: gold = VERB + compound:prt.
  * UD Turkish BOUN, Kenet and Penn test files for Turkish base forms and parts of speech.
"""
import json, random, re, sqlite3, sys, glob, os

dbp, nltk_dir, magpie, ud, prev, out = sys.argv[1:7]
db = sqlite3.connect(f'file:{dbp}?mode=ro', uri=True)
import nltk
nltk.data.path.insert(0, nltk_dir)
from nltk.corpus import semcor, wordnet as wn
from nltk.tree import Tree

SEED = 20261122 + 500
QUOTA = {'n': 120, 'v': 120, 'a': 60, 'r': 40}
repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
used = set()
for f in ('sense_eval_semcor.tsv', 'sense_eval_semcor_dev.tsv', 'sense_eval_semcor_fresh.tsv'):
    for l in open(os.path.join(repo, 'test', 'data', f), encoding='utf-8'):
        if not l.startswith('#') and l.strip():
            used.add(l.split('\t')[0])
used |= {'course', 'still', 'bank', 'book', 'through', 'want', 'raise', 'goal', 'delicious', 'recommend', 'simply', 'class'}

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
nomap = 0
for fid in semcor.fileids():
    for sent in semcor.tagged_sents(fid, tag='sem'):
        words, marks = [], []
        for ch in sent:
            if isinstance(ch, Tree):
                lem = ch.label()
                leaves = ch.leaves()
                if hasattr(lem, 'synset') and len(leaves) == 1:
                    marks.append((len(words), lem))
                words.extend(leaves)
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
            if not hit:
                nomap += 1
                continue
            if sum(1 for w in words if w.lower() == words[at].lower()) != 1:
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
with open(f'{out}/holdout_semcor.tsv', 'w', encoding='utf-8') as f:
    f.write(f'# SemCor 3.0 hold-out for Task 5A, seed {SEED}; words of the three earlier draws left out. KeNet Turkish may be empty.\n')
    for r in rows:
        f.write('\t'.join(str(x) for x in r) + '\n')
print('semcor candidates', {p: len(c) for p, c in cands.items()}, 'synsets not in dict.db', nomap, 'sampled', len(rows),
      'with KeNet Turkish', sum(1 for r in rows if r[3]))

# MAGPIE: idioms not used before
prev_idioms = set()
for f in glob.glob(f'{prev}/sense_eval_magpie_*.tsv'):
    for l in open(f, encoding='utf-8'):
        if not l.startswith('#') and l.strip():
            prev_idioms.add(l.split('\t')[0])
dict_phr = {}
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    dict_phr.setdefault(p, c)
by = {'i': {}, 'l': {}}
all_idioms = set()
for line in open(magpie, encoding='utf-8'):
    j = json.loads(line)
    if j['confidence'] != 1.0 or j['label'] not in by:
        continue
    all_idioms.add(j['idiom'])
    if j['idiom'] in prev_idioms or j['idiom'] not in dict_phr:
        continue
    if j['variant_type'] not in ('identical', 'inflection'):
        continue
    s = detok(j['context'][2].split(' '))
    if 5 <= len(s.split()) <= 30:
        by[j['label']].setdefault(j['idiom'], []).append((s, j['id']))
rnd = random.Random(SEED + 1)
mrows = []
for label, n in (('i', 150), ('l', 150)):
    names = sorted(by[label])
    rnd.shuffle(names)
    for name in names[:n]:
        s, i = rnd.choice(sorted(by[label][name]))
        mrows.append((name, label, dict_phr[name], i, s))
with open(f'{out}/holdout_magpie.tsv', 'w', encoding='utf-8') as f:
    f.write('# MAGPIE hold-out (idioms not in earlier draws); BNC text, local only. Columns: idiom, label, dict category, id, sentence\n')
    for r in mrows:
        f.write('\t'.join(str(x) for x in r) + '\n')
inside = sum(1 for x in all_idioms if x in dict_phr)
print('magpie idioms (agreement 1.0)', len(all_idioms), 'in dict.db expr', inside, 'hold-out rows', len(mrows),
      {k: len(v) for k, v in by.items()})


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


with open(f'{out}/holdout_ewt_prt.jsonl', 'w', encoding='utf-8') as f:
    n = g = 0
    for text, sent in [x for part in ('dev', 'test') for x in conllu(f'{ud}/en_ewt-{part}.conllu')]:
        gold = []
        for c in sent:
            if c[7] == 'compound:prt':
                h = sent[int(c[6]) - 1]
                if h[3] == 'VERB':
                    gold.append([h[2].lower(), c[2].lower()])
        f.write(json.dumps({'text': text, 'gold': gold}, ensure_ascii=False) + '\n')
        n += 1
        g += len(gold)
    print('ewt sentences', n, 'gold verb+particle', g)

with open(f'{out}/holdout_ewt_propn.jsonl', 'w', encoding='utf-8') as f:
    for text, sent in [x for part in ('dev', 'test') for x in conllu(f'{ud}/en_ewt-{part}.conllu')]:
        pr = [c[1] for c in sent[1:] if c[3] == 'PROPN' and c[1][:1].isupper() and c[1].isalpha()]
        if pr and text:
            f.write(json.dumps({'text': text, 'propn': pr}, ensure_ascii=False) + '\n')

with open(f'{out}/holdout_ud_tr.jsonl', 'w', encoding='utf-8') as f:
    for tb in ('boun', 'kenet', 'penn'):
        n = t = 0
        for text, sent in conllu(f'{ud}/tr_{tb}-test.conllu'):
            toks = [[c[1], c[2], c[3]] for c in sent if c[3] in ('NOUN', 'VERB', 'ADJ', 'ADV')]
            f.write(json.dumps({'tb': tb, 'text': text, 'toks': toks}, ensure_ascii=False) + '\n')
            n += 1
            t += len(toks)
        print('tr', tb, 'sentences', n, 'content words', t)

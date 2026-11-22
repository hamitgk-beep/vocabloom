"""Builds the independent evaluation sets for the meaning-in-context rule (read-only on dict.db).

usage: python3 tools/eval/build_sense_eval.py assets/dict.db NLTK_DATA_DIR [MAGPIE_unfiltered.jsonl] OUT_DIR

1. test/data/sense_eval_semcor.tsv: words in sentences of SemCor 3.0 (Brown corpus), whose WordNet
   sense was chosen by human annotators at Princeton. The reference Turkish is the Turkish of that
   very synset in KeNet (the hand-made Turkish WordNet), as stored in dict.db (syn.tr). Examples
   whose gold synset has no Turkish in KeNet are left out: there is no reliable reference for them.
2. OUT_DIR/sense_eval_magpie_dev.tsv and _fresh.tsv (optional): idioms in sentences of the MAGPIE corpus, each
   labelled idiomatic or literal by crowd annotators with full agreement. Most of its sentences
   are from the British National Corpus, which may not be passed on: this file is for local
   measuring only and is not kept in the repository.

The sample is drawn with a fixed seed, by part of speech, one example per word, BEFORE any system
output is looked at; the words used as worked examples while the rule was written are left out.
Nothing here reads what the app answers.
"""
import json
import random
import re
import sqlite3
import sys

db = sqlite3.connect(f'file:{sys.argv[1]}?mode=ro', uri=True)
import nltk
nltk.data.path.insert(0, sys.argv[2])
from nltk.corpus import semcor, wordnet as wn
from nltk.tree import Tree

magpie = sys.argv[3] if len(sys.argv) > 4 else None
out = sys.argv[-1]
SEED = 20261122
DEV_WORDS = {'course', 'still', 'bank', 'book', 'through', 'want', 'raise', 'goal', 'delicious', 'recommend', 'simply', 'class'}
QUOTA = {'n': 90, 'v': 90, 'a': 50, 'r': 30}

syn = {}  # (pos, gloss) -> (id, tr)
for i, pos, gloss, tr in db.execute('SELECT id, pos, gloss, tr FROM syn'):
    syn[('a' if pos == 's' else pos, gloss)] = (i, json.loads(tr) if tr else [])
freq = {w for (w,) in db.execute('SELECT word FROM wfreq')}


def detok(words):
    s = ' '.join(words)
    s = re.sub(r" ([,.;:!?%)])", r"\1", s)
    s = re.sub(r"([(]) ", r"\1", s)
    s = re.sub(r" (n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    s = s.replace('`` ', '"').replace(" ''", '"').replace('``', '"').replace("''", '"')
    return s


cands = {p: {} for p in QUOTA}
for fid in semcor.fileids():
    if not fid.startswith(('brown1', 'brown2')):
        continue
    for sent in semcor.tagged_sents(fid, tag='sem'):
        words = []
        marks = []
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
            if pos not in QUOTA or name in DEV_WORDS or name not in freq or not name.isalpha() or len(name) < 3:
                continue
            if len(wn.synsets(name, ss.pos() if ss.pos() != 's' else 'a')) < 2:
                continue  # one sense only: nothing to choose
            hit = syn.get((pos, ss.definition()))
            if not hit or not hit[1]:
                continue  # no human Turkish reference for this sense
            surface = words[at].lower()
            if sum(1 for w in words if w.lower() == surface) != 1:
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
with open(f'{out}/sense_eval_semcor.tsv', 'w', encoding='utf-8') as f:
    f.write('# SemCor 3.0 (Princeton University; mapping to WordNet 3.0 by R. Mihalcea, UNT), Brown corpus sentences.\n')
    f.write('# Sense chosen by human annotators; Turkish reference: KeNet (CC BY-SA 4.0) Turkish of that synset.\n')
    f.write(f'# Built by tools/eval/build_sense_eval.py, seed {SEED}. Columns: lemma, pos, dict.db synset id, reference Turkish, sentence, file.\n')
    for r in rows:
        f.write('\t'.join(str(x) for x in r) + '\n')
print('semcor', {p: len(cands[p]) for p in cands}, 'sampled', len(rows))

if magpie:
    exprs = {p for (p,) in db.execute("SELECT phrase FROM expr WHERE cat='idioms' AND tr IS NOT NULL AND tr != ''")}
    by = {'i': {}, 'l': {}}
    for line in open(magpie, encoding='utf-8'):
        j = json.loads(line)
        if j['confidence'] != 1.0 or j['label'] not in by or j['idiom'] not in exprs:
            continue
        if j['variant_type'] not in ('identical', 'inflection'):
            continue
        s = detok(j['context'][2].split(' '))
        if 5 <= len(s.split()) <= 24:
            by[j['label']].setdefault(j['idiom'], []).append((s, j['id']))
    # Two draws of different idioms: the first one was looked at while the rule for expressions
    # was settled (development), the second one is measured once (fresh).
    used = set()
    for part in ('dev', 'fresh'):
        rows = []
        for label, n in (('i', 60), ('l', 60)):
            names = sorted(x for x in by[label] if x not in used)
            rnd.shuffle(names)
            for name in names[:n]:
                s, i = rnd.choice(sorted(by[label][name]))
                rows.append((name, label, i, s))
        used |= {r[0] for r in rows}
        with open(f'{out}/sense_eval_magpie_{part}.tsv', 'w', encoding='utf-8') as f:
            f.write('# MAGPIE corpus (Haagsma, Bos, Nissim 2020); not for redistribution (BNC text); label i = idiomatic, l = literal (annotator agreement 1.0).\n')
            f.write('# Columns: idiom, label, MAGPIE id, sentence.\n')
            for r in rows:
                f.write('\t'.join(str(x) for x in r) + '\n')
        print('magpie', part, {k: len(v) for k, v in by.items()}, 'sampled', len(rows))

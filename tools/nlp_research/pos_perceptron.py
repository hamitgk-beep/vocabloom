"""Task 5E, stage 2, option 4: a small part-of-speech tagger the phone could run without Python or native code.

An averaged perceptron (the classic Collins / Honnibal tagger, as in NLTK's PerceptronTagger) trained here from
scratch on UD English-EWT (CC BY-SA 4.0): only its weights, a table of feature -> tag -> weight, would ship, and the
tagging loop is about 60 lines in Dart. Nothing pretrained is used, so no WSJ / OntoNotes licence question arises;
the CC BY-SA terms of EWT (attribution, share-alike on the weights as an adaptation) remain to be checked by
the licence task (5C).

usage: python3 tools/nlp_research/pos_perceptron.py UD_DIR EWT_TEXT_JSONL EVERY ENGINE_DUMP OUT_DIR [FINAL_JSONL FINAL_DUMP]

Training: EWT dev + test, and the EWT train paragraphs NOT in the development sample (every EVERY-th paragraph of
EWT_TEXT_JSONL is the development sample, see dump_engine_test.dart). Development: the sampled paragraphs.
"""
import json, os, sys, time, random, pickle, gzip

ud, ewt, every, dump, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
final = sys.argv[6:8] if len(sys.argv) > 7 else None
os.makedirs(out, exist_ok=True)
from nltk.tag.perceptron import PerceptronTagger

WANT = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'}


def conllu_sents(path):
    sent = []
    for line in open(path, encoding='utf-8'):
        if line.startswith('#'):
            continue
        if not line.strip():
            if sent:
                yield sent
            sent = []
            continue
        c = line.split('\t')
        if '-' in c[0] or '.' in c[0]:
            continue
        sent.append((c[1], c[3]))
    if sent:
        yield sent


def para_sents(p):
    """The paragraph's tokens grouped by gold sentence, as (form, upos), plus their offsets."""
    res = []
    for a, b in p['sents']:
        res.append([(t[2], t[4], t[0]) for t in p['toks'] if a <= t[0] < b])
    return res


paras = [json.loads(l) for l in open(ewt, encoding='utf-8')]
train = list(conllu_sents(f'{ud}/en_ewt-dev.conllu')) + list(conllu_sents(f'{ud}/en_ewt-test.conllu'))
for i, p in enumerate(paras):
    if i % every != 0:
        train += [[(f, u) for f, u, _ in s] for s in para_sents(p)]
print('training sentences', len(train), flush=True)
t0 = time.time()
tagger = PerceptronTagger(load=False)
random.seed(5)
tagger.train(train, nr_iter=5)
print(f'trained in {time.time() - t0:.0f}s', flush=True)
model = {'weights': tagger.model.weights, 'tagdict': tagger.tagdict, 'classes': sorted(tagger.classes)}
blob = gzip.compress(json.dumps(model).encode())
open(f'{out}/ewt_perceptron.json.gz', 'wb').write(blob)
n_feat = len(tagger.model.weights)
n_w = sum(len(v) for v in tagger.model.weights.values())
print(f'model: {n_feat} features, {n_w} weights, {len(blob) / 1e6:.1f} MB gzipped JSON', flush=True)


def evaluate(paras_eval, dump_path, label):
    # tag every gold sentence; map by paragraph index + offset
    tags = {}
    t0 = time.time()
    ns = 0
    for pi, p in paras_eval:
        for s in para_sents(p):
            ns += 1
            for (f, u, off), (_, t) in zip(s, tagger.tag([f for f, _, _ in s])):
                tags[(pi, off)] = t
    secs = time.time() - t0
    tok_n = tok_ok = 0
    for pi, p in paras_eval:
        for t in p['toks']:
            if t[4] in WANT and t[2].isalpha():
                tok_n += 1
                tok_ok += tags.get((pi, t[0])) == t[4]
    eng = [json.loads(l) for l in open(dump_path, encoding='utf-8')]
    pmap = dict(paras_eval)
    bn = bok = engok = bsure = bsure_wrong = esure = esure_wrong = amb_n = amb_ok = 0
    for e in eng:
        p = pmap.get(e['p'])
        if p is None:
            continue
        off = p['text'].find(e['sent'])
        tg = tags.get((e['p'], off + e['start'])) if off >= 0 else None
        if e['cat'] is not None or len(e['posOf']) < 2:
            continue
        gold = WANT[e['gold_upos']]
        sp = WANT.get(tg)
        amb_n += 1
        amb_ok += sp == gold
        if not e['shown'] or e['pos'] is None:
            continue
        bn += 1
        engok += e['pos'] == gold
        if e['conf'] == 'sure':
            esure += 1
            esure_wrong += e['pos'] != gold
        chosen, conf = e['pos'], e['conf']
        if sp and sp != e['pos'] and sp in e['byPos']:
            chosen, conf = sp, 'likely'
        elif sp != e['pos']:
            conf = 'likely' if conf == 'sure' else conf
        bok += chosen == gold
        if conf == 'sure':
            bsure += 1
            bsure_wrong += chosen != gold
    r = {'set': label, 'sentences': ns, 'ms_per_sentence (python)': round(1000 * secs / max(1, ns), 3),
         'upos_nvar': f'{tok_ok}/{tok_n} = {100 * tok_ok / max(1, tok_n):.1f}%',
         'ambiguous_words_pos': f'{amb_ok}/{amb_n} = {100 * amb_ok / max(1, amb_n):.1f}%',
         'engine_pos_of_meaning_shown': f'{engok}/{bn} = {100 * engok / max(1, bn):.1f}%; sure {esure}, wrong {esure_wrong} = {100 * esure_wrong / max(1, esure):.1f}%',
         'B4_engine_plus_perceptron_pos': f'{bok}/{bn} = {100 * bok / max(1, bn):.1f}%; sure {bsure}, wrong {bsure_wrong} = {100 * bsure_wrong / max(1, bsure):.1f}%'}
    print(json.dumps(r, indent=1), flush=True)
    return r


res = [evaluate([(i, p) for i, p in enumerate(paras) if i % every == 0], dump, 'dev: EWT train sample')]
if final:
    fp = [json.loads(l) for l in open(final[0], encoding='utf-8')]
    res.append(evaluate(list(enumerate(fp)), final[1], 'final: PUD + GENTLE'))
json.dump(res, open(f'{out}/perceptron_eval.json', 'w'), indent=1)

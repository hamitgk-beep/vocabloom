"""Task 5E: part of speech of the target word of every dumped sense row, by spaCy (sm / md / trf) or the EWT
perceptron (pos_perceptron.py), for system B (the engine's candidates re-chosen by that part of speech).

usage: python3 tools/nlp_research/pos_for_rows.py TAGGER DUMP_DIR OUT_DIR SET [SET ...]
TAGGER: en_core_web_sm | en_core_web_md | en_core_web_trf | perceptron:<path to ewt_perceptron.json.gz>
"""
import gzip, json, os, re, sys, time

WANT = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r', 'PROPN': 'propn'}
tagger, dump, out, sets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
key = 'perceptron' if tagger.startswith('perceptron:') else tagger
os.makedirs(f'{out}/{key}', exist_ok=True)
if key == 'perceptron':
    from nltk.tag.perceptron import PerceptronTagger
    m = json.loads(gzip.decompress(open(tagger.split(':', 1)[1], 'rb').read()))
    pt = PerceptronTagger(load=False)
    pt.model.weights = m['weights']
    pt.tagdict = m['tagdict']
    pt.classes = set(m['classes'])
    pt.model.classes = pt.classes
    TOK = re.compile(r"[A-Za-z0-9À-ÿ]+(?:['’][A-Za-z]+)?|[^\sA-Za-z0-9À-ÿ]")
else:
    import spacy
    nlp = spacy.load(tagger)
for name in sets:
    rows = [json.loads(l) for l in open(f'{dump}/{name}.engine.jsonl', encoding='utf-8')]
    res = []
    t0 = time.time()
    for r in rows:
        if 'start' not in r:
            res.append(None)
            continue
        s, a = r['sentence'], r['start']
        if key == 'perceptron':
            toks = [(m_.start(), m_.group()) for m_ in TOK.finditer(s)]
            tags = pt.tag([t for _, t in toks]) if toks else []
            tag = next((tg for (st, _), (_, tg) in zip(toks, tags) if st == a), None)
        else:
            doc = nlp(s)
            tag = next((t.pos_ for t in doc if t.idx == a), None)
        res.append(WANT.get(tag, tag))
    json.dump({'tagger': tagger, 'secs': time.time() - t0, 'pos': res}, open(f'{out}/{key}/{name}.json', 'w'))
    print(key, name, f'{time.time() - t0:.1f}s', flush=True)

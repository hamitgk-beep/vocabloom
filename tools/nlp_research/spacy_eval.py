"""Task 5E, stage 2: spaCy against the current Storilex analysis, on the same UD English-EWT tokens.

usage: python3 tools/nlp_research/spacy_eval.py EWT_TEXT_JSONL ENGINE_DUMP_JSONL EVERY OUT_JSON

EWT_TEXT_JSONL: text_eval format (tools/eval/build_final.py, UD English-EWT train, CC BY-SA 4.0; spaCy's en_core_web
models are trained on OntoNotes 5, not on EWT, so EWT is out of their training data).
ENGINE_DUMP_JSONL: tools/nlp_research/dump_engine_test.dart "ewt tokens" output for the same file and EVERY.
Measures, for spaCy sm / md / trf: tokenization (gold token boundaries), sentence boundaries, POS and lemma of
nouns, verbs, adjectives and adverbs, PROPN for names, and speed; then system B: the engine's own candidates
re-chosen by spaCy's part of speech.
"""
import json, sys, time, collections, os, resource

import spacy

ewt, dump, every, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
WANT = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'}
paras = [json.loads(l) for i, l in enumerate(open(ewt, encoding='utf-8')) if i % every == 0]
eng = [json.loads(l) for l in open(dump, encoding='utf-8')]
# engine rows by (paragraph index, sentence, start in sentence)
eng_by = {}
for e in eng:
    eng_by[(e['p'], e['sent'], e['start'])] = e

res = {}
for name in ('en_core_web_sm', 'en_core_web_md', 'en_core_web_trf'):
    try:
        nlp = spacy.load(name)
    except OSError:
        continue
    t0 = time.time()
    docs = list(nlp.pipe([p['text'] for p in paras], batch_size=16))
    secs = time.time() - t0
    nsent_gold = sum(len(p['sents']) for p in paras)
    tok_n = tok_ok = 0
    b_gold = b_pred = b_hit = 0
    lem_n = lem_ok = 0
    pos_n = pos_ok = 0
    amb_n = amb_ok = 0
    propn_n = propn_ok = 0
    # system B on the engine's rows
    bn = bshown = bok = engok = 0
    bsure = bsure_wrong = esure = esure_wrong = 0
    for pi_, (p, doc) in enumerate(zip(paras, docs)):
        pi = pi_ * every
        starts = {t.idx: t for t in doc}
        gold_b = {s[0] for s in p['sents'][1:]}
        pred_b = {s.start_char for s in list(doc.sents)[1:]}
        # gold sentence starts may follow spaces
        text = p['text']
        pred_b = {i + (len(text[i:]) - len(text[i:].lstrip())) for i in pred_b}
        b_gold += len(gold_b); b_pred += len(pred_b); b_hit += len(gold_b & pred_b)
        for (s, e, form, lemma, upos) in p['toks']:
            if upos in ('PUNCT', 'SYM', 'NUM', 'X') or not any(ch.isalpha() for ch in form):
                continue
            tok_n += 1
            t = starts.get(s)
            if t is None or t.idx + len(t.text) != e:
                continue
            tok_ok += 1
            if upos == 'PROPN':
                propn_n += 1
                propn_ok += t.pos_ == 'PROPN' or t.ent_type_ != ''
            if upos not in WANT:
                continue
            lower = form.lower().replace('’', "'")
            if not lower.isalpha() or not lower.isascii():
                continue
            lem_n += 1
            lem_ok += t.lemma_.lower() == lemma.lower()
            pos_n += 1
            pos_ok += t.pos_ == upos
            # the engine's row for this token (same sentence split as the app's)
    # system B: rows of the engine dump, spaCy's POS of the same token (found by character offset in the paragraph)
    for e in eng:
        p = paras[e['p'] // every]
        doc = docs[e['p'] // every]
        off = p['text'].find(e['sent'])
        t = {x.idx: x for x in doc}.get(off + e['start']) if off >= 0 else None
        if t is None or e['cat'] is not None or len(e['posOf']) < 2:
            continue
        gold = WANT[e['gold_upos']]
        sp = WANT.get(t.pos_)
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
    res[name] = {
        'version': nlp.meta.get('version'), 'paragraphs': len(paras), 'seconds': round(secs, 2),
        'ms_per_sentence': round(1000 * secs / max(1, nsent_gold), 2),
        'tokens': f'{tok_ok}/{tok_n} = {100 * tok_ok / tok_n:.1f}%',
        'sentence_boundaries': f'P {100 * b_hit / max(1, b_pred):.1f}% R {100 * b_hit / max(1, b_gold):.1f}%',
        'lemma_nvar': f'{lem_ok}/{lem_n} = {100 * lem_ok / lem_n:.1f}%',
        'upos_nvar': f'{pos_ok}/{pos_n} = {100 * pos_ok / pos_n:.1f}%',
        'propn_recall': f'{propn_ok}/{propn_n} = {100 * propn_ok / max(1, propn_n):.1f}%',
        'ambiguous_words_pos': f'{amb_ok}/{amb_n} = {100 * amb_ok / max(1, amb_n):.1f}%',
        'engine_pos_of_meaning_shown': f'{engok}/{bn} = {100 * engok / max(1, bn):.1f}%; sure {esure}, wrong {esure_wrong} = {100 * esure_wrong / max(1, esure):.1f}%',
        'B_engine_plus_spacy_pos': f'{bok}/{bn} = {100 * bok / max(1, bn):.1f}%; sure {bsure}, wrong {bsure_wrong} = {100 * bsure_wrong / max(1, bsure):.1f}%',
        'maxrss_mb': round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024),
        'package_mb': round(sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(nlp.path) for f in fs) / 1e6, 1),
    }
    print(name, json.dumps(res[name], indent=1), flush=True)
json.dump(res, open(out, 'w'), indent=1)

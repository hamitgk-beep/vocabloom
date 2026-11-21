"""Measures the English analyzers on hand-labelled sentences (eval/en_gold.jsonl).

Every sentence is copied verbatim from a public-domain Project Gutenberg book in library/books. The labels
(names, phrasal verbs, lemmas) were written for this evaluation; they are an approximation, not a published
gold standard.

Metrics, per engine:
  lemma_accuracy        labelled inflected words whose lemma is right ("sat" -> "sit")
  name_precision/recall words treated as names (left out of word candidates) against the labelled names
  phrasal_precision/recall   two-word particle verbs found, against the labelled ones
  name_leakage          labelled names that still became a word candidate in a full extraction
  word_candidates       word candidates written for the 30 sentences (lower is less review work)

Usage (repository root):
  python3 tools/lexicon/eval/evaluate.py [--engine builtin|spacy|both] [--dict-db assets/dict.db] [--json]
  python3 tools/lexicon/eval/evaluate.py --lang tr [--engine builtin|zemberek|both]
Turkish (eval/tr_gold.jsonl, 20 sentences from public-domain Wikisource texts in the app's library): lemma accuracy,
name precision/recall (titles such as "Hoca", "Bey" are not scored) and name leakage.
The dictionaries are opened read-only; the candidate store is a temporary file that is deleted afterwards.
"""
import argparse
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

from lexicon.adapters.english import make_english  # noqa: E402
from lexicon.adapters.turkish import make_turkish  # noqa: E402
from lexicon.compare import EnTrDictionary, TrEnDictionary, fold_tr  # noqa: E402
from lexicon.extract import extract, name_evidence  # noqa: E402
from lexicon.safety import repo_root  # noqa: E402
from lexicon.store import CandidateStore  # noqa: E402

GOLD = os.path.join(HERE, 'en_gold.jsonl')
TR_GOLD = os.path.join(HERE, 'tr_gold.jsonl')
# Capitalised titles and day names: neither a name nor a word error, so not scored.
TR_UNSCORED = {'hoca', 'bey', 'paşa', 'efendi', 'çelebi', 'hacı', 'cuma', 'peygamberin', 'peygamber'}


def load_gold(path=GOLD):
    with open(path, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def _bare(word):
    w = word.lower().replace('’', "'")
    return w[:-2] if w.endswith("'s") else w


def _ratio(a, b):
    return round(a / b, 3) if b else None


def evaluate(engine, dictionary, gold):
    analyzer = make_english(engine, dictionary)
    per_sentence = [analyzer.analyze(g['text']) for g in gold]
    names, _ = name_evidence([s for sents in per_sentence for s in sents])

    lemma_ok = lemma_all = 0
    name_tp = name_fp = name_fn = 0
    ph_tp = ph_fp = ph_fn = 0
    errors = {'lemma': [], 'name_missed': [], 'name_wrong': [], 'phrasal_missed': [], 'phrasal_wrong': []}
    for g, sents in zip(gold, per_sentence):
        toks = [t for s in sents for t in s.tokens if t.is_word]
        by_text = {}
        for t in toks:
            by_text.setdefault(t.text.lower(), t)
        for surface, lemma in g['lemmas'].items():
            lemma_all += 1
            t = by_text.get(surface)
            got = (t.lemma or '').lower() if t else None
            if got == lemma:
                lemma_ok += 1
            else:
                errors['lemma'].append(f'{surface}->{got} (want {lemma})')
        predicted_names = {_bare(t.text) for t in toks
                           if t.pos == 'PROPN' or t.ent or t.text.lower() in names}
        predicted_names.discard('i')
        gold_names = set(g['names'])
        name_tp += len(predicted_names & gold_names)
        name_fp += len(predicted_names - gold_names)
        name_fn += len(gold_names - predicted_names)
        errors['name_missed'] += sorted(gold_names - predicted_names)
        errors['name_wrong'] += sorted(predicted_names - gold_names)
        predicted_ph = {p.phrase for s in sents for p in s.phrases
                        if p.kind == 'phrasal_verb' and len(p.phrase.split()) == 2}
        gold_ph = set(g['phrasal_verbs'])
        ph_tp += len(predicted_ph & gold_ph)
        ph_fp += len(predicted_ph - gold_ph)
        ph_fn += len(gold_ph - predicted_ph)
        errors['phrasal_missed'] += sorted(gold_ph - predicted_ph)
        errors['phrasal_wrong'] += sorted(predicted_ph - gold_ph)

    all_names = {n for g in gold for n in g['names']}
    with tempfile.TemporaryDirectory() as tmp:
        store = CandidateStore(os.path.join(tmp, 'eval.db'))
        sid = store.add_source('eval-gutenberg', 'public_domain_text', 'Public domain', 'en')
        extract(store, analyzer, dictionary, sid, '\n\n'.join(g['text'] for g in gold), 'en-tr', examples=False)
        words = [r['headword'] for r in store.candidates(kind='word')]
        store.close()
    leaked = sorted({w for w in words if w in all_names})
    return {
        'engine': analyzer.engine_id,
        'sentences': len(gold),
        'lemma_accuracy': _ratio(lemma_ok, lemma_all), 'lemmas': lemma_all,
        'name_precision': _ratio(name_tp, name_tp + name_fp), 'name_recall': _ratio(name_tp, name_tp + name_fn),
        'names': name_tp + name_fn,
        'phrasal_precision': _ratio(ph_tp, ph_tp + ph_fp), 'phrasal_recall': _ratio(ph_tp, ph_tp + ph_fn),
        'phrasal_verbs': ph_tp + ph_fn,
        'name_leakage': _ratio(len(leaked), len(all_names)), 'leaked_names': leaked,
        'word_candidates': len(words), 'word_candidate_list': sorted(words),
        'errors': errors,
    }


def _tr_key(word):
    w = fold_tr(word)
    for ap in ("'", '’', '´'):
        w = w.split(ap)[0]
    return w


def evaluate_tr(engine, dictionary, gold):
    analyzer = make_turkish(engine, dictionary)
    try:
        per_sentence = [analyzer.analyze(g['text']) for g in gold]
        names, _ = name_evidence([s for sents in per_sentence for s in sents])
        lemma_ok = lemma_all = name_tp = name_fp = name_fn = 0
        errors = {'lemma': [], 'name_missed': [], 'name_wrong': []}
        for g, sents in zip(gold, per_sentence):
            toks = [t for s in sents for t in s.tokens if t.is_word]
            by_text = {}
            for t in toks:
                by_text.setdefault(fold_tr(t.text), t)
            for surface, lemma in g['lemmas'].items():
                lemma_all += 1
                t = by_text.get(surface)
                got = fold_tr(t.lemma) if t and t.lemma else ''
                got_key = dictionary.lemma_key(got) if got else None
                if got == lemma or got_key == lemma:
                    lemma_ok += 1
                else:
                    errors['lemma'].append(f'{surface}->{got or "?"} (want {lemma})')
            predicted = {_tr_key(t.text) for t in toks if t.pos == 'PROPN' or t.ent or fold_tr(t.text) in names}
            predicted -= TR_UNSCORED
            gold_names = set(g['names'])
            name_tp += len(predicted & gold_names)
            name_fp += len(predicted - gold_names)
            name_fn += len(gold_names - predicted)
            errors['name_missed'] += sorted(gold_names - predicted)
            errors['name_wrong'] += sorted(predicted - gold_names)
        all_names = {n for g in gold for n in g['names']}
        with tempfile.TemporaryDirectory() as tmp:
            store = CandidateStore(os.path.join(tmp, 'eval.db'))
            sid = store.add_source('eval-wikisource', 'public_domain_text', 'Public domain', 'tr')
            extract(store, analyzer, dictionary, sid, '\n\n'.join(g['text'] for g in gold), 'tr-en', examples=False)
            words = [r['headword'] for r in store.candidates(kind='word')]
            store.close()
    finally:
        if hasattr(analyzer, 'close'):
            analyzer.close()
    leaked = sorted({w for w in words if _tr_key(w) in all_names})
    return {
        'engine': analyzer.engine_id, 'sentences': len(gold),
        'lemma_accuracy': _ratio(lemma_ok, lemma_all), 'lemmas': lemma_all,
        'name_precision': _ratio(name_tp, name_tp + name_fp), 'name_recall': _ratio(name_tp, name_tp + name_fn),
        'names': name_tp + name_fn,
        'name_leakage': _ratio(len(leaked), len(all_names)), 'leaked_names': leaked,
        'word_candidates': len(words), 'word_candidate_list': sorted(words), 'errors': errors,
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--lang', default='en', choices=['en', 'tr'])
    p.add_argument('--engine', default='both', choices=['builtin', 'spacy', 'zemberek', 'both'])
    p.add_argument('--dict-db', default=os.path.join(repo_root(), 'assets', 'dict.db'))
    p.add_argument('--tr-en-db', default=os.path.join(repo_root(), 'assets', 'tr_en.db'))
    p.add_argument('--json', action='store_true')
    a = p.parse_args(argv)
    if a.lang == 'en':
        gold, dictionary, run, other = load_gold(), EnTrDictionary(a.dict_db), evaluate, 'spacy'
    else:
        gold, dictionary, run, other = load_gold(TR_GOLD), TrEnDictionary(a.tr_en_db), evaluate_tr, 'zemberek'
    engines = ['builtin', other] if a.engine == 'both' else [a.engine]
    results = []
    for e in engines:
        try:
            results.append(run(e, dictionary, gold))
        except (ImportError, RuntimeError) as exc:
            print(f'{e}: not available ({exc}); see setup_spacy.sh / setup_zemberek.sh', file=sys.stderr)
    dictionary.close()
    if a.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
        return
    keys = [k for k in ['lemma_accuracy', 'name_precision', 'name_recall', 'phrasal_precision', 'phrasal_recall',
                        'name_leakage', 'word_candidates'] if all(k in r for r in results)]
    print('metric'.ljust(20) + ''.join(r['engine'].ljust(36) for r in results))
    for k in keys:
        print(k.ljust(20) + ''.join(str(r[k]).ljust(36) for r in results))
    for r in results:
        print(f'\n[{r["engine"]}]')
        for k, v in r['errors'].items():
            if v:
                print(f'  {k}: {", ".join(v)}')
        print(f'  leaked names: {", ".join(r["leaked_names"]) or "-"}')
        print(f'  word candidates: {", ".join(r["word_candidate_list"]) or "-"}')


if __name__ == '__main__':
    main()

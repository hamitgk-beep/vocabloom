"""Measures the context sense suggestion (senses.py) on hand-labelled sentences (eval/sense_gold.jsonl).

Each line is a sentence copied verbatim from a public-domain Project Gutenberg book in library/books, a word with
several curated senses in dict.db, and the index (or indices, when two senses fit equally) of the fitting sense.
Labels were written for this evaluation by Claude, not by a lexicographer.

Metrics:
  accuracy           the suggested sense is one of the labelled ones
  first_sense        the same for always picking the dictionary's first sense (the baseline)
  pos_only           first sense of the right word class (the analyzer's class, no context words)
  context_precision  accuracy over suggestions made with basis 'context' (confidence 0.5)
  context_coverage   share of instances that got a 'context' suggestion

Usage (repository root):
  python3 tools/lexicon/eval/evaluate_senses.py [--engine builtin|spacy|both] [--embeddings] [--json]
--embeddings adds a run with the Sentence Transformers model (embeddings.py; setup_embeddings.sh).
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))

from lexicon.adapters.english import make_english  # noqa: E402
from lexicon.compare import EnTrDictionary  # noqa: E402
from lexicon.safety import repo_root  # noqa: E402
from lexicon.senses import OWN_POS_TO_UPOS, SenseRanker  # noqa: E402

GOLD = os.path.join(HERE, 'sense_gold.jsonl')


def load_gold(path=GOLD):
    with open(path, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


def _ratio(a, b):
    return round(a / b, 3) if b else None


def target_pos(analyzer, text, word):
    """Universal POS of the labelled word in the sentence, as the analyzer sees it (None if not found)."""
    for s in analyzer.analyze(text):
        for t in s.tokens:
            if t.is_word and (t.lemma or '').lower() == word and t.pos:
                return t.pos
    for s in analyzer.analyze(text):
        for t in s.tokens:
            if t.is_word and t.text.lower().startswith(word[:4]) and t.pos:
                return t.pos
    return None


def evaluate(engine, dictionary, gold, encoder=None):
    analyzer = make_english(engine, dictionary)
    ranker = SenseRanker(dictionary, encoder)
    ok = first = pos_only = ctx_n = ctx_ok = 0
    errors = []
    for g in gold:
        upos = target_pos(analyzer, g['text'], g['word'])
        sug = ranker.suggest(g['word'], g['text'], upos)
        want = set(g['gold'])
        got = sug['index'] if sug else None
        if got in want:
            ok += 1
        else:
            errors.append(f"{g['word']}: got {got} ({sug['tr'] if sug else '-'}), want {sorted(want)} "
                          f"[{upos or '?'}]")
        if 0 in want:
            first += 1
        senses = ranker.senses(g['word'])
        same = [i for i, s, _ in senses if OWN_POS_TO_UPOS.get(s.get('pos')) == upos]
        if (same[0] if same else 0) in want:
            pos_only += 1
        if sug and sug['basis'] == 'context':
            ctx_n += 1
            ctx_ok += got in want
    n = len(gold)
    engine_id = analyzer.engine_id + (f' + {encoder.engine_id}' if encoder else '')
    return {'engine': engine_id, 'instances': n, 'words': len({g['word'] for g in gold}),
            'accuracy': _ratio(ok, n), 'first_sense': _ratio(first, n), 'pos_only': _ratio(pos_only, n),
            'context_precision': _ratio(ctx_ok, ctx_n), 'context_coverage': _ratio(ctx_n, n), 'errors': errors}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--engine', default='both', choices=['builtin', 'spacy', 'both'])
    p.add_argument('--dict-db', default=os.path.join(repo_root(), 'assets', 'dict.db'))
    p.add_argument('--embeddings', action='store_true',
                   help='also measure with sentence embeddings (embeddings.py, setup_embeddings.sh)')
    p.add_argument('--json', action='store_true')
    a = p.parse_args(argv)
    gold, dictionary = load_gold(), EnTrDictionary(a.dict_db)
    encoders = [None]
    if a.embeddings:
        from lexicon.embeddings import SentenceEncoder
        encoders.append(SentenceEncoder())
    results = []
    for e in (['builtin', 'spacy'] if a.engine == 'both' else [a.engine]):
        for enc in encoders:
            try:
                results.append(evaluate(e, dictionary, gold, enc))
            except (ImportError, RuntimeError) as exc:
                print(f'{e}: not available ({exc}); see setup_spacy.sh', file=sys.stderr)
    dictionary.close()
    if a.json:
        print(json.dumps(results, ensure_ascii=False, indent=1))
        return
    keys = ['accuracy', 'first_sense', 'pos_only', 'context_precision', 'context_coverage']
    print('metric'.ljust(20) + ''.join(r['engine'][:60].ljust(62) for r in results))
    for k in keys:
        print(k.ljust(20) + ''.join(str(r[k]).ljust(62) for r in results))
    for r in results:
        print(f'\n[{r["engine"]}] errors:')
        for e in r['errors']:
            print('  ' + e)


if __name__ == '__main__':
    main()

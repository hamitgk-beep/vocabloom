"""Task 5E: part-of-speech numbers of the engine's own ewt-token dumps (dump_engine_test.dart), as in text_eval_test.dart."""
import json, sys
WANT = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'}


def pos_metrics(path):
    n = shown = ok = sure = sure_wrong = lem = lem_ok = 0
    for l in open(path, encoding='utf-8'):
        e = json.loads(l)
        if e['cat'] is None:
            lem += 1
            lem_ok += e['lemma_ctx'] == e['gold_lemma']
        if e['cat'] is not None or len(e['posOf']) < 2:
            continue
        n += 1
        if not e['shown'] or e['pos'] is None:
            continue
        shown += 1
        good = e['pos'] == WANT[e['gold_upos']]
        ok += good
        if e['conf'] == 'sure':
            sure += 1
            sure_wrong += not good
    return {'asked': n, 'shown': shown, 'pos_right': f'{ok}/{shown} = {100 * ok / max(1, shown):.1f}%',
            'sure': sure, 'sure_wrong': f'{sure_wrong}/{sure} = {100 * sure_wrong / max(1, sure):.1f}%',
            'lemma_of_meaning_shown': f'{lem_ok}/{lem} = {100 * lem_ok / max(1, lem):.1f}%'}


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(p, json.dumps(pos_metrics(p)))

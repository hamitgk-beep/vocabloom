"""Task 5E, stage 4: idiom or literal? Methods 1-3 and 5 on MAGPIE rows dumped by dump_engine_test.dart.

usage: python3 tools/nlp_research/idiom_eval.py DUMP_DIR SCORE_DIR dev
       python3 tools/nlp_research/idiom_eval.py DUMP_DIR SCORE_DIR final FINAL_SET   (uses idiom_tuned.json, once)

1. the engine as it is (engine_idiom in metrics.py);
2. bi-encoder similarity: margin = best idiom-meaning score - best word-by-word score;
3. cross-encoder / NLI / GlossBERT margin, same rule;
5. a small logistic-regression classifier on the engine's own scores and the model margins, trained on MAGPIE.
A three-way rule: idiom above hi, literal below lo, undecided between (shown as the engine's guess, never "sure").

Leakage: the classifier is cross-validated twice on the development pool, grouped by idiom (an idiom's sentences are
all in the same fold: the test idioms were never seen) and by sentence at random (other sentences of the same idiom
are in training). The gap between the two is the effect the task asks about.
"""
import json, os, sys, random, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metrics import load, idiom_metrics, fmt_idiom, IDIOM_HEAD, engine_idiom, wilson  # noqa
from eval_systems import scores_for, idiom_feats  # noqa

DEV = ['dev_mp_dev', 'dev_mp_fresh', 'dev_mp_fresh2', 'dev_mp_5a', 'dev_mp_5b']
MODELS = ['minilm', 'bge_small', 'mpnet', 'mminilm', 'ce_marco', 'ce_stsb', 'ce_bge', 'nli_xsmall', 'glossbert']
CATS = ['idioms', 'phrasal_verbs', 'prepositional_phrases', 'binomials', 'similes', 'collocations', 'proverbs']


def engine_margin(r):
    i = [c['score'] for c in r.get('cands') or [] if not c['lit']]
    l = [c['score'] for c in r.get('cands') or [] if c['lit']]
    if not i:
        return 0.0
    return max(i) - (max(l) if l else 0.0)


def feats(r, margins):
    x = [1.0, float(bool(r.get('literal'))), float(r.get('conf') == 'sure'), float(r.get('conf') == 'likely'), engine_margin(r),
         min(len(r['sentence'].split()), 40) / 40]
    x += [float(r.get('cat') == c) for c in CATS]
    for m in margins:
        x += [0.0 if m is None else m, float(m is None)]
    return x


def three_way(p, lo, hi):
    return 'idiom' if p >= hi else ('literal' if p <= lo else 'unsure')


def rule_system(rows_sc, lo, hi):
    def s(r):
        f = idiom_feats(r, rows_sc[r['k']])
        if f is None:
            return engine_idiom(r)
        d = three_way(f, lo, hi)
        return d, False
    return s


def veto_system(rows_sc, lo):
    """Deployable form: the model can only veto. Below lo the phrase is read word by word; otherwise the engine's
    own decision stands (so an uncertain case keeps today's "likely" idiom)."""
    def s(r):
        f = idiom_feats(r, rows_sc[r['k']])
        if f is not None and f < lo:
            return 'literal', False
        return engine_idiom(r)
    return s


def grid(vals):
    vals = sorted(v for v in vals if v is not None)
    if not vals:
        return [0.0]
    return [vals[int(q * (len(vals) - 1))] for q in [i / 40 for i in range(41)]]


def objective(t):
    # the error to cut is a literal sentence shown as an idiom; an idiom not shown costs less (the reader still has
    # the words' meanings and can tap the phrase list).
    return t['tp'] - 1.5 * t['fp']


def fit_lr(X, y, C=1.0):
    from sklearn.linear_model import LogisticRegression
    m = LogisticRegression(C=C, max_iter=2000, class_weight='balanced')
    m.fit(X, y)
    return m


def main():
    dump, score_dir, mode = sys.argv[1], sys.argv[2], sys.argv[3]
    tuned_path = os.path.join(os.path.dirname(dump.rstrip('/')), 'idiom_tuned.json')
    sets = DEV if mode == 'dev' else [sys.argv[4]]
    rows = {n: load(f'{dump}/{n}.engine.jsonl') for n in sets}
    scores = {m: {n: scores_for(score_dir, m, n) for n in sets} for m in MODELS}
    models = [m for m in MODELS if all(scores[m][n] is not None for n in sets)]
    if mode == 'dev':
        tuned = {'rules': {}, 'lr': {}}
        allr = [(n, r) for n in sets for r in rows[n] if r['label'] in 'il']
        print('### development pool (all five MAGPIE development sets together)\n' + IDIOM_HEAD)
        pool = [r for n in sets for r in rows[n]]
        print(fmt_idiom('1 engine', idiom_metrics(pool, engine_idiom)))
        # methods 2/3: margin rule, thresholds by objective on dev sets 1-4, reported on dev_mp_5b (inner check)
        for m in models:
            tune_sets = DEV[:-1]
            vals = [idiom_feats(r, scores[m][n][r['k']]) for n in tune_sets for r in rows[n] if r['found']]
            best = None
            g = grid(vals)
            for lo in g:
                for hi in g:
                    if hi < lo:
                        continue
                    tot = sum(objective(idiom_metrics(rows[n], rule_system(scores[m][n], lo, hi))) for n in tune_sets)
                    if best is None or tot > best[0]:
                        best = (tot, lo, hi)
            bv = None
            for lo in g:
                tot = sum(objective(idiom_metrics(rows[n], veto_system(scores[m][n], lo))) for n in tune_sets)
                if bv is None or tot > bv[0]:
                    bv = (tot, lo)
            tuned['rules'][m] = {'lo': best[1], 'hi': best[2], 'veto_lo': bv[1]}
            t = idiom_metrics(rows['dev_mp_5b'], rule_system(scores[m]['dev_mp_5b'], best[1], best[2]))
            print(fmt_idiom(f'margin {m} (tuned on 4 dev sets; shown: dev_mp_5b)', t))
            t = idiom_metrics(rows['dev_mp_5b'], veto_system(scores[m]['dev_mp_5b'], bv[1]))
            print(fmt_idiom(f'veto {m} (tuned on 4 dev sets; shown: dev_mp_5b)', t))
        print('\n(engine on dev_mp_5b alone):\n' + IDIOM_HEAD)
        print(fmt_idiom('1 engine', idiom_metrics(rows['dev_mp_5b'], engine_idiom)))
        # method 5: classifier, grouped vs random cross-validation on the pool (+ training pool when present)
        pool_rows = [r for r in pool if r['found'] and r['label'] in 'il']
        extra = 'train_mp'
        clf_models = models
        if os.path.exists(f'{dump}/{extra}.engine.jsonl'):
            tr = load(f'{dump}/{extra}.engine.jsonl')
            trs = {m: scores_for(score_dir, m, extra) for m in models}
            clf_models = [m for m in models if trs[m] is not None]
            if clf_models:
                for r in tr:
                    if r['found'] and r['label'] in 'il':
                        r['_m'] = [idiom_feats(r, trs[m][r['k']]) for m in clf_models]
                        pool_rows.append(r)
        name_of = {}
        for n in sets:
            for r in rows[n]:
                if r['found'] and r['label'] in 'il':
                    r['_m'] = [idiom_feats(r, scores[m][n][r['k']]) for m in clf_models]
        X = [feats(r, r['_m']) for r in pool_rows]
        y = [1 if r['label'] == 'i' else 0 for r in pool_rows]
        idioms = sorted({r['idiom'] for r in pool_rows})
        rnd = random.Random(7)
        rnd.shuffle(idioms)
        fold_of_idiom = {w: i % 5 for i, w in enumerate(idioms)}
        idx = list(range(len(pool_rows)))
        rnd.shuffle(idx)
        fold_rand = {k: n % 5 for n, k in enumerate(idx)}
        print(f'\n### classifier, 5-fold cross-validation on {len(pool_rows)} development+training sentences '
              f'({sum(y)} idiomatic, {len(y) - sum(y)} literal, {len(idioms)} idioms); probability thresholds 0.35/0.65')
        res = {}
        for split, fold in (('grouped by idiom (unseen idioms)', lambda k: fold_of_idiom[pool_rows[k]['idiom']]),
                            ('random (same idioms in training)', lambda k: fold_rand[k])):
            pred = [None] * len(pool_rows)
            for f in range(5):
                tr_i = [k for k in range(len(pool_rows)) if fold(k) != f]
                te_i = [k for k in range(len(pool_rows)) if fold(k) == f]
                mdl = fit_lr([X[k] for k in tr_i], [y[k] for k in tr_i])
                for k, p in zip(te_i, mdl.predict_proba([X[k] for k in te_i])[:, 1]):
                    pred[k] = p
            for k, r in enumerate(pool_rows):
                r['_p'] = pred[k]
            t = idiom_metrics(pool_rows, lambda r: (three_way(r['_p'], 0.35, 0.65), False))
            res[split] = t
            print(fmt_idiom(f'5 classifier, CV {split}', t))
            for lo in (0.2, 0.3, 0.4, 0.5):
                tv = idiom_metrics(pool_rows, lambda r: ('literal', False) if r['_p'] <= lo else engine_idiom(r))
                print(fmt_idiom(f'5 classifier veto p<={lo}, CV {split}', tv))
        print(fmt_idiom('1 engine, same sentences', idiom_metrics(pool_rows, engine_idiom)))
        # Text-feature classifier: bag of words of the sentence (can memorise idioms' typical contexts).
        from sklearn.feature_extraction.text import TfidfVectorizer
        from sklearn.linear_model import LogisticRegression
        from scipy.sparse import hstack, csr_matrix
        for split, fold in (('grouped by idiom (unseen idioms)', lambda k: fold_of_idiom[pool_rows[k]['idiom']]),
                            ('random (same idioms in training)', lambda k: fold_rand[k])):
            pred = [None] * len(pool_rows)
            for f in range(5):
                tr_i = [k for k in range(len(pool_rows)) if fold(k) != f]
                te_i = [k for k in range(len(pool_rows)) if fold(k) == f]
                vec = TfidfVectorizer(min_df=2, ngram_range=(1, 2))
                A = vec.fit_transform([pool_rows[k]['sentence'] for k in tr_i])
                B = vec.transform([pool_rows[k]['sentence'] for k in te_i])
                A = hstack([A, csr_matrix([X[k] for k in tr_i])])
                B = hstack([B, csr_matrix([X[k] for k in te_i])])
                mdl = LogisticRegression(C=1.0, max_iter=3000, class_weight='balanced').fit(A, [y[k] for k in tr_i])
                for k, p in zip(te_i, mdl.predict_proba(B)[:, 1]):
                    pred[k] = p
            for k, r in enumerate(pool_rows):
                r['_p'] = pred[k]
            print(fmt_idiom(f'5b words+features classifier, CV {split}', idiom_metrics(pool_rows, lambda r: (three_way(r['_p'], 0.35, 0.65), False))))
        # final classifier: all pool rows
        mdl = fit_lr(X, y)
        tuned['lr'] = {'models': clf_models, 'coef': mdl.coef_[0].tolist(), 'intercept': float(mdl.intercept_[0]), 'lo': 0.35, 'hi': 0.65,
                       'veto_lo': float(os.environ.get('VETO_LO', '0.3')), 'n_train': len(X)}
        json.dump(tuned, open(tuned_path, 'w'), indent=1)
    else:
        import math
        tuned = json.load(open(tuned_path))
        n = sets[0]
        print(f'### {n}\n' + IDIOM_HEAD)
        print(fmt_idiom('1 engine', idiom_metrics(rows[n], engine_idiom)))
        for m, t in tuned['rules'].items():
            if scores[m][n] is not None:
                print(fmt_idiom(f'margin {m}', idiom_metrics(rows[n], rule_system(scores[m][n], t['lo'], t['hi']))))
        lr = tuned['lr']
        if all(scores[m][n] is not None for m in lr['models']):
            def sysf(r):
                x = feats(r, [idiom_feats(r, scores[m][n][r['k']]) for m in lr['models']])
                z = sum(a * b for a, b in zip(lr['coef'], x)) + lr['intercept']
                return three_way(1 / (1 + math.exp(-z)), lr['lo'], lr['hi']), False
            print(fmt_idiom('5 classifier', idiom_metrics(rows[n], sysf)))

            def _p_of(r):
                x = feats(r, [idiom_feats(r, scores[m][n][r['k']]) for m in lr['models']])
                z = sum(a * b for a, b in zip(lr['coef'], x)) + lr['intercept']
                return 1 / (1 + math.exp(-z))
            print(fmt_idiom(f'5 classifier veto p<={lr["veto_lo"]}', idiom_metrics(rows[n], lambda r: ('literal', False) if r['found'] and _p_of(r) <= lr['veto_lo'] else engine_idiom(r))))
        for m, t in tuned['rules'].items():
            if scores[m][n] is not None and 'veto_lo' in t:
                print(fmt_idiom(f'veto {m}', idiom_metrics(rows[n], veto_system(scores[m][n], t['veto_lo']))))


if __name__ == '__main__':
    main()

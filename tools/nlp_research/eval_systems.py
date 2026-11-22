"""Task 5E, stages 3, 4 and 6: systems A-G on the dumped rows, with the model scores of score_senses.py.

usage: python3 tools/nlp_research/eval_systems.py DUMP_DIR SCORE_DIR MODE [args]
  MODE dev:   tunes every free setting on the development sets and prints the tables (writes DUMP_DIR/../tuned.json)
  MODE final: reads tuned.json (nothing is tuned) and prints the tables for the final sets, once.

Sense systems (rows from SemCor / Senseval / SemEval):
  A  the engine as it is.
  C/D/E  the engine's candidates re-ranked by engine score + lam * softmax(model score / T); lam and T chosen on dev.
     Confidence is never raised: a row is "sure" only when the engine said sure AND the model's own first choice is
     the engine's choice (agreement gate). Review cards are graded only when the engine graded them AND the model's
     first choice is the meaning the engine graded with.
  *-gate  the engine's own choice, with only the agreement gate (no re-ranking): shows what the gate alone does.
Idiom systems (MAGPIE rows): see idiom_* below.
"""
import json, math, os, sys, itertools, collections

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metrics import *  # noqa


def scores_for(score_dir, model, name):
    p = f'{score_dir}/{model}/{name}.json'
    return json.load(open(p))['scores'] if os.path.exists(p) else None


def softmax(xs, T):
    v = [x for x in xs if x is not None]
    if not v:
        return [None] * len(xs)
    mx = max(v)
    e = [math.exp((x - mx) / T) if x is not None else None for x in xs]
    s = sum(x for x in e if x is not None)
    return [x / s if x is not None else None for x in e]


def model_top(row, sc):
    best = None
    for c, s in zip(row['cands'], sc):
        if s is not None and c.get('tr') and (best is None or s > best[1]):
            best = (c, s)
    return best[0] if best else None


def make_sense_system(lam, T, gate=True, rerank=True):
    def system(row, sc):
        b, conf = engine(row)
        if b is None or conf == 'none' or sc is None:
            return b, conf
        top = model_top(row, sc)
        chosen = b
        if rerank and lam > 0:
            p = softmax(sc, T)
            best = None
            for c, pi in zip(row['cands'], p):
                if not c.get('tr'):
                    continue
                v = c['score'] + lam * (pi if pi is not None else 0)
                if best is None or v > best[1]:
                    best = (c, v)
            if best and best[0]['id'] != b['id']:
                chosen = best[0]
        agree = top is not None and top['id'] == b['id']
        if chosen is not b:
            return chosen, 'likely'
        if gate and conf == 'sure' and not agree:
            return chosen, 'likely'
        return chosen, conf
    return system


def pos_for(pos_dir, tagger, name):
    p = f'{pos_dir}/{tagger}/{name}.json'
    return json.load(open(p))['pos'] if os.path.exists(p) else None


def with_pos(base, pos_rows):
    """System B: the engine's candidates re-chosen by the tagger's part of speech; a choice of another part of speech
    than the tagger's is never "sure"; a word the tagger calls a name keeps no "sure" common meaning."""
    def system(row, sc):
        b, conf = base(row, sc)
        sp = pos_rows[row['k']] if pos_rows else None
        if b is None or conf == 'none' or sp is None:
            return b, conf
        if sp == 'propn':
            return b, 'likely' if conf == 'sure' else conf
        if sp in ('n', 'v', 'a', 'r') and b.get('pos') and b['pos'] != sp:
            alt = [c for c in row['cands'] if c.get('pos') == sp and c.get('tr')]
            if alt:
                return max(alt, key=lambda c: c['score']), 'likely'
            return b, 'likely' if conf == 'sure' else conf
        return b, conf
    return system


def run_sense(rows, sc, system):
    def sysf(r):
        return system(r, sc[r['k']] if sc else None)

    def fitf(r, b, conf):
        f = r.get('fit')
        if not f or f['fit'] != 'confirmed':
            return None
        if sc is not None and sc[r['k']] is not None:
            top = model_top(r, sc[r['k']])
            if top is not None and top['id'] != f['best']:
                return None
        return bool(f['ok'])
    return sense_metrics(rows, sysf, fitf)


def objective(m):
    # Right senses gained, with every wrong "sure" counting double and every wrong graded card triple.
    return m['ok'] + m['acc_ok'] - 2 * (m['sure'] - m['sure_ok']) - 3 * (m['fit_conf'] - m['fit_ok'])


SENSE_MODELS = ['minilm', 'bge_small', 'mpnet', 'mminilm', 'ce_marco', 'ce_stsb', 'ce_bge', 'nli_xsmall', 'glossbert']
LAMS = [0, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 3.0]
TS = [0.02, 0.05, 0.1, 0.5, 1.0, 3.0]


def tune_sense(dump, score_dir, dev_sets):
    out = {}
    rows = {n: load(f'{dump}/{n}.engine.jsonl') for n in dev_sets}
    for model in SENSE_MODELS:
        scs = {n: scores_for(score_dir, model, n) for n in dev_sets}
        if any(v is None for v in scs.values()):
            continue
        best = None
        for lam, T in itertools.product(LAMS, TS):
            sys_ = make_sense_system(lam, T)
            tot = sum(objective(run_sense(rows[n], scs[n], sys_)) for n in dev_sets)
            if best is None or tot > best[0]:
                best = (tot, lam, T)
        out[model] = {'lam': best[1], 'T': best[2], 'objective': best[0]}
    return out


# ---------------------------------------------------------------- idioms

def idiom_feats(row, sc):
    """Model margin: best idiom-sense score minus best word-by-word score (None when either side has no score)."""
    if sc is None:
        return None
    i = [s for c, s in zip(row['cands'], sc) if s is not None and not c['lit']]
    l = [s for c, s in zip(row['cands'], sc) if s is not None and c['lit']]
    if not i:
        return None
    return max(i) - (max(l) if l else min(i) - 1.0)


def make_idiom_system(sc_rows, lo, hi, use_engine=True):
    """idiom if margin > hi, literal if margin < lo, otherwise the engine's decision as 'unsure' (or the engine's own)."""
    def system(r):
        d0, sure0 = engine_idiom(r)
        f = idiom_feats(r, sc_rows[r['k']]) if sc_rows else None
        if f is None:
            return d0, sure0
        if f > hi:
            return 'idiom', False if not use_engine else (sure0 and d0 == 'idiom')
        if f < lo:
            return 'literal', False
        return ('unsure', False)
    return system


def idiom_objective(t):
    # literal sentences shown as idioms are the error to cut; idioms missed are the price.
    return t['tp'] - 1.5 * t['fp']


if __name__ == '__main__':
    dump, score_dir, mode = sys.argv[1], sys.argv[2], sys.argv[3]
    tuned_path = os.path.join(os.path.dirname(dump.rstrip('/')), 'tuned.json')
    if mode == 'dev':
        dev = ['dev_semcor5a', 'dev_semcor5b']
        tuned = {'sense': tune_sense(dump, score_dir, dev)}
        tuned['sense_se07'] = tune_sense(dump, score_dir, ['dev_se07'])
        json.dump(tuned, open(tuned_path, 'w'), indent=1)
        print(json.dumps(tuned, indent=1))
    for n in (['dev_semcor5a', 'dev_semcor5b', 'dev_se07'] if mode == 'dev' else sys.argv[4:]):
        rows = load(f'{dump}/{n}.engine.jsonl')
        tuned = json.load(open(tuned_path))
        print(f'\n### {n}\n' + SENSE_HEAD)
        print(fmt_sense('A engine', sense_metrics(rows, engine)))
        pos_dir = os.path.join(os.path.dirname(dump.rstrip('/')), 'pos')
        for tg in ('en_core_web_sm', 'en_core_web_md', 'en_core_web_trf', 'perceptron'):
            pr = pos_for(pos_dir, tg, n)
            if pr is None:
                continue
            m = run_sense(rows, None, with_pos(lambda r, sc: engine(r), pr))
            gp = sum(1 for r, (k, shown, ok, conf) in zip(rows, m['per_row']) if shown)
            print(fmt_sense(f'B engine + {tg} POS', m))
            for model in ('minilm', 'bge_small', 'ce_marco', 'glossbert'):
                sc = scores_for(score_dir, model, n)
                if sc is not None:
                    print(fmt_sense(f'B {tg} + {model} gate', run_sense(rows, sc, with_pos(make_sense_system(0, 1, rerank=False), pr))))
        for model in SENSE_MODELS:
            sc = scores_for(score_dir, model, n)
            if sc is None or model not in tuned['sense']:
                continue
            t = tuned['sense'][model]
            print(fmt_sense(f'{model} gate only', run_sense(rows, sc, make_sense_system(0, 1, rerank=False))))
            print(fmt_sense(f'{model} lam={t["lam"]} T={t["T"]}', run_sense(rows, sc, make_sense_system(t['lam'], t['T']))))
            print(fmt_sense(f'{model} model alone', run_sense(rows, sc, make_sense_system(1000, 0.02))))

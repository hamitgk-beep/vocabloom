"""Task 5E: is the model's agreement informative, or does the gate only make fewer "sure" answers?

usage: python3 tools/nlp_research/gate_analysis.py DUMP_DIR SCORE_DIR MODEL SET [SET ...]

Among the rows the engine calls "sure", compares those where the model's own first choice is the engine's choice
(kept sure by the gate) with those where it is not (lowered to likely). A random gate would keep the same share of
right answers in both groups; Fisher's exact test says how likely the observed difference is by chance.
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metrics import load, engine  # noqa
from eval_systems import scores_for, model_top  # noqa
from scipy.stats import fisher_exact

dump, score_dir, model, sets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
k_ok = k_n = d_ok = d_n = 0
tk_ok = tk_n = td_ok = td_n = 0
for n in sets:
    rows = load(f'{dump}/{n}.engine.jsonl')
    sc = scores_for(score_dir, model, n)
    for r in rows:
        b, conf = engine(r)
        if b is None or conf != 'sure' or not b.get('tr'):
            continue
        top = model_top(r, sc[r['k']])
        agree = top is not None and top['id'] == b['id']
        ok = b['id'] in r['gold']
        if agree:
            k_n += 1; k_ok += ok
        else:
            d_n += 1; d_ok += ok
        if r['gtr']:
            t = bool(b.get('trOk'))
            if agree:
                tk_n += 1; tk_ok += t
            else:
                td_n += 1; td_ok += t
p = fisher_exact([[k_ok, k_n - k_ok], [d_ok, d_n - d_ok]])[1]
pt = fisher_exact([[tk_ok, tk_n - tk_ok], [td_ok, td_n - td_ok]])[1]
print(f'{model} on {"+".join(sets)}: engine-sure rows kept {k_n} (right sense {k_ok}, {100 * k_ok / max(1, k_n):.1f}%), '
      f'lowered {d_n} (right {d_ok}, {100 * d_ok / max(1, d_n):.1f}%), Fisher p = {p:.3g}; '
      f'Turkish: kept {tk_ok}/{tk_n} = {100 * tk_ok / max(1, tk_n):.1f}%, lowered {td_ok}/{td_n} = {100 * td_ok / max(1, td_n):.1f}%, p = {pt:.3g}')

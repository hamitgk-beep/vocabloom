"""Task 5E: tables of the one final run (see run_final.sh). Reads the settings chosen on the development sets; tunes
nothing. usage: python3 tools/nlp_research/final_report.py WORK_DIR GATE_MODEL IDIOM_MODEL"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from metrics import *  # noqa
from eval_systems import scores_for, make_sense_system, run_sense  # noqa
from idiom_eval import veto_system  # noqa

W, gate, idiom = sys.argv[1:4]
wsd = sys.argv[4] if len(sys.argv) > 4 else None  # research system E: a WSD model re-ranks (settings from dev_se07)
F = f'{W}/final'
it = json.load(open(f'{W}/idiom_tuned.json'))
veto_lo = it['rules'][idiom]['veto_lo']
out = []
rowsA = load(f'{F}/dumpA/final5e_wsd.engine.jsonl')
rowsG0 = load(f'{F}/dumpG0/final5e_wsd.engine.jsonl')
scG0 = scores_for(f'{F}/scores_dumpG0', gate, 'final5e_wsd')
scA = scores_for(f'{F}/scores_dumpA', gate, 'final5e_wsd')
mA = sense_metrics(rowsA, engine)
mG0 = sense_metrics(rowsG0, engine)
mAg = run_sense(rowsA, scA, make_sense_system(0, 1, rerank=False))
mG = run_sense(rowsG0, scG0, make_sense_system(0, 1, rerank=False))
out.append('## Final: Senseval-2/3 + SemEval-2013/15 (514 rows; 279 with a KeNet Turkish reference)\n')
out.append(SENSE_HEAD)
for name, m in (('A engine (main)', mA), ('G0 engine + EWT tagger', mG0), (f'G0 + {gate} gate = G (sense part)', mG)):
    out.append(fmt_sense(name, m))
mE = None
if wsd:
    tE = json.load(open(f'{W}/tuned.json'))['sense_se07'][wsd]
    scE = scores_for(f'{F}/scores_dumpG0', wsd, 'final5e_wsd')
    sysE = make_sense_system(tE['lam'], tE['T'])
    mE = run_sense(rowsG0, scE, sysE)
    out.append(fmt_sense(f'E = G0 + {wsd} re-rank (lam={tE["lam"]}, T={tE["T"]}) and gate', mE))
    out.append(fmt_sense(f'G0 + {wsd} gate only', run_sense(rowsG0, scE, make_sense_system(0, 1, rerank=False))))
out.append(f'\n(the gate alone on A, for the record: {fmt_sense(f"A + {gate} gate", mAg)})\n')


def paired(m1, m2, key):
    a = {k: (shown and ok) for k, shown, ok, conf in m1['per_row']}
    b = {k: (shown and ok) for k, shown, ok, conf in m2['per_row']}
    return mcnemar(a, b)


def wrong_sure(m):
    return {k: (shown and conf == 'sure' and not ok) for k, shown, ok, conf in m['per_row']}


x, y, p = paired(mA, mG0, 'ok')
out.append(f'Paired (McNemar, right English sense): G0 right where A wrong {x}, A right where G0 wrong {y}, p = {p:.3g}')
x, y, p = mcnemar({k: not v for k, v in wrong_sure(mA).items()}, {k: not v for k, v in wrong_sure(mG).items()})
out.append(f'Paired (McNemar, rows NOT shown wrongly as sure): G avoids where A errs {x}, the reverse {y}, p = {p:.3g}')



def tr_ok(rows, f, sc):
    d = {}
    for r in rows:
        if not r['gtr']:
            continue
        b, conf = f(r, sc[r['k']] if sc is not None else None)
        d[r['k']] = bool(b and b.get('trOk'))
    return d


trA = tr_ok(rowsA, lambda r, _: engine(r), None)
trG0 = tr_ok(rowsG0, lambda r, _: engine(r), None)
x, y, p = mcnemar(trA, trG0)
out.append(f'Paired (McNemar, KeNet Turkish of the shown meaning, rows with a reference): G0 right where A wrong {x}, the reverse {y}, p = {p:.3g}')
if wsd:
    trE = tr_ok(rowsG0, sysE, scE)
    x, y, p = mcnemar(trA, trE)
    out.append(f'Paired (McNemar, KeNet Turkish): E right where A wrong {x}, the reverse {y}, p = {p:.3g}; '
               f'A {sum(trA.values())}/{len(trA)}, E {sum(trE.values())}/{len(trE)}')
    x, y, p = paired(mA, mE, 'ok')
    out.append(f'Paired (McNemar, right English sense): E right where A wrong {x}, the reverse {y}, p = {p:.3g}')

# Turkish: wrong among sure, row list for the manual synonym check
out.append('\n### Rows shown as sure whose Turkish is not KeNet\'s (for the manual check)\n')
for name, rows, sysf in (('A', rowsA, None), ('G', rowsG0, scG0)):
    for r in rows:
        if sysf is None:
            b, conf = engine(r)
        else:
            b, conf = make_sense_system(0, 1, rerank=False)(r, scG0[r['k']])
        if b and conf == 'sure' and r['gtr'] and b.get('tr') and not b.get('trOk'):
            out.append(f'- {name} | {r["lemma"]} ({r["pos"]}) | shown: {", ".join(b["tr"][:3])} | KeNet: {r["gtr"][:60]} | {r["sentence"][:140]}')

# idioms
out.append('\n## Final: MAGPIE, idioms never seen before (300 idiomatic / 110 literal sentences)\n')
out.append(IDIOM_HEAD)
mpA = load(f'{F}/dumpA/final5e_magpie.engine.jsonl')
mpG0 = load(f'{F}/dumpG0/final5e_magpie.engine.jsonl')
sci = scores_for(f'{F}/scores_dumpG0', idiom, 'final5e_magpie')
out.append(fmt_idiom('A engine (main)', idiom_metrics(mpA, engine_idiom)))
out.append(fmt_idiom('G0 engine + EWT tagger', idiom_metrics(mpG0, engine_idiom)))
out.append(fmt_idiom(f'G = G0 + {idiom} veto (margin < {veto_lo:.3f})', idiom_metrics(mpG0, veto_system(sci, veto_lo))))
# by variant type
import collections
by = collections.defaultdict(lambda: [0, 0, 0, 0])
vs = veto_system(sci, veto_lo)
for rA, rG in zip(mpA, mpG0):
    v = rA['extra']
    b = by[(v, rA['label'])]
    b[0] += 1
    b[1] += rA['found']
    b[2] += engine_idiom(rA)[0] == 'idiom' if rA['found'] else 0
    b[3] += vs(rG)[0] == 'idiom' if rG['found'] else 0
out.append('\n| variant | label | rows | phrase found | A shown as idiom | G shown as idiom |\n|---|---|---|---|---|---|')
for (v, l), b in sorted(by.items()):
    out.append(f'| {v} | {l} | {b[0]} | {b[1]} | {b[2]} | {b[3]} |')
# speed
us = sorted(r['us'] for r in rowsA if r.get('us') is not None)
usg = sorted(r['us'] for r in rowsG0 if r.get('us') is not None)
out.append(f'\nEngine resolve time on the final WSD rows (Linux x64 desktop CPU, Dart VM in flutter test): A median {us[len(us) // 2]} µs, '
           f'p95 {us[int(len(us) * 0.95)]} µs; G0 median {usg[len(usg) // 2]} µs, p95 {usg[int(len(usg) * 0.95)]} µs')
print('\n'.join(out))
open(f'{F}/FINAL_TABLES.md', 'w').write('\n'.join(out) + '\n')

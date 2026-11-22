"""Task 5E: the metrics, computed the same way for every system on the rows dumped by dump_engine_test.dart.

A system is a function row -> (candidate dict or None, confidence 'sure' | 'likely' | 'none').
The definitions follow tools/eval/holdout_eval_test.dart (Task 5B), so the current engine gives the same numbers
here as there (checked by check_baseline() below).
"""
import json
import math


def load(path):
    return [json.loads(l) for l in open(path, encoding='utf-8')]


def engine(row):
    """System A: the current SenseEngine as it is."""
    if row.get('i', -1) < 0 or not row.get('shown'):
        return None, 'none'
    return row.get('bestc'), row['conf']


def pc(a, b):
    return '-' if b == 0 else f'{100 * a / b:.1f}%'


def wilson(k, n, z=1.96):
    """95% Wilson interval of k/n, in percent."""
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (100 * (c - h) / d, 100 * (c + h) / d)


def sense_metrics(rows, system, fit_system=None):
    """English sense, Turkish and review-card numbers of [system] on WSD/SemCor rows."""
    m = dict(n=len(rows), shown=0, ok=0, sure=0, sure_ok=0, likely=0, likely_ok=0, tr_rows=0, tr_shown=0, tr_ok=0, tr_syn=0,
             tr_sure=0, tr_sure_ok=0, tr_sure_syn=0, tr_sure_wrong_any=0, first_ok=0, first_rows=0, first_tr_ok=0, fit_conf=0, fit_ok=0,
             acc_ok=0, us=[])
    per_row = []
    for r in rows:
        if r.get('first'):
            m['first_rows'] += 1
            if r['first'] in r['gold']:
                m['first_ok'] += 1
        b, conf = system(r) if r.get('i', -1) >= 0 else (None, 'none')
        shown = b is not None and conf != 'none' and bool(b.get('tr'))
        ok = shown and b['id'] in r['gold']
        if r.get('us') is not None:
            m['us'].append(r['us'])
        if shown:
            m['shown'] += 1
            if conf == 'sure':
                m['sure'] += 1
                m['sure_ok'] += ok
            else:
                m['likely'] += 1
                m['likely_ok'] += ok
        m['ok'] += ok
        # Accepted = the right synset, or (rows with a KeNet reference) Turkish that KeNet gives the gold synset or a
        # synonym of it: a right translation can come from an own-dictionary sense that has no WordNet id.
        tr_ok = shown and bool(b.get('trOk'))
        tr_syn = shown and bool(b.get('trSyn') or b.get('trOk'))
        if r['gtr']:
            m['tr_rows'] += 1
            if r.get('firstTrOk'):
                m['first_tr_ok'] += 1
            if shown:
                m['tr_shown'] += 1
                m['tr_ok'] += tr_ok
                m['tr_syn'] += tr_syn
                if conf == 'sure':
                    m['tr_sure'] += 1
                    m['tr_sure_ok'] += tr_ok
                    m['tr_sure_syn'] += tr_syn
        if shown:
            m['acc_ok'] += ok or tr_syn
        per_row.append((r['k'], shown, ok, conf))
        f = (fit_system or fit_engine)(r, b, conf) if r['gtr'] else None
        if f is not None:
            m['fit_conf'] += 1
            m['fit_ok'] += f
    m['per_row'] = per_row
    return m


def fit_engine(row, best, conf):
    """Review-card rule of the current engine: None = not graded, else whether the graded meaning is right."""
    f = row.get('fit')
    if not f or f['fit'] != 'confirmed':
        return None
    return bool(f['ok'])


def fmt_sense(name, m):
    s = m['us']
    s = sorted(s)
    med = s[len(s) // 2] if s else 0
    wrong_sure = m['sure'] - m['sure_ok']
    lo, hi = wilson(m['tr_sure'] - m['tr_sure_ok'], m['tr_sure'])
    return (f"| {name} | {m['n']} | {pc(m['shown'], m['n'])} | {pc(m['ok'], m['n'])} | {pc(m['ok'], m['shown'])} | "
            f"{pc(m['acc_ok'], m['shown'])} | {m['sure']} ({pc(m['sure'], m['n'])}) | {pc(m['sure_ok'], m['sure'])} | {pc(wrong_sure, m['n'])} | "
            f"{pc(m['tr_ok'], m['tr_shown'])} | {pc(m['tr_syn'], m['tr_shown'])} | "
            f"{m['tr_sure'] - m['tr_sure_ok']}/{m['tr_sure']} = {pc(m['tr_sure'] - m['tr_sure_ok'], m['tr_sure'])} [{lo:.0f}–{hi:.0f}] | "
            f"{m['tr_sure'] - m['tr_sure_syn']}/{m['tr_sure']} | {pc(m['first_ok'], m['n'])} | {pc(m['first_tr_ok'], m['tr_rows'])} | "
            f"{m['fit_conf']}, {pc(m['fit_ok'], m['fit_conf'])} |")


SENSE_HEAD = ('| system | rows | coverage | right sense (all) | right sense (shown) | accepted (shown) | sure (share) | sure right | '
              'WRONG sure (of all) | TR strict (shown) | TR syn (shown) | WRONG TR among sure, strict [95% CI] | wrong TR sure, syn-aware | '
              'first-sense right (all) | first-sense TR | cards graded, right |\n' + '|---' * 16 + '|')


def idiom_metrics(rows, system):
    """[system] row -> 'idiom' | 'literal' | 'unsure' (+ sure flag). Rows whose phrase the matcher did not find count as
    'not found' (a miss for idiomatic, a correct rejection for literal)."""
    t = dict(i=0, l=0, i_found=0, l_found=0, tp=0, fp=0, fn=0, tn=0, unsure_i=0, unsure_l=0, fp_sure=0, tp_sure=0)
    for r in rows:
        lab = r['label']
        if lab not in ('i', 'l'):
            continue
        t[lab] += 1
        if not r['found']:
            if lab == 'i':
                t['fn'] += 1
            else:
                t['tn'] += 1
            continue
        t[lab + '_found'] += 1
        d, sure = system(r)
        if d == 'idiom':
            if lab == 'i':
                t['tp'] += 1
                t['tp_sure'] += sure
            else:
                t['fp'] += 1
                t['fp_sure'] += sure
        elif d == 'literal':
            if lab == 'i':
                t['fn'] += 1
            else:
                t['tn'] += 1
        else:
            t['unsure_' + lab] += 1
            if lab == 'i':
                t['fn'] += 1
            else:
                t['tn'] += 1
    p = t['tp'] / (t['tp'] + t['fp']) if t['tp'] + t['fp'] else 0
    rc = t['tp'] / t['i'] if t['i'] else 0
    t['precision'], t['recall'] = p, rc
    t['f1'] = 2 * p * rc / (p + rc) if p + rc else 0
    t['lit_as_idiom'] = t['fp'] / t['l'] if t['l'] else 0
    return t


def fmt_idiom(name, t):
    lo, hi = wilson(t['fp'], t['l'])
    return (f"| {name} | {t['i']}/{t['l']} | {100 * t['precision']:.1f}% | {100 * t['recall']:.1f}% | {100 * t['f1']:.1f} | "
            f"{t['fp']}/{t['l']} = {100 * t['lit_as_idiom']:.1f}% [{lo:.0f}–{hi:.0f}] | {t['fp_sure']} | {t['unsure_i']}/{t['unsure_l']} |")


IDIOM_HEAD = ('| system | idiomatic/literal rows | idiom precision | idiom recall | F1 | literal read as idiom [95% CI] | '
              'literal read as idiom and SURE | undecided (idiomatic/literal) |\n' + '|---' * 8 + '|')


def engine_idiom(row):
    """System A for idioms: the expression's meaning is shown (not the word-by-word reading)."""
    if row.get('literal'):
        return 'literal', False
    if row.get('conf') == 'none' or not row.get('shownTr'):
        return 'unsure', False
    return 'idiom', row.get('conf') == 'sure'


def mcnemar(a_rows, b_rows):
    """Exact two-sided McNemar test on paired right/wrong outcomes (dict k -> bool). Returns (b_only, a_only, p)."""
    keys = a_rows.keys() & b_rows.keys()
    x = sum(1 for k in keys if b_rows[k] and not a_rows[k])
    y = sum(1 for k in keys if a_rows[k] and not b_rows[k])
    n = x + y
    if n == 0:
        return x, y, 1.0
    k = min(x, y)
    p = sum(math.comb(n, i) for i in range(0, k + 1)) / 2 ** n * 2
    return x, y, min(1.0, p)

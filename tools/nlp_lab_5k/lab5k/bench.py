"""Task 5K benchmark: same candidates (real Storilex matcher), same gold, every system; paired statistics.

usage: python -m lab5k.bench SET OUTDIR [--systems a,b,...]
SET: mini | streusle_dev | streusle_test | streusle_train | final5k. Inputs are read from OUTDIR (local, never
committed): <set>.tsv, <set>.baseline.jsonl (Dart trace), <set>.<engine>.jsonl (lab5k.engines), and for AMALGrAM
<set>.amalgram.groups.json. Writes OUTDIR/<set>.decisions.jsonl (common result schema) and <set>.metrics.json.
Character spans everywhere: 0-based start, exclusive end, on the sentence string.
"""
import json
import math
import os
import sys
from collections import Counter, defaultdict

from . import rules
from . import streusle_io

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT_ORDER = {c: i for i, c in enumerate(['conjunctions', 'phrasal_verbs', 'collocations', 'prepositional_phrases', 'proverbs',
                                          'discourse_markers', 'idioms', 'chunks', 'binomials', 'false_friends', 'modal_verbs',
                                          'irregular_verbs', 'dependent_prepositions', 'similes', 'polite_phrases',
                                          'informal_slang', 'confusables', 'uk_us'])}
PARSERS = ["spacy_sm", "spacy_md", "stanza", "udpipe_ewt25", "udpipe_bnosac21"]
SYSTEMS = (["baseline", "rules_noparser"] + [f"rules+{p}" for p in PARSERS]
           + ["rules+spacy_sm&udpipe_bnosac21", "amalgram_retrained"])
FILES = {"mini": "mini", "streusle_dev": "streusle/dev", "streusle_test": "streusle/test",
         "streusle_train": "streusle/train", "final5k": "final5k"}


def jl(p):
    return [json.loads(l) for l in open(p, encoding="utf-8")] if os.path.exists(p) else None


def load(setname, outdir):
    base = os.path.join(outdir, FILES[setname])
    texts = {}
    for l in open(base + ".tsv", encoding="utf-8"):
        if l.strip():
            i, t = l.rstrip("\n").split("\t", 1)
            texts[i] = t
    recs = {}
    for r in jl(base + ".baseline.jsonl"):
        r["text"] = texts[r["id"]]
        recs[r["id"]] = r
    parses = {}
    for e in PARSERS:
        rows = jl(f"{base}.{e}.jsonl")
        if rows is not None:
            parses[e] = {r["id"]: r["tokens"] for r in rows}
    am = None
    p = base + ".amalgram.groups.json"
    if os.path.exists(p):
        am = json.load(open(p))
    return recs, parses, am


def overlaps(a, b):
    return a[0] < b[1] and b[0] < a[1]


def cand_chars(rec, m):
    return [(rec["tokens"][i]["start"], rec["tokens"][i]["end"]) for i in m["tokens"]]


def amalgram_decide(rec, m, groups):
    """AMALGrAM as a filter: EXPR if one predicted MWE group (strong or weak) covers every candidate token."""
    if groups is None:
        return None
    ch = cand_chars(rec, m)
    for g in groups:
        if all(any(overlaps(c, gc) for gc in g) for c in ch):
            return ("EXPR", "amalgram-group")
    return ("LIT", "amalgram-no-group")


def run_system(name, rec, parses, am):
    ms = rec["matches"]
    multi = [k for k, m in enumerate(ms) if len(m["tokens"]) >= 2]
    if name == "baseline":
        dec = [(rules.baseline_decision(m), "baseline") for m in ms]
        win = rec["winners"]
    elif name == "amalgram_retrained":
        groups = am.get(rec["id"]) if am is not None else None
        if am is None or groups is None:
            return None
        dec = [amalgram_decide(rec, m, groups) if len(m["tokens"]) >= 2 else (rules.baseline_decision(m), "single") for m in ms]
        win = rules.winners(rec, ms, dec, CAT_ORDER)
    else:
        if name == "rules_noparser":
            parse, use = None, False
        elif "&" in name:
            a, b = name.split("+", 1)[1].split("&")
            if a not in parses or b not in parses:
                return None
            da = run_system("rules+" + a, rec, parses, am)
            db = run_system("rules+" + b, rec, parses, am)
            dec = []
            for x, y in zip(da[0], db[0]):
                dec.append(x if x[0] == y[0] else ("UNDECIDED", "disagree:" + x[1] + "|" + y[1]))
            return dec, rules.winners(rec, ms, dec, CAT_ORDER)
        else:
            e = name.split("+", 1)[1]
            if e not in parses or rec["id"] not in parses[e]:
                return None
            parse, use = rules.Parse(parses[e][rec["id"]], rec["tokens"]), True
        dec = [rules.decide(rec, m, parse, use_parser=use) if len(m["tokens"]) >= 2 else (rules.baseline_decision(m), "single")
               for m in ms]
        dec = rules.resolve_overlaps(rec, ms, dec, parse, use_parser=use)
        win = rules.winners(rec, ms, dec, CAT_ORDER)
    return dec, win


# ------------------------------------------------------------------ gold items per set
def items_mini(recs):
    g = json.load(open(os.path.join(HERE, "data", "mini_suite_5k.gold.json")))["items"]
    out = []
    for it in g:
        rec = recs[it["id"]]
        k = None
        for j, m in enumerate(rec["matches"]):
            if m["phrase"] == it["phrase"] and any(overlaps(c, tuple(s)) for c in cand_chars(rec, m) for s in it["spans"]):
                k = j
        out.append({"item": f"{it['id']}:{it['phrase']}", "sid": it["id"], "gold": it["label"], "cand": k,
                    "gold_spans": [tuple(s) for s in it["spans"]], "phrase": it["phrase"]})
    return [o for o in out if o["gold"] != "AMBIG"]


def items_final5k():
    rows = []
    p = "/home/user/lab5k/sets/5k/final5k_magpie.tsv"
    p = os.environ.get("NLP_5K_FINAL", p)
    for l in open(p, encoding="utf-8"):
        if l.startswith("#") or not l.strip():
            continue
        idiom, lab, cat, mid, s, spans, vt, conf = l.rstrip("\n").split("\t")
        rows.append((idiom, lab, cat, mid, [tuple(map(int, x.split(":"))) for x in spans.split(",")], vt))
    return rows


def items_magpie(recs):
    out = []
    for idiom, lab, cat, mid, spans, vt in items_final5k():
        rec = recs.get("M" + mid)
        if rec is None:
            continue
        k = None
        for j, m in enumerate(rec["matches"]):
            if m["phrase"] == idiom and any(overlaps(c, s) for c in cand_chars(rec, m) for s in spans):
                k = j
        out.append({"item": f"M{mid}:{idiom}", "sid": "M" + mid, "gold": "EXPR" if lab == "i" else "LIT", "cand": k,
                    "gold_spans": spans, "phrase": idiom, "variant": vt, "cat": cat})
    return out


def streusle_map(rec, st):
    """Storilex token -> STREUSLE token indexes (char overlap)."""
    return [[k for k, t in enumerate(st["tokens"]) if overlaps((s["start"], s["end"]), (t["start"], t["end"]))] for s in rec["tokens"]]


def items_streusle(recs, split):
    gold = {s["id"]: s for s in streusle_io.load(split)}
    out = []
    for sid, rec in recs.items():
        st = gold[sid]
        mp = streusle_map(rec, st)
        mwes = [set(m["toks"]) for m in st["mwes"]]
        seen = set()
        for j, m in enumerate(rec["matches"]):
            if len(m["tokens"]) < 2:
                continue
            key = (m["phrase"], tuple(m["tokens"]))
            if key in seen:
                continue
            seen.add(key)
            toks = set(x for i in m["tokens"] for x in mp[i])
            lab = "EXPR" if any(toks <= g for g in mwes) else "LIT"
            out.append({"item": f"{sid}:{m['phrase']}:{m['tokens']}", "sid": sid, "gold": lab, "cand": j,
                        "phrase": m["phrase"], "cat": m["cat"]})
    return out, gold


# ------------------------------------------------------------------ metrics
def wilson(k, n, z=1.96):
    if n == 0:
        return [None, None]
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return [round(c - h, 3), round(c + h, 3)]


def mcnemar_exact(b, c):
    """Two-sided exact binomial p for discordant pairs b (sys wrong->right) and c (right->wrong)."""
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    p = sum(math.comb(n, i) for i in range(0, k + 1)) / 2 ** n
    return min(1.0, 2 * p)


def paired_diff_ci(b, c, n, z=1.96):
    """95% Wald CI for the difference of paired proportions (new - old accuracy)."""
    if n == 0:
        return [None, None]
    d = (b - c) / n
    se = math.sqrt(max((b + c) / n - d * d, 0) / n)
    return [round(d - z * se, 3), round(d + z * se, 3)]


def prf(tp, fp, fn):
    p = tp / (tp + fp) if tp + fp else None
    r = tp / (tp + fn) if tp + fn else None
    f = 2 * p * r / (p + r) if p and r else (0.0 if p is not None and r is not None else None)
    return {"P": None if p is None else round(p, 3), "R": None if r is None else round(r, 3), "F1": None if f is None else round(f, 3)}


def item_view(it, rec, out):
    """Decision of one system on one gold item."""
    k = it["cand"]
    if k is None:
        return {"dec": "NONE", "rule": "no-candidate", "shown": False, "conf": None, "card": False, "exact": False, "tr": "n/a"}
    dec, win = out
    d, rule = dec[k]
    m = rec["matches"][k]
    shown = d in ("EXPR", "UNDECIDED") and any(w == k for w in win)
    conf = m["conf"] if d == "EXPR" else ("none" if d == "UNDECIDED" else None)
    if d == "EXPR" and rule.endswith(rules.CAP) and conf == "sure":
        conf = "likely"
    card = d == "EXPR" and shown and conf == "sure" and bool(m["tr_shown"]) and not m["draft"]
    exact = shown and all(w == k for i, w in enumerate(win) if i in m["tokens"])
    if it.get("gold_spans"):
        exact = exact and sorted(cand_chars(rec, m)) == sorted(map(tuple, it["gold_spans"])) if len(it["gold_spans"]) == len(m["tokens"]) else exact and _same_cover(rec, m, it["gold_spans"])
    tr = "var" if (m.get("dict_tr") or "").strip() else ("taslak-yeterli-kaynak-yok" if m.get("dict_tr_draft") else "yok")
    return {"dec": d, "rule": rule, "shown": shown, "conf": conf, "card": card, "exact": exact, "tr": tr}


def _same_cover(rec, m, spans):
    ch = cand_chars(rec, m)
    return min(c[0] for c in ch) == min(s[0] for s in spans) and max(c[1] for c in ch) == max(s[1] for s in spans)


def score(items, views):
    """Two levels + safety metrics for one system."""
    pos = lambda v: v["dec"] == "EXPR"
    tp = sum(1 for it, v in zip(items, views) if it["gold"] == "EXPR" and pos(v))
    fp = sum(1 for it, v in zip(items, views) if it["gold"] != "EXPR" and pos(v))
    fn = sum(1 for it, v in zip(items, views) if it["gold"] == "EXPR" and not pos(v))
    neg = sum(1 for it in items if it["gold"] != "EXPR")
    gold_pos = sum(1 for it in items if it["gold"] == "EXPR")
    # level (i): detection of the expression span (shown, gold EXPR, exact span)
    shown = sum(1 for v in views if v["shown"])
    det_tp = sum(1 for it, v in zip(items, views) if it["gold"] == "EXPR" and v["shown"] and v["exact"])
    det = prf(det_tp, shown - det_tp, gold_pos - det_tp)
    s = {
        "n": len(items), "gold_expr": gold_pos, "gold_nonexpr": neg,
        "detect_exact_span": det,
        "idiom_vs_literal": {**prf(tp, fp, fn), "FPR": round(fp / neg, 3) if neg else None, "FPR_CI95": wilson(fp, neg),
                             "TP": tp, "FP": fp, "FN": fn},
        "undecided": sum(1 for v in views if v["dec"] == "UNDECIDED"),
        "no_candidate": sum(1 for v in views if v["dec"] == "NONE"),
        "wrong_sure": sum(1 for it, v in zip(items, views) if it["gold"] != "EXPR" and v["dec"] == "EXPR" and v["conf"] == "sure"),
        "wrong_card_approval": sum(1 for it, v in zip(items, views) if it["gold"] != "EXPR" and v["card"]),
        "idiom_missed": fn,
        "coverage_candidate": round(sum(1 for v in views if v["dec"] != "NONE") / len(items), 3) if items else None,
        "turkish_for_expr_decisions": dict(Counter(v["tr"] for v in views if v["dec"] == "EXPR")),
    }
    return s


def paired(items, base_views, views, base_cards=None):
    ok = lambda it, v: (v["dec"] == "EXPR") == (it["gold"] == "EXPR")
    c = Counter()
    for it, a, b in zip(items, base_views, views):
        c[("old_ok" if ok(it, a) else "old_wrong") + "/" + ("new_ok" if ok(it, b) else "new_wrong")] += 1
    b_ = c["old_wrong/new_ok"]
    c_ = c["old_ok/new_wrong"]
    blocked = sum(1 for it, a, v in zip(items, base_views, views) if it["gold"] == "EXPR" and a["card"] and not v["card"])
    return {"old_wrong_new_ok": b_, "old_ok_new_wrong": c_, "both_ok": c["old_ok/new_ok"], "both_wrong": c["old_wrong/new_wrong"],
            "mcnemar_exact_p": round(mcnemar_exact(b_, c_), 4), "acc_diff_CI95": paired_diff_ci(b_, c_, len(items)),
            "correct_cards_blocked": blocked}


def slices(items, views):
    by = defaultdict(lambda: defaultdict(list))
    for it, v in zip(items, views):
        n = len(it["phrase"].split())
        by["length"]["2" if n == 2 else "3" if n == 3 else "4+"].append((it, v))
        by["category"][it.get("cat") or "-"].append((it, v))
        first = it["phrase"].split()[0]
        cls = "be+" if first == "be" else "prep-initial" if first in rules.PARTICLES else "other"
        by["first_word"][cls].append((it, v))
        if it.get("variant"):
            by["magpie_variant"][it["variant"]].append((it, v))
    out = {}
    for k, d in by.items():
        out[k] = {}
        for name, pairs in sorted(d.items()):
            its, vs = [p[0] for p in pairs], [p[1] for p in pairs]
            s = score(its, vs)
            out[k][name] = {"n": s["n"], "gold_expr": s["gold_expr"], **{x: s["idiom_vs_literal"][x] for x in ("P", "R", "F1", "FPR")},
                            "wrong_sure": s["wrong_sure"], "undecided": s["undecided"]}
    return out


def span_level_streusle(recs, gold, outs):
    """STREUSLE MWE spans (strong + weak) vs the multiword units each system shows. Not an idiom measure."""
    res = {}
    for sysname, per in outs.items():
        tpe = npred = ngold = 0
        part = 0
        tok_tp = tok_p = tok_g = 0
        lex_hit = lex_n = 0
        for sid, rec in recs.items():
            st = gold[sid]
            mp = streusle_map(rec, st)
            gm = [frozenset(m["toks"]) for m in st["mwes"]]
            ngold += len(gm)
            if sysname == "amalgram_native":
                pu = per.get(sid)
                if pu is None:
                    continue
                units = set()
                for g in pu:
                    units.add(frozenset(k for k, t in enumerate(st["tokens"]) if any(overlaps((t["start"], t["end"]), c) for c in g)))
            else:
                o = per.get(sid)
                if o is None:
                    continue
                dec, win = o
                units = set()
                for k, m in enumerate(rec["matches"]):
                    if len(m["tokens"]) >= 2 and dec[k][0] in ("EXPR", "UNDECIDED") and any(w == k for w in win):
                        units.add(frozenset(x for i in m["tokens"] for x in mp[i]))
            units = {u for u in units if len(u) >= 2}
            npred += len(units)
            tpe += sum(1 for u in units if u in gm)
            part += sum(1 for u in units if any(u & g for g in gm))
            pt = set().union(*units) if units else set()
            gt = set().union(*gm) if gm else set()
            tok_tp += len(pt & gt)
            tok_p += len(pt)
            tok_g += len(gt)
            lexset = getattr(span_level_streusle, "lexicon", set())
            for m, g in zip(st["mwes"], gm):
                if (m.get("lexlemma") or "").lower() in lexset:
                    lex_n += 1
                    lex_hit += 1 if g in units else 0
        res[sysname] = {"exact": prf(tpe, npred - tpe, ngold - tpe), "partial_precision": round(part / npred, 3) if npred else None,
                        "token_level": prf(tok_tp, tok_p - tok_tp, tok_g - tok_tp), "pred_units": npred, "gold_units": ngold,
                        "in_lexicon_gold": lex_n, "in_lexicon_exact_recall": round(lex_hit / lex_n, 3) if lex_n else None}
    return res


def main():
    setname, outdir = sys.argv[1], sys.argv[2]
    systems = SYSTEMS
    if "--systems" in sys.argv:
        systems = sys.argv[sys.argv.index("--systems") + 1].split(",")
    recs, parses, am = load(setname, outdir)
    if setname == "mini":
        items, gold = items_mini(recs), None
    elif setname == "final5k":
        items, gold = items_magpie(recs), None
    else:
        items, gold = items_streusle(recs, setname.split("_")[1])
    outs = {}
    for s in systems:
        per = {}
        for sid, rec in recs.items():
            o = run_system(s, rec, parses, am)
            if o is not None:
                per[sid] = o
        if per:
            outs[s] = per
    views = {s: [item_view(it, recs[it["sid"]], outs[s][it["sid"]]) if it["sid"] in outs[s] else None for it in items] for s in outs}
    metrics = {"set": setname, "rules_version": rules.FREEZE, "systems": {}}
    bv = views["baseline"]
    for s, vs in views.items():
        ok_items = [(it, v, b) for it, v, b in zip(items, vs, bv) if v is not None]
        its, v2, b2 = [x[0] for x in ok_items], [x[1] for x in ok_items], [x[2] for x in ok_items]
        metrics["systems"][s] = {"score": score(its, v2), "paired_vs_baseline": paired(its, b2, v2), "slices": slices(its, v2),
                                 "items_covered": len(its)}
    if gold is not None:
        import sqlite3
        db = sqlite3.connect(f"file:{os.path.join(HERE, '..', '..', 'assets', 'dict.db')}?mode=ro", uri=True)
        span_level_streusle.lexicon = {p.lower() for (p,) in db.execute("SELECT phrase FROM expr")}
        so = dict(outs)
        if am is not None:
            so["amalgram_native"] = am
        metrics["streusle_span_level"] = span_level_streusle(recs, gold, so)
    with open(os.path.join(outdir, setname + ".decisions.jsonl"), "w", encoding="utf-8") as f:
        for k, it in enumerate(items):
            row = {"item": it["item"], "set": setname, "sentence_id": it["sid"], "gold": it["gold"], "phrase": it["phrase"]}
            for s in views:
                v = views[s][k]
                if v is not None:
                    row[s] = {x: v[x] for x in ("dec", "rule", "shown", "conf", "card", "exact", "tr")}
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    json.dump(metrics, open(os.path.join(outdir, setname + ".metrics.json"), "w"), indent=1, ensure_ascii=False)
    for s, m in metrics["systems"].items():
        sc = m["score"]
        il = sc["idiom_vs_literal"]
        pv = m["paired_vs_baseline"]
        print(f"{s:34} n={sc['n']:5} P={il['P']} R={il['R']} F1={il['F1']} FPR={il['FPR']} undec={sc['undecided']} "
              f"wrongSure={sc['wrong_sure']} wrongCard={sc['wrong_card_approval']} | +{pv['old_wrong_new_ok']} -{pv['old_ok_new_wrong']} "
              f"p={pv['mcnemar_exact_p']} blocked={pv['correct_cards_blocked']}")
    if "streusle_span_level" in metrics:
        for s, m in metrics["streusle_span_level"].items():
            print(f"  span {s:32} exact={m['exact']} partialP={m['partial_precision']} tok={m['token_level']} inLexR={m['in_lexicon_exact_recall']}")


if __name__ == "__main__":
    main()

"""Task 5L: metrics of the trace (trace_5l_test.dart) against a gold set (build_sets_5l.py). Local data only.

  python3 -I metrics_5l.py TRACE.jsonl GOLD.jsonl KIND [--show SYSTEM N]
KIND: streusle | dimsum | parseme (PARSEME: phrasal_verbs candidates only, it labels verbal MWEs only)

Gold EXPR = every token of the candidate lies inside one gold MWE. Decision: LIT = hidden as literal or wins no token
of the reader; UND = shown with no meaning ("cannot tell"); EXPR = shown with a meaning (sure / likely).
--show prints changed candidates WITH sentence text: for local inspection only, never commit the output.
"""
import json
import math
import sys
from collections import Counter, defaultdict


def mcnemar(b, c):
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    p = sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n
    return min(1.0, 2 * p)


def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - h) / d, (c + h) / d)


def to_gold_tokens(chars, gtoks):
    out = []
    for s, e in chars:
        hit = [i for i, (gs, ge) in enumerate(gtoks) if gs < e and s < ge]
        if not hit:
            return None
        out.extend(hit)
    return sorted(set(out))


def dec(x):
    if x["hidden"] or x["win"] == 0:
        return "LIT"
    if x["conf"] == "none":
        return "UND"
    return "EXPR"


def klass(c):
    ph = c["phrase"].split()
    if c["cat"] == "phrasal_verbs" and len(ph) == 2 and ph[0] == "be":
        return "be+particle"
    if c["cat"] == "phrasal_verbs":
        return "phrasal_verb"
    return c["cat"]


def main():
    trace, gold_path, kind = sys.argv[1:4]
    show = None
    if "--show" in sys.argv:
        k = sys.argv.index("--show")
        show = (sys.argv[k + 1], int(sys.argv[k + 2]))
    gold = {json.loads(l)["id"]: json.loads(l) for l in open(gold_path, encoding="utf-8")}
    rows = []
    span = defaultdict(lambda: {"shown": 0, "exact": 0})
    gold_mwes = 0
    systems = None
    for line in open(trace, encoding="utf-8"):
        t = json.loads(line)
        g = gold.get(t["id"])
        if g is None:
            continue
        gsets = [tuple(sorted(m["toks"])) for m in g["mwes"]]
        if kind == "parseme":
            gold_mwes += 0
        else:
            gold_mwes += len(gsets)
        overlaps = Counter()
        for c in t["cands"]:
            for i in c["tokens"]:
                overlaps[i] += 1
        for c in t["cands"]:
            systems = systems or list(c["sys"])
            gt = to_gold_tokens(c["chars"], g["tokens"])
            unit = gt is not None and any(set(gt) <= set(s) for s in gsets)
            exact = gt is not None and tuple(gt) in gsets
            shared = any(overlaps[i] > 1 for i in c["tokens"])
            for n, x in c["sys"].items():
                if kind != "parseme" and not x["hidden"] and x["win"] > 0:
                    span[n]["shown"] += 1
                    span[n]["exact"] += exact
            if kind == "parseme" and c["cat"] != "phrasal_verbs":
                continue
            rows.append({"id": t["id"], "c": c, "gold": "EXPR" if unit else "LIT", "class": klass(c), "shared": shared,
                         "text": g["text"]})
    if not rows:
        print("no candidates")
        return
    base = systems[0]
    print(f"{kind}: {len(rows)} candidates, gold EXPR {sum(r['gold'] == 'EXPR' for r in rows)}, "
          f"sentences {len(gold)}; base = {base}")
    hdr = "system P R F1 FPR[95%] und% wrong_sure right_sure card_ok wrong_card right_card_blocked fixed broken p span_P span_R span_F1"
    print(hdr)
    out = {}
    for n in systems:
        tp = fp = fn = tn = und = ws = rs = cok = wc = rcb = fixed = broken = 0
        for r in rows:
            x, b = r["c"]["sys"][n], r["c"]["sys"][base]
            d, db = dec(x), dec(b)
            e = r["gold"] == "EXPR"
            if d == "UND":
                und += 1
            pos = d == "EXPR"
            if pos and e:
                tp += 1
            elif pos:
                fp += 1
            elif e:
                fn += 1
            else:
                tn += 1
            if pos and x["conf"] == "sure":
                if e:
                    rs += 1
                else:
                    ws += 1
            if x.get("card"):
                cok += 1
                if not e:
                    wc += 1
            if e and b.get("card") and not x.get("card"):
                rcb += 1
            ok, okb = pos == e, (db == "EXPR") == e
            if ok and not okb:
                fixed += 1
            if okb and not ok:
                broken += 1
        P = tp / (tp + fp) if tp + fp else 0
        R = tp / (tp + fn) if tp + fn else 0
        F = 2 * P * R / (P + R) if P + R else 0
        fpr = fp / (fp + tn) if fp + tn else 0
        lo, hi = wilson(fp, fp + tn)
        sp = span[n]
        sP = sp["exact"] / sp["shown"] if sp["shown"] else 0
        sR = sp["exact"] / gold_mwes if gold_mwes else 0
        sF = 2 * sP * sR / (sP + sR) if sP + sR else 0
        out[n] = dict(P=P, R=R, F1=F, FPR=fpr, und=und, wrong_sure=ws, right_sure=rs, card=cok, wrong_card=wc,
                      right_card_blocked=rcb, fixed=fixed, broken=broken, p=mcnemar(fixed, broken), spanP=sP, spanR=sR, spanF1=sF)
        print(f"{n} {P:.3f} {R:.3f} {F:.3f} {fpr:.3f}[{lo:.2f}-{hi:.2f}] {100 * und / len(rows):.1f} {ws} {rs} {cok} {wc} {rcb} "
              f"{fixed} {broken} {mcnemar(fixed, broken):.3g} " + (f"{sP:.3f} {sR:.3f} {sF:.3f}" if kind != "parseme" else "- - -"))
    # slices: class x system, changed decisions
    print("slices (class: n, goldEXPR | per system fixed/broken, wrong_sure)")
    by = defaultdict(list)
    for r in rows:
        by[r["class"]].append(r)
        by["shares-a-token" if r["shared"] else "alone"].append(r)
    for k, rs_ in sorted(by.items(), key=lambda kv: -len(kv[1])):
        parts = []
        for n in systems[1:]:
            f = b = w = 0
            for r in rs_:
                x, bb = r["c"]["sys"][n], r["c"]["sys"][base]
                e = r["gold"] == "EXPR"
                ok, okb = (dec(x) == "EXPR") == e, (dec(bb) == "EXPR") == e
                f += ok and not okb
                b += okb and not ok
                w += dec(x) == "EXPR" and x["conf"] == "sure" and not e
            parts.append(f"{n}:+{f}/-{b}/ws{w}")
        print(f"  {k}: {len(rs_)}, {sum(r['gold'] == 'EXPR' for r in rs_)} | " + " ".join(parts))
    print("JSON " + json.dumps(out))
    if show:
        n, lim = show
        k = 0
        for r in rows:
            x, b = r["c"]["sys"][n], r["c"]["sys"][base]
            if dec(x) != dec(b) or x["conf"] != b["conf"]:
                print(f"  [{r['gold']}] {r['c']['phrase']} ({r['c']['cat']}) {dec(b)}/{b['conf']} -> {dec(x)}/{x['conf']} :: {r['text'][:140]}")
                k += 1
                if k >= lim:
                    break


if __name__ == "__main__":
    main()

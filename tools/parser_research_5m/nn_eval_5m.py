"""Task 5M: score a neural MWE tagger's predictions (neural_tagger_5m.py) against a gold set, and add it as a filter
system to a 5M trace (a candidate shown by BASE stays shown only if the tagger groups all its tokens together).

  python nn_eval_5m.py span   PRED.jsonl GOLD.jsonl
  python nn_eval_5m.py filter PRED.jsonl GOLD.jsonl TRACE OUT_TRACE BASE NAME
"""
import json
import sys

sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "nlp_research_5l"))
from metrics_5l import dec, to_gold_tokens  # noqa: E402


def span(pred, gold):
    g = {json.loads(l)["id"]: json.loads(l) for l in open(gold, encoding="utf-8")}
    tp = npred = ngold = 0
    for l in open(pred, encoding="utf-8"):
        p = json.loads(l)
        gs = {tuple(sorted(m["toks"])) for m in g[p["id"]]["mwes"] if m.get("kind", "strong") == "strong"}
        ps = {tuple(sorted(x)) for x in p["groups"]}
        tp += len(gs & ps)
        npred += len(ps)
        ngold += len(gs)
    P = tp / npred if npred else 0
    R = tp / ngold if ngold else 0
    print(f"span exact P {P:.3f} R {R:.3f} F1 {2 * P * R / (P + R) if P + R else 0:.3f} (pred {npred}, gold {ngold})")


def filt(pred, gold, trace, out, base, name):
    g = {json.loads(l)["id"]: json.loads(l) for l in open(gold, encoding="utf-8")}
    pr = {json.loads(l)["id"]: json.loads(l)["groups"] for l in open(pred, encoding="utf-8")}
    with open(out, "w", encoding="utf-8") as fo:
        for l in open(trace, encoding="utf-8"):
            t = json.loads(l)
            groups = pr.get(t["id"], [])
            for c in t["cands"]:
                x = dict(c["sys"][base])
                gt = to_gold_tokens(c["chars"], g[t["id"]]["tokens"])
                ok = gt is not None and any(set(gt) <= set(gr) for gr in groups)
                if dec(x) == "EXPR" and not ok:
                    x["hidden"], x["win"] = True, 0
                c["sys"][name] = x
            fo.write(json.dumps(t) + "\n")


if __name__ == "__main__":
    if sys.argv[1] == "span":
        span(sys.argv[2], sys.argv[3])
    else:
        filt(*sys.argv[2:8])

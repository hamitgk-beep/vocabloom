"""Task 5M (research): add a neural tagger's opinion to each candidate's unit features (feat_tpl) of a 5M trace, so
train_unit_5m.py can learn "unit scorer + neural tagger". nn=in: the tagger groups all the candidate's tokens together;
nn=part: it puts some of them in a group; nn=out: none. For training sets, use cross-fitted predictions (the tagger
must not have seen the sentence).

  python stack_nn_5m.py PRED.jsonl GOLD.jsonl TRACE OUT_TRACE
"""
import json
import sys

sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "nlp_research_5l"))
from metrics_5l import to_gold_tokens  # noqa: E402

pred, gold, trace, out = sys.argv[1:5]
g = {json.loads(l)["id"]: json.loads(l) for l in open(gold, encoding="utf-8")}
pr = {json.loads(l)["id"]: json.loads(l)["groups"] for l in open(pred, encoding="utf-8")}
with open(out, "w", encoding="utf-8") as fo:
    for l in open(trace, encoding="utf-8"):
        t = json.loads(l)
        groups = pr.get(t["id"], [])
        flat = {i for gr in groups for i in gr}
        for c in t["cands"]:
            if "feat_tpl" not in c:
                continue
            gt = to_gold_tokens(c["chars"], g[t["id"]]["tokens"]) or []
            v = "in" if gt and any(set(gt) <= set(gr) for gr in groups) else ("part" if set(gt) & flat else "out")
            c["feat_tpl"]["nn=" + v] = 1.0
            c["feat_tpl"][f"cat={c['cat']}|nn={v}"] = 1.0
        fo.write(json.dumps(t) + "\n")

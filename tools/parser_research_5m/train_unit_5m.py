"""Task 5M: train the unit scorer (logistic regression over lib/nlp/construction.dart unitFeatures) and add it to a
5M trace as extra systems, so metrics_5l.py can score them. Local data only; writes no corpus text.

  python train_unit_5m.py fit   TRAIN_TRACE TRAIN_GOLD KIND MODEL.json [--no-lex] [--C 1.0]
  python train_unit_5m.py apply MODEL.json TRACE GOLD_UNUSED OUT_TRACE NAME:THRESHOLD [NAME:THRESHOLD ...]
  python train_unit_5m.py dart  MODEL.json THRESHOLD OUT.dart
A system NAME = the tpl decision, but a candidate shown with a meaning whose score is below THRESHOLD is hidden.
"""
import json
import sys

sys.path.insert(0, __import__("os").path.join(__import__("os").path.dirname(__import__("os").path.abspath(__file__)), "..", "nlp_research_5l"))
from metrics_5l import dec, to_gold_tokens  # noqa: E402


def load(trace, gold_path, kind):
    gold = {json.loads(l)["id"]: json.loads(l) for l in open(gold_path, encoding="utf-8")}
    X, y = [], []
    for line in open(trace, encoding="utf-8"):
        t = json.loads(line)
        g = gold.get(t["id"])
        if g is None:
            continue
        gs = [tuple(sorted(m["toks"])) for m in g["mwes"]]
        for c in t["cands"]:
            if "feat_tpl" not in c:
                continue
            if kind == "parseme" and c["cat"] != "phrasal_verbs":
                continue
            gt = to_gold_tokens(c["chars"], g["tokens"])
            X.append(c["feat_tpl"])
            y.append(int(gt is not None and any(set(gt) <= set(s) for s in gs)))
    return X, y


def fit(args):
    from sklearn.feature_extraction import DictVectorizer
    from sklearn.linear_model import LogisticRegression
    trace, gold, kind, out = args[:4]
    lex = "--no-lex" not in args
    C = float(args[args.index("--C") + 1]) if "--C" in args else 1.0
    X, y = load(trace, gold, kind)
    if not lex:
        X = [{k: v for k, v in x.items() if not k.startswith("w=")} for x in X]
    v = DictVectorizer()
    A = v.fit_transform(X)
    m = LogisticRegression(C=C, max_iter=2000, fit_intercept=False).fit(A, y)
    w = {f: round(float(c), 4) for f, c in zip(v.get_feature_names_out(), m.coef_[0]) if abs(c) >= 1e-3}
    json.dump({"weights": w, "lex": lex, "C": C, "n": len(y), "pos": sum(y)}, open(out, "w"), indent=0, sort_keys=True)
    print(f"trained on {len(y)} candidates ({sum(y)} units), {len(w)} weights, lex={lex}, C={C}")


def score(w, f):
    import math
    z = sum(w.get(k, 0.0) * x for k, x in f.items())
    return 1 / (1 + math.exp(-z))


def apply(args):
    model, trace, _gold, out = args[:4]
    sysdefs = [(s.split(":")[0], float(s.split(":")[1])) for s in args[4:]]
    w = json.load(open(model))["weights"]
    with open(out, "w", encoding="utf-8") as fo:
        for line in open(trace, encoding="utf-8"):
            t = json.loads(line)
            for c in t["cands"]:
                x = c["sys"]["tpl"]
                p = score(w, c["feat_tpl"]) if "feat_tpl" in c else 0.0
                for name, th in sysdefs:
                    y = dict(x)
                    if dec(x) == "EXPR" and p < th:
                        y["hidden"] = True
                        y["win"] = 0
                    c["sys"][name] = y
            fo.write(json.dumps(t) + "\n")


def dart(args):
    model, th, out = args[0], float(args[1]), args[2]
    m = json.load(open(model))
    lines = ["// Task 5M (research, OFF by default): weights of the unit scorer, made by",
             "// tools/parser_research_5m/train_unit_5m.py from STREUSLE 4.x train+dev candidates (CC BY-SA 4.0",
             f"// annotations; {m['n']} candidates, {m['pos']} units, C={m['C']}, lexical features: {m['lex']}).",
             "// Generated file: do not edit by hand.",
             "import 'construction.dart';", "",
             f"const unitScorer5m = UnitScorer(_w, {th});", "",
             "const _w = <String, double>{"]
    for k, v in sorted(m["weights"].items()):
        lines.append(f"  {json.dumps(k).replace('$', chr(92) + '$')}: {v},")
    lines.append("};")
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"wrote {len(m['weights'])} weights")


if __name__ == "__main__":
    {"fit": fit, "apply": apply, "dart": dart}[sys.argv[1]](sys.argv[2:])

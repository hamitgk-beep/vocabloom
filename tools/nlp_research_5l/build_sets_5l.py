"""Task 5L: build the evaluation sets LOCALLY and print their SHA-256 (the hashes are committed, the text never is).

Sets (all human-annotated; nothing here was labelled by Claude):
  dev_streusle  STREUSLE 4.x train+dev (seen in 5K for design: development only)
  hold_dimsum   DiMSUM 2016 TEST (TrustPilot reviews, Tweebank tweets, TED talks), strong MWEs  -> locked holdout
  hold_parseme  PARSEME 1.1 English (train+test), verbal MWEs (VID, LVC, VPC, IAV, MVC)     -> locked holdout
Sentences whose text also occurs in STREUSLE (any split) or in the 5K mini suite are dropped from both holdouts,
so no holdout sentence was seen by 5K. DiMSUM gives tokens only: the text is the tokens joined by one space.

  python3 -I build_sets_5l.py EXT_DIR OUT_DIR
EXT_DIR holds dimsum-data @3af1dd3, sharedtask-data (PARSEME) @012ee7d, streusle @8ba61fe; OUT_DIR is outside the repo.
Output per set: <set>.tsv ("id<TAB>text") and <set>.gold.jsonl ({id, text, tokens:[[start,end]], mwes:[{toks, cat}]}).
"""
import hashlib
import json
import os
import re
import sys


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def offsets(text, words):
    out, at = [], 0
    for w in words:
        i = text.find(w, at)
        if i < 0:
            return None
        out.append([i, i + len(w)])
        at = i + len(w)
    return out


def streusle(ext):
    rows = []
    for split, path in (("train", "train/streusle.ud_train.json"), ("dev", "dev/streusle.ud_dev.json"), ("test", "test/streusle.ud_test.json")):
        for s in json.load(open(os.path.join(ext, "streusle", path), encoding="utf-8")):
            words = [t["word"] for t in s["toks"]]
            offs = offsets(s["text"], words)
            if offs is None:
                continue
            mwes = [{"toks": [n - 1 for n in m["toknums"]], "cat": m.get("lexcat") or "", "kind": "strong"} for m in s["smwes"].values()]
            mwes += [{"toks": [n - 1 for n in m["toknums"]], "cat": "weak", "kind": "weak"} for m in s["wmwes"].values()]
            rows.append((split, {"id": s["sent_id"], "text": s["text"], "tokens": offs, "words": words, "mwes": mwes}))
    return rows


def dimsum(ext):
    sents, cur = [], []
    for line in open(os.path.join(ext, "dimsum-data", "dimsum16.test"), encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            if cur:
                sents.append(cur)
            cur = []
            continue
        cur.append(line.split("\t"))
    if cur:
        sents.append(cur)
    out = []
    for k, s in enumerate(sents):
        words = [c[1] for c in s]
        text = " ".join(words)
        offs = offsets(text, words)
        parent = {int(c[0]) - 1: int(c[5]) - 1 for c in s if c[5] not in ("", "0")}
        groups = {}
        for i in range(len(s)):
            r = i
            while r in parent:
                r = parent[r]
            if r != i or any(p == i for p in parent.values()) or i in parent:
                groups.setdefault(r, set()).add(i)
        mwes = [{"toks": sorted(g), "cat": s[r][3], "kind": "strong"} for r, g in groups.items() if len(g) > 1]
        out.append({"id": f"dimsum-{k:04d}", "text": text, "tokens": offs, "words": words, "mwes": mwes})
    return out


def parseme(ext):
    out = []
    for split in ("train", "test"):
        block = []
        for line in open(os.path.join(ext, "sharedtask-data", "1.1", "EN", f"{split}.cupt"), encoding="utf-8"):
            line = line.rstrip("\n")
            if line:
                block.append(line)
                continue
            if not block:
                continue
            text = next((l[len("# text = "):] for l in block if l.startswith("# text = ")), None)
            toks = [l.split("\t") for l in block if not l.startswith("#")]
            toks = [t for t in toks if re.fullmatch(r"\d+", t[0])]
            block = []
            if text is None:
                continue
            words = [t[1] for t in toks]
            offs = offsets(text, words)
            if offs is None:
                continue
            g = {}
            for i, t in enumerate(toks):
                if t[10] in ("*", "_"):
                    continue
                for part in t[10].split(";"):
                    num, _, cat = part.partition(":")
                    e = g.setdefault(num, {"toks": [], "cat": ""})
                    e["toks"].append(i)
                    if cat:
                        e["cat"] = cat
            out.append({"id": f"parseme-{split}-{len(out):04d}", "text": text, "tokens": offs, "words": words,
                        "mwes": [dict(v, kind="strong") for v in g.values()]})
    return out


def write(outdir, name, rows):
    tsv = os.path.join(outdir, f"{name}.tsv")
    gold = os.path.join(outdir, f"{name}.gold.jsonl")
    with open(tsv, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(f"{r['id']}\t{r['text']}\n")
    with open(gold, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return {p: hashlib.sha256(open(os.path.join(outdir, p), "rb").read()).hexdigest() for p in (f"{name}.tsv", f"{name}.gold.jsonl")}


def main():
    ext, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    st = streusle(ext)
    here = os.path.dirname(os.path.abspath(__file__))
    mini = os.path.join(here, "..", "nlp_lab_5k", "data", "mini_suite_5k.tsv")
    seen = {norm(r["text"]) for _, r in st} | {norm(l.split("\t", 1)[1]) for l in open(mini, encoding="utf-8") if "\t" in l}
    dev = [r for split, r in st if split in ("train", "dev")]
    dim = [r for r in dimsum(ext) if r["tokens"] is not None and norm(r["text"]) not in seen]
    par_all = parseme(ext)
    par, dup = [], set()
    for r in par_all:
        n = norm(r["text"])
        if n in seen or n in dup:
            continue
        dup.add(n)
        par.append(r)
    lock = {}
    lock.update(write(outdir, "dev_streusle", dev))
    lock.update(write(outdir, "hold_dimsum", dim))
    lock.update(write(outdir, "hold_parseme", par))
    print(json.dumps({"counts": {"dev_streusle": len(dev), "hold_dimsum": len(dim), "hold_parseme": len(par),
                                 "parseme_dropped_seen_or_dup": len(par_all) - len(par)},
                      "sha256": lock}, indent=1))


if __name__ == "__main__":
    main()

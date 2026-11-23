"""Task 5M: build the NEW locked final set LOCALLY and print its SHA-256 (hashes are committed, text never is).

final_tweets  DiMSUM 2016 TRAIN, only the tweet parts (Lowlands 200 + Ritter 787 sentences). Human-annotated strong
              MWEs (same format as hold_dimsum in 5L). Never used in 5F-5L: 5L used only dimsum16.test, the ewtb part
              of dimsum16.train is STREUSLE (seen in 5K/5L) and is dropped. Sentences whose text also occurs in STREUSLE,
              dimsum16.test, PARSEME 1.1 EN or the 5K mini suite are dropped.

  python3 -I build_final_5m.py EXT_DIR OUT_DIR
EXT_DIR holds dimsum-data @3af1dd3, streusle @8ba61fe, sharedtask-data @012ee7d. OUT_DIR is outside the repo.
"""
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "nlp_research_5l"))
import build_sets_5l as b5l  # noqa: E402


def dimsum_file(ext, name, keep):
    sents, cur = [], []
    for line in open(os.path.join(ext, "dimsum-data", name), encoding="utf-8"):
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
    for s in sents:
        sid = s[0][8]
        if not keep(sid):
            continue
        words = [c[1] for c in s]
        text = " ".join(words)
        offs = b5l.offsets(text, words)
        parent = {int(c[0]) - 1: int(c[5]) - 1 for c in s if c[5] not in ("", "0")}
        groups = {}
        for i in range(len(s)):
            r = i
            while r in parent:
                r = parent[r]
            if r != i or any(p == i for p in parent.values()) or i in parent:
                groups.setdefault(r, set()).add(i)
        mwes = [{"toks": sorted(g), "cat": s[r][3], "kind": "strong"} for r, g in groups.items() if len(g) > 1]
        out.append({"id": f"tw-{sid}", "text": text, "tokens": offs, "words": words, "mwes": mwes})
    return out


def main():
    ext, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    seen = {b5l.norm(r["text"]) for _, r in b5l.streusle(ext)}
    seen |= {b5l.norm(" ".join(r["words"])) for r in b5l.dimsum(ext)}
    seen |= {b5l.norm(r["text"]) for r in b5l.parseme(ext)}
    mini = os.path.join(HERE, "..", "nlp_lab_5k", "data", "mini_suite_5k.tsv")
    seen |= {b5l.norm(l.split("\t", 1)[1]) for l in open(mini, encoding="utf-8") if "\t" in l}
    rows = dimsum_file(ext, "dimsum16.train", lambda sid: not sid.startswith("ewtb"))
    out, dup = [], set()
    for r in rows:
        n = b5l.norm(r["text"])
        if r["tokens"] is None or n in seen or n in dup or not n:
            continue
        dup.add(n)
        out.append(r)
    lock = b5l.write(outdir, "final_tweets", out)
    print(json.dumps({"counts": {"final_tweets": len(out), "dropped": len(rows) - len(out)}, "sha256": lock}, indent=1))


if __name__ == "__main__":
    main()

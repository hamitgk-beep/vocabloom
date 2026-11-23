"""Read STREUSLE (github.com/nert-nlp/streusle, JSON per split) into a common form; parse it for real.

Each sentence: id, text, tokens [{i, start, end (0-based, exclusive), word, xpos, upos, lemma}],
gold MWEs [{kind: strong|weak, toks: [0-based], lexcat, lexlemma}]. STREUSLE text (EWT reviews, redistributed by
STREUSLE with LDC/Google permission) and its annotations (CC BY-SA 4.0) stay LOCAL; nothing from it is committed.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(HERE, "external", "streusle")
SPLITS = {"train": "train/streusle.ud_train.json", "dev": "dev/streusle.ud_dev.json", "test": "test/streusle.ud_test.json"}


def load(split):
    data = json.load(open(os.path.join(ROOT, SPLITS[split]), encoding="utf-8"))
    out = []
    for s in data:
        text = s["text"]
        toks, at = [], 0
        ok = True
        for k, t in enumerate(s["toks"]):
            w = t["word"]
            i = text.find(w, at)
            if i < 0:
                ok = False
                break
            toks.append({"i": k, "start": i, "end": i + len(w), "word": w, "xpos": t["xpos"], "upos": t["upos"], "lemma": t["lemma"]})
            at = i + len(w)
        if not ok:
            continue
        mwes = []
        for kind, key in (("strong", "smwes"), ("weak", "wmwes")):
            for m in s[key].values():
                mwes.append({"kind": kind, "toks": [n - 1 for n in m["toknums"]], "lexcat": m.get("lexcat"), "lexlemma": m.get("lexlemma")})
        out.append({"id": s["sent_id"], "text": text, "tokens": toks, "mwes": mwes})
    return out


def write_tsv(split, path):
    rows = load(split)
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(f"{r['id']}\t{r['text']}\n")
    return len(rows)


def write_amalgram_mwe(split, path):
    """AMALGrAM's .mwe training format (sentId, readable, JSON with words/_/~, 1-based offsets), gold PTB POS."""
    with open(path, "w", encoding="utf-8") as f:
        for r in load(split):
            words = [[t["word"], t["xpos"]] for t in r["tokens"]]
            strong = [[k + 1 for k in m["toks"]] for m in r["mwes"] if m["kind"] == "strong"]
            weak = [[k + 1 for k in m["toks"]] for m in r["mwes"] if m["kind"] == "weak"]
            f.write(f"{r['id']}\t{' '.join(w for w, _ in words)}\t{json.dumps({'words': words, '_': strong, '~': weak})}\n")


if __name__ == "__main__":
    cmd, split, path = sys.argv[1:4]
    if cmd == "tsv":
        print(write_tsv(split, path))
    elif cmd == "amalgram":
        write_amalgram_mwe(split, path)

"""Task 5M (research only, never shipped): LSR / BeeParser-style MWE tagger, re-trained here.

Neither original model is usable: the LSR Tagger (Liu et al. 2021, BERT-large + constraints, MIT code) keeps its
models on Google Drive (blocked from this container), BeeParser (Erdem & Karaarslan, MWE-2026, XLM-R-base BIO tagger,
MIT code) released no model and has no English. Both are "encoder + per-token BIO head"; this script trains exactly
that on STREUSLE train+dev (strong MWEs) and writes predicted MWE groups per sentence.

  python train   OUT_DIR MODEL_NAME TRAIN.gold.jsonl [epochs]
  python predict OUT_DIR SET.gold.jsonl PRED.jsonl
Prediction groups: B starts a group, I joins the open group (gaps of O allowed, up to 3 tokens).
"""
import json
import os
import sys
import time

import torch
from transformers import AutoModelForTokenClassification, AutoTokenizer

LABELS = ["O", "B", "I"]
torch.set_num_threads(4)


def rows(path):
    return [json.loads(l) for l in open(path, encoding="utf-8")]


def bio(r):
    lab = ["O"] * len(r["words"])
    for m in r["mwes"]:
        if m.get("kind", "strong") != "strong" or len(m["toks"]) < 2:
            continue
        t = sorted(m["toks"])
        lab[t[0]] = "B"
        for i in t[1:]:
            lab[i] = "I"
    return lab


def encode(tok, words, labels=None, maxlen=160):
    enc = tok(words, is_split_into_words=True, truncation=True, max_length=maxlen, return_tensors="pt")
    wid = enc.word_ids(0)
    if labels is None:
        return enc, wid
    y, prev = [], None
    for w in wid:
        y.append(-100 if w is None or w == prev else LABELS.index(labels[w]))
        prev = w
    return enc, wid, torch.tensor([y])


def train(out, name, path, epochs=3):
    tok = AutoTokenizer.from_pretrained(name, add_prefix_space=True) if "roberta" in name else AutoTokenizer.from_pretrained(name)
    model = AutoModelForTokenClassification.from_pretrained(name, num_labels=3)
    data = [r for r in rows(path) if r["words"]]
    opt = torch.optim.AdamW(model.parameters(), lr=5e-5 if "L-4" in name or "MiniLM" in name else 3e-5)
    g = torch.Generator().manual_seed(5)
    t0 = time.time()
    model.train()
    for ep in range(epochs):
        order = torch.randperm(len(data), generator=g).tolist()
        tot = 0.0
        for k, i in enumerate(order):
            enc, _, y = encode(tok, data[i]["words"], bio(data[i]))
            loss = model(**enc, labels=y).loss
            loss.backward()
            if k % 8 == 7:
                opt.step()
                opt.zero_grad()
            tot += loss.item()
        print(f"epoch {ep} loss {tot / len(data):.4f} t={time.time() - t0:.0f}s", flush=True)
    os.makedirs(out, exist_ok=True)
    model.save_pretrained(out)
    tok.save_pretrained(out)
    n = sum(p.numel() for p in model.parameters())
    json.dump({"base": name, "params": n, "train_s": round(time.time() - t0), "epochs": epochs}, open(os.path.join(out, "info_5m.json"), "w"))


def groups(labs):
    out, cur, gap = [], None, 0
    for i, l in enumerate(labs):
        if l == "B":
            if cur and len(cur) > 1:
                out.append(cur)
            cur, gap = [i], 0
        elif l == "I" and cur is not None:
            cur.append(i)
            gap = 0
        else:
            gap += 1
            if cur is not None and gap > 3:
                if len(cur) > 1:
                    out.append(cur)
                cur = None
    if cur and len(cur) > 1:
        out.append(cur)
    return out


def predict(out, path, pred):
    tok = AutoTokenizer.from_pretrained(out)
    model = AutoModelForTokenClassification.from_pretrained(out).eval()
    t0, n = time.time(), 0
    with open(pred, "w", encoding="utf-8") as f, torch.no_grad():
        for r in rows(path):
            if not r["words"]:
                continue
            enc, wid = encode(tok, r["words"])
            p = model(**enc).logits[0].argmax(-1).tolist()
            labs, prev = ["O"] * len(r["words"]), None
            for k, w in enumerate(wid):
                if w is not None and w != prev:
                    labs[w] = LABELS[p[k]]
                prev = w
            f.write(json.dumps({"id": r["id"], "groups": groups(labs)}) + "\n")
            n += 1
    print(f"predicted {n} sentences, {1000 * (time.time() - t0) / max(n, 1):.1f} ms/sentence (CPU, 4 threads)")


if __name__ == "__main__":
    if sys.argv[1] == "train":
        train(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 3)
    else:
        predict(sys.argv[2], sys.argv[3], sys.argv[4])

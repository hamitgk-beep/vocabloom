#!/usr/bin/env python3
"""Paragraphs with human sentence boundaries, word positions, base forms and
parts of speech, for test/text_eval_test.dart.

Source: the GUM treebank in Universal Dependencies form (Georgetown
University Multilayer corpus, https://github.com/UniversalDependencies/UD_English-GUM),
written genres only. Its fiction and wikiHow texts are CC BY-NC-SA, so the
output is NOT added to the repository: it is written where you say and the
test reads it from $TEXT_EVAL_DIR.

  python3 tools/eval/build_text_eval.py <dir with en_gum-ud-{train,dev,test}.conllu> <out dir>

Writes text_eval_dev.jsonl (GUM train + dev: for development) and
text_eval_test.jsonl (GUM test: measured, never tuned on). One paragraph a
line: {"doc", "genre", "text", "sents": [[start, end]], "toks": [[start, end,
form, lemma, upos]]}.
"""
import json
import os
import sys


def paragraphs(path):
    doc = genre = None
    written = True
    para = None  # {"text", "sents", "toks"}

    def flush():
        nonlocal para
        if para and para["sents"] and written:
            yield_list.append({"doc": doc, "genre": genre, **para})
        para = None

    yield_list = []
    sent = []  # (form, lemma, upos, space_after)
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    lines.append("")
    mwt_end = 0
    mwt_first = True
    for line in lines:
        if line.startswith("# newdoc"):
            flush()
            doc = line.split("=", 1)[1].strip()
            written = True
        elif line.startswith("# meta::genre"):
            genre = line.split("=", 1)[1].strip()
        elif line.startswith("# meta::modality"):
            written = line.split("=", 1)[1].strip() == "written"
        elif line.startswith("# newpar") and not line.startswith("# newpar_block"):
            flush()
        elif line.startswith("#"):
            continue
        elif not line.strip():
            if sent:
                if para is None:
                    para = {"text": "", "sents": [], "toks": []}
                if para["text"] and not para["text"].endswith(" "):
                    para["text"] += " " if para.get("_space", True) else ""
                start = len(para["text"])
                for form, lemma, upos, space in sent:
                    s = len(para["text"])
                    if form is not None:
                        para["text"] += form
                        e = len(para["text"])
                        if not space:
                            pass
                        else:
                            para["text"] += " "
                        last = (s, e)
                    else:
                        s, e = last
                    if upos is not None:
                        para["toks"].append([s if form is not None else last[0], e, None, lemma, upos])
                # trailing space of the last token decides the join
                para["_space"] = para["text"].endswith(" ")
                para["text"] = para["text"].rstrip(" ")
                para["sents"].append([start, len(para["text"])])
                sent = []
            mwt_end = 0
        else:
            c = line.split("\t")
            if "." in c[0]:
                continue
            space = "SpaceAfter=No" not in c[9]
            if "-" in c[0]:
                a, b = c[0].split("-")
                mwt_end = int(b)
                mwt_first = True
                sent.append((c[1], None, None, space))  # surface only
                continue
            i = int(c[0])
            if i <= mwt_end:
                # Inside a multi-word token ("don't" = do + n't): the first
                # part stands for the written word.
                if mwt_first:
                    sent.append((None, c[2], c[3], True))
                    mwt_first = False
                continue
            sent.append((c[1], c[2], c[3], space))
    flush()
    for p in yield_list:
        p.pop("_space", None)
        for t in p["toks"]:
            t[2] = p["text"][t[0]:t[1]]
    return yield_list


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    sets = {"dev": ["train", "dev"], "test": ["test"]}
    for name, parts in sets.items():
        rows = []
        for part in parts:
            rows += paragraphs(os.path.join(src, f"en_gum-ud-{part}.conllu"))
        with open(os.path.join(out, f"text_eval_{name}.jsonl"), "w", encoding="utf-8") as f:
            for r in rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(name, "paragraphs", len(rows), "sentences", sum(len(r["sents"]) for r in rows),
              "words", sum(len(r["toks"]) for r in rows), "docs", len({r["doc"] for r in rows}))


if __name__ == "__main__":
    main()

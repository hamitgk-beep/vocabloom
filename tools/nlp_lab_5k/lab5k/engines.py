"""Run one real parser on sentences and write a common JSONL schema.

Common token schema (all engines): {"i", "start", "end" (0-based, exclusive, Python str offsets),
"text", "lemma", "upos", "xpos", "head" (0-based token index or -1 for root), "deprel"}.
Each output line: {"id", "engine", "tokens": [...]}. Runs offline: models must already be on disk
(see setup.sh); no download happens here.
"""
import json
import os
import resource
import sys
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(HERE, "models")

ENGINES = ["spacy_sm", "spacy_md", "stanza", "udpipe_ewt25", "udpipe_bnosac21"]


def _spacy(name):
    import spacy
    nlp = spacy.load(name)

    def run(text):
        doc = nlp(text)
        out = []
        for t in doc:
            if t.is_space:
                continue
            out.append({"start": t.idx, "end": t.idx + len(t.text), "text": t.text, "lemma": t.lemma_,
                        "upos": t.pos_, "xpos": t.tag_, "head_abs": t.head.i, "self_abs": t.i,
                        "deprel": "root" if t.dep_ == "ROOT" else t.dep_})
        idx = {o["self_abs"]: k for k, o in enumerate(out)}
        for o in out:
            o["head"] = -1 if o["head_abs"] == o["self_abs"] else idx.get(o["head_abs"], -1)
            del o["head_abs"], o["self_abs"]
        return out

    import spacy as _s
    meta = nlp.meta
    return run, {"library": "spacy " + _s.__version__, "model": f"{meta['name']} {meta['version']}",
                 "model_license": meta.get("license"), "sources": [s.get("name") for s in meta.get("sources", [])]}


def _stanza():
    import stanza
    import logging
    logging.getLogger("stanza").setLevel(logging.ERROR)
    nlp = stanza.Pipeline("en", dir=os.path.join(MODELS, "stanza"), processors="tokenize,mwt,pos,lemma,depparse",
                          download_method=None, use_gpu=False, verbose=False)

    def run(text):
        doc = nlp(text)
        out = []
        for sent in doc.sentences:
            base = len(out)
            words = sent.words
            for w in words:
                tok = w.parent
                out.append({"start": tok.start_char, "end": tok.end_char, "text": w.text, "lemma": w.lemma or w.text,
                            "upos": w.upos, "xpos": w.xpos, "head": (base + w.head - 1) if w.head > 0 else -1,
                            "deprel": w.deprel})
        return out

    import json as _j
    res = _j.load(open(os.path.join(MODELS, "stanza", "resources.json")))
    pk = res["en"]["default_processors"]
    return run, {"library": "stanza " + stanza.__version__, "model": f"en default {pk}",
                 "resources_version": res.get("version") or res["en"].get("lang_name")}


def _udpipe(fname):
    from ufal.udpipe import Model, Pipeline, ProcessingError
    path = os.path.join(MODELS, fname)
    model = Model.load(path)
    if model is None:
        raise RuntimeError("cannot load " + path)
    pipe = Pipeline(model, "tokenizer=ranges", Pipeline.DEFAULT, Pipeline.DEFAULT, "conllu")

    keep = (model, pipe)  # SWIG does not keep the model alive for the pipeline: hold both (segfault otherwise)

    def run(text, _keep=keep):
        err = ProcessingError()
        conllu = _keep[1].process(text, err)
        if err.occurred():
            raise RuntimeError(err.message)
        out = []
        base = 0
        sent = []
        for line in conllu.split("\n") + [""]:
            if not line:
                if sent:
                    for c in sent:
                        h = int(c[6])
                        misc = dict(x.split("=", 1) for x in c[9].split("|") if "=" in x)
                        a, b = misc["TokenRange"].split(":")
                        out.append({"start": int(a), "end": int(b), "text": c[1], "lemma": c[2], "upos": c[3],
                                    "xpos": c[4], "head": base + h - 1 if h > 0 else -1, "deprel": c[7]})
                    base = len(out)
                    sent = []
                continue
            if line.startswith("#"):
                continue
            c = line.split("\t")
            if "-" in c[0] or "." in c[0]:
                continue  # multiword token lines / empty nodes
            sent.append(c)
        return out

    import ufal.udpipe as u
    return run, {"library": "ufal.udpipe (UDPipe 1 binding)", "model": fname}


def load(engine):
    if engine == "spacy_sm":
        return _spacy("en_core_web_sm")
    if engine == "spacy_md":
        return _spacy("en_core_web_md")
    if engine == "stanza":
        return _stanza()
    if engine == "udpipe_ewt25":
        return _udpipe("english-ewt-ud-2.5-191206.udpipe")
    if engine == "udpipe_bnosac21":
        return _udpipe("english-ud-2.1-20180111.udpipe")
    raise SystemExit("unknown engine " + engine)


def parse_file(engine, in_path, out_path, perf_path=None):
    t0 = time.perf_counter()
    run, info = load(engine)
    t_load = time.perf_counter() - t0
    n = ntok = 0
    t1 = time.perf_counter()
    with open(in_path, encoding="utf-8") as f, open(out_path, "w", encoding="utf-8") as o:
        for line in f:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            sid, text = line.split("\t", 1)
            toks = run(text)
            for k, t in enumerate(toks):
                t["i"] = k
            o.write(json.dumps({"id": sid, "engine": engine, "tokens": toks}, ensure_ascii=False) + "\n")
            n += 1
            ntok += len(toks)
    t_run = time.perf_counter() - t1
    perf = {"engine": engine, **info, "sentences": n, "tokens": ntok, "load_s": round(t_load, 3),
            "run_s": round(t_run, 3), "ms_per_sentence": round(1000 * t_run / max(n, 1), 2),
            "peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1)}
    if perf_path:
        with open(perf_path, "a") as p:
            p.write(json.dumps(perf) + "\n")
    return perf


if __name__ == "__main__":
    eng, i, o = sys.argv[1:4]
    print(json.dumps(parse_file(eng, i, o, sys.argv[4] if len(sys.argv) > 4 else None)))

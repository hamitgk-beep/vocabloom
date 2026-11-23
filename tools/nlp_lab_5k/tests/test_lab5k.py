"""Offline tests of the 5K lab. Model-backed tests skip when the models of setup.sh are absent (CI default)."""
import hashlib
import json
import os
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)
from lab5k import bench, rules  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
TEXT = "Blacky the Crow was on hand promptly that afternoon."


def tok(spans):
    return [{"i": i, "start": a, "end": b, "text": TEXT[a:b]} for i, (a, b) in enumerate(spans)]


STOKS = tok([(0, 6), (7, 10), (11, 15), (16, 19), (20, 22), (23, 27), (28, 36), (37, 41), (42, 51)])


def match(phrase, cat, idx, conf="sure"):
    return {"phrase": phrase, "cat": cat, "tokens": idx, "literal_hidden": False, "conf": conf,
            "tr_shown": "x", "draft": False, "dict_tr": "x", "dict_tr_draft": None}


def ptoks(rows):
    out = []
    for i, (t, upos, head, rel) in enumerate(rows):
        s = STOKS[i]
        out.append({"i": i, "start": s["start"], "end": s["end"], "text": t, "lemma": t.lower(), "upos": upos, "xpos": "",
                    "head": head, "deprel": rel})
    return out


# UD analysis (as Stanza / UDPipe give it): 'on' is the case marker of 'hand'
UD = ptoks([("Blacky", "PROPN", 5, "nsubj"), ("the", "DET", 2, "det"), ("Crow", "PROPN", 0, "flat"), ("was", "AUX", 5, "cop"),
            ("on", "ADP", 5, "case"), ("hand", "NOUN", -1, "root"), ("promptly", "ADV", 5, "advmod"),
            ("that", "DET", 8, "det"), ("afternoon", "NOUN", 5, "obl")])
# ClearNLP analysis (as spaCy gives it): 'on' is a 'prep' of 'was' with 'hand' as its pobj
CLEAR = ptoks([("Blacky", "PROPN", 3, "nsubj"), ("the", "DET", 2, "det"), ("Crow", "PROPN", 0, "appos"), ("was", "AUX", -1, "ROOT"),
               ("on", "ADP", 3, "prep"), ("hand", "NOUN", 4, "pobj"), ("promptly", "ADV", 3, "advmod"),
               ("that", "DET", 8, "det"), ("afternoon", "NOUN", 3, "npadvmod")])


@pytest.mark.parametrize("tree", [UD, CLEAR], ids=["ud", "clearnlp"])
def test_was_on_hand_same_rule_both_label_schemes(tree):
    rec = {"text": TEXT, "tokens": STOKS}
    ms = [match("be on", "phrasal_verbs", [3, 4]), match("on hand", "prepositional_phrases", [4, 5], "likely")]
    p = rules.Parse(tree, STOKS)
    dec = [rules.decide(rec, m, p) for m in ms]
    dec = rules.resolve_overlaps(rec, ms, dec, p)
    assert dec[0][0] == "LIT" and dec[1][0] == "EXPR"
    assert rules.winners(rec, ms, dec, bench.CAT_ORDER)[4] == 1  # 'on' opens 'on hand', not 'be on'


def test_parser_free_rules_never_sure_for_be_particle():
    rec = {"text": TEXT, "tokens": STOKS}
    assert rules.decide(rec, match("be on", "phrasal_verbs", [3, 4]), None, use_parser=False)[0] == "UNDECIDED"


def test_quoted_mention():
    t = "She said the words 'on the run' aloud."
    toks = [{"i": i, "start": a, "end": b, "text": t[a:b]} for i, (a, b) in enumerate([(0, 3), (4, 8), (9, 12), (13, 18), (20, 22), (23, 26), (27, 30), (32, 37)])]
    rec = {"text": t, "tokens": toks}
    assert rules.decide(rec, match("on the run", "prepositional_phrases", [4, 5, 6]), None, use_parser=False)[0] == "MENTION"


def test_rules_never_raise_certainty():
    rec = {"text": TEXT, "tokens": STOKS}
    m = match("on hand", "prepositional_phrases", [4, 5], "likely")
    d = rules.decide(rec, m, rules.Parse(UD, STOKS))
    v = bench.item_view({"cand": 0, "gold_spans": None}, {"tokens": STOKS, "matches": [m]}, ([d], [None, None, None, None, 0, 0, None, None, None]))
    assert v["conf"] == "likely" and not v["card"]


def test_mcnemar_and_ci():
    assert bench.mcnemar_exact(9, 0) == pytest.approx(0.0039, abs=1e-4)
    lo, hi = bench.wilson(0, 10)
    assert lo == 0 and 0.27 < hi < 0.29


def test_audit_is_read_only(tmp_path):
    db = os.path.join(REPO, "assets", "dict.db")
    if not os.path.exists(db):
        pytest.skip("no dict.db")
    before = hashlib.sha256(open(db, "rb").read()).hexdigest()
    out = tmp_path / "audit.tsv"
    subprocess.run([sys.executable, "-m", "lab5k.audit", db, str(out)], cwd=HERE, check=True, capture_output=True)
    assert hashlib.sha256(open(db, "rb").read()).hexdigest() == before
    rows = [l.split("\t") for l in open(out, encoding="utf-8")][1:]
    be_on = [r for r in rows if r[1] == "be on"]
    assert be_on and "BE_PLUS_PARTICLE" in be_on[0][4]


def _have(mod):
    try:
        __import__(mod)
        return True
    except Exception:
        return False


@pytest.mark.skipif(not _have("en_core_web_sm"), reason="spaCy model not installed (setup.sh)")
def test_real_spacy_parse_of_screenshot_sentence():
    from lab5k import engines
    run, info = engines.load("spacy_sm")
    toks = run(TEXT)
    on = [t for t in toks if t["text"] == "on"][0]
    hand = [t for t in toks if t["text"] == "hand"][0]
    assert hand["deprel"] == "pobj" and toks[hand["head"]] is on


@pytest.mark.skipif(not _have("ufal.udpipe") or not os.path.exists(os.path.join(HERE, "models", "english-ud-2.1-20180111.udpipe")),
                    reason="UDPipe or its model absent (setup.sh)")
def test_real_udpipe_parse_of_bridge_sentence():
    from lab5k import engines
    run, _ = engines.load("udpipe_bnosac21")
    toks = run("He was on the bridge.")
    on = [t for t in toks if t["text"] == "on"][0]
    assert on["deprel"] == "case" and toks[on["head"]]["text"] == "bridge"

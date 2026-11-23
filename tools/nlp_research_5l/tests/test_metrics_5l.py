"""Offline tests of the 5L metric helpers (no corpus data needed)."""
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("metrics_5l", os.path.join(HERE, "metrics_5l.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def test_mcnemar_exact():
    assert m.mcnemar(0, 0) == 1.0
    assert abs(m.mcnemar(13, 0) - 2 / 2 ** 13) < 1e-12
    assert m.mcnemar(5, 5) == 1.0


def test_gold_token_mapping_by_characters():
    gold = [[0, 2], [3, 6], [7, 9], [10, 14]]  # "He was on hand"
    assert m.to_gold_tokens([[7, 9], [10, 14]], gold) == [2, 3]
    assert m.to_gold_tokens([[20, 22]], gold) is None


def test_decision_levels():
    assert m.dec({"hidden": True, "win": 2, "conf": "sure"}) == "LIT"
    assert m.dec({"hidden": False, "win": 0, "conf": "sure"}) == "LIT"
    assert m.dec({"hidden": False, "win": 1, "conf": "none"}) == "UND"
    assert m.dec({"hidden": False, "win": 1, "conf": "likely"}) == "EXPR"


def test_end_to_end_fixed_and_broken(tmp_path):
    gold = {"id": "s1", "text": "He was on hand.", "tokens": [[0, 2], [3, 6], [7, 9], [10, 14]],
            "mwes": [{"toks": [2, 3], "cat": "PP", "kind": "strong"}]}
    def sysrec(hidden, win, conf):
        return {"hidden": hidden, "win": win, "conf": conf, "card": False}
    trace = {"id": "s1", "cands": [
        {"phrase": "be on", "cat": "phrasal_verbs", "tokens": [1, 2], "chars": [[3, 6], [7, 9]],
         "sys": {"base": sysrec(False, 2, "sure"), "A": sysrec(True, 0, "likely")}},
        {"phrase": "on hand", "cat": "prepositional_phrases", "tokens": [2, 3], "chars": [[7, 9], [10, 14]],
         "sys": {"base": sysrec(False, 1, "likely"), "A": sysrec(False, 2, "likely")}},
    ]}
    (tmp_path / "g.jsonl").write_text(json.dumps(gold) + "\n")
    (tmp_path / "t.jsonl").write_text(json.dumps(trace) + "\n")
    out = subprocess.run([sys.executable, "-I", os.path.join(HERE, "metrics_5l.py"), str(tmp_path / "t.jsonl"),
                          str(tmp_path / "g.jsonl"), "streusle"], capture_output=True, text=True, check=True).stdout
    res = json.loads(out.split("JSON ", 1)[1].splitlines()[0])
    assert res["base"]["wrong_sure"] == 1 and res["A"]["wrong_sure"] == 0
    assert res["A"]["fixed"] == 1 and res["A"]["broken"] == 0

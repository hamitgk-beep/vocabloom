"""Recompute QC flags of stored results with the current rules. Usage: python3 requalify.py ITEMS.json RESULTS.jsonl"""
import importlib.util, json, pathlib, sys
here = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rf", here / "run_fill.py"); rf = importlib.util.module_from_spec(spec); spec.loader.exec_module(rf)
items = {i["key"]: i for i in json.load(open(sys.argv[1], encoding="utf-8"))}
rows = [json.loads(l) for l in open(sys.argv[2], encoding="utf-8") if l.strip()]
with open(sys.argv[2], "w", encoding="utf-8") as f:
    for r in rows:
        if r.get("senses") and r["key"] in items:
            r["flags"] = rf.qc(r, items[r["key"]])
        f.write(json.dumps(r, ensure_ascii=False) + "\n")
print("requalified", len(rows))

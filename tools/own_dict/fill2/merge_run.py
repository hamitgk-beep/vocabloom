"""Merge one fill run into the branch's current out/ directory. Used by the workflow's commit step.

usage: python3 merge_run.py RUN_DIR OUT_DIR
RUN_DIR holds this run's results.jsonl.gz and summary.json (copied before the branch was reset).
OUT_DIR holds the branch's latest out/ (after git reset). Results are unioned by key, the first
copy wins, so a record already on the branch is never replaced. Spend is the branch's total plus
this run's own spend (summary run_usd), so concurrent or repeated runs cannot lose spend.
"""
import gzip, json, pathlib, sys

run, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)


def read_results(path):
    if not path.exists():
        return []
    with gzip.open(path, "rt", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


seen, rows = set(), []
for r in read_results(out / "results.jsonl.gz") + read_results(run / "results.jsonl.gz"):
    if r["key"] not in seen:
        seen.add(r["key"])
        rows.append(r)
with gzip.open(out / "results.jsonl.gz", "wt", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

run_summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
base = json.loads((out / "spend.json").read_text(encoding="utf-8"))["usd"] if (out / "spend.json").exists() else 0.0
total = round(base + float(run_summary.get("run_usd", 0.0)), 4)
(out / "spend.json").write_text(json.dumps({"usd": total}), encoding="utf-8")
(out / "summary.json").write_text((run / "summary.json").read_text(encoding="utf-8"), encoding="utf-8")
print("records on branch:", len(rows), "spend total:", total)

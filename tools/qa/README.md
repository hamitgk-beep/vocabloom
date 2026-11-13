# Release quality check

Runs in CI after every app build (`.github/workflows/quality.yml`) and can be
run locally:

```sh
python3 tools/qa/audit_dict.py assets/dict.db --baseline tools/qa/baseline.json --out qa-report
flutter test qa_test          # QA_WORDS=1000 QA_EXPRS=60 for a wider sweep, QA_SHOTS=0 for no screenshots
```

Output in `qa-report/`:

- `report.md`: dictionary audit in Turkish, bugs vs. not-yet-translated, per category
- `samples/<check>.tsv`: examples of each finding
- `ui-findings.tsv`: every English line without Turkish, empty heading or layout problem, per panel
- `screens/`: screenshots of the reader panels, Word Family, sentence analysis, each dictionary category and
  the main pages, on phone and desktop, light and dark; `full_*.png` show a whole panel in one picture

The audit fails when a "bug" count is above `baseline.json`. After a fix lowers a count, refresh the baseline
so it cannot come back: `python3 tools/qa/audit_dict.py assets/dict.db --baseline tools/qa/baseline.json --write-baseline`.

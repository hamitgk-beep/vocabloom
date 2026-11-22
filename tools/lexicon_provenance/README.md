# tools/lexicon_provenance

Source traceability and licence gate for the dictionaries (Task 5C). Standard library only; nothing here writes to
`assets/*.db`. Documentation (Turkish): `docs/lexicon_provenance/`.

| File | Purpose |
|---|---|
| `registry.json` | Sources and licences, with the evidence for each value |
| `provenance.py` | Record format, lineage (`independent_count`), the `Gate` rules, JSON/CSV reports |
| `inventory.py` | Provenance records for `dict.db` and `tr_en.db`, from the build code (read-only) |
| `gate.py` | Publish gate CLI: `--mode release` (exit 1 unless all approved) or `--mode legacy` (report only) |
| `report.py` | Per-dictionary traceability numbers |
| `test_provenance.py` | Synthetic tests: `python3 -I -m unittest discover -s tools/lexicon_provenance -p 'test_*.py' -v` |

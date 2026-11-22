# tools/lexicon_remediation (Task 5D)

Standard library only. Nothing here changes `assets/*.db` or publishes anything.

| Tool | Use |
|---|---|
| `release_gate.py` | Dictionary gate run by `release.yml` (`check`, `same-dbs`, `check-workflow`) |
| `dictionary_manifest.json` | Dictionaries the gate may let through, by SHA-256 (decision `gate` / `legacy_exception`; `legacy_exception_proposed` stops a release) |
| `build_candidate.py` | Candidate dictionaries without blocked content, plus `quarantine.db` and `ft_id_map.tsv`, in a work folder |
| `check_candidate.py` | Integrity and impact check of a candidate |
| `tatoeba_ids.py` | Tatoeba pairs with ids, authors, licences; exact matching to the dictionary examples |

Docs: `docs/lexicon_remediation/`. Tests (synthetic data):
`python3 -I -m unittest discover -s tools/lexicon_remediation -p 'test_*.py' -v`

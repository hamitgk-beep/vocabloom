# Storilex Task 5K NLP lab (development only)

Real installs and runs of spaCy, Stanza, UDPipe 1, AMALGrAM 2.0 and DISC, plus the STREUSLE dataset, measured against
the real Storilex expression matcher on the same candidates. **Nothing here is part of the app**: no Python, PyTorch
or model weight goes into the Flutter build, the app gets no network call, and `assets/dict.db` / `assets/tr_en.db`
are only ever opened read-only. Results and the decision: `docs/nlp_engine_research/NLP_ENGINES_REAL_BENCHMARK_5K.md`.

## Layout

| path | what |
|---|---|
| `setup.sh` | venv (Python 3.12, `uv`) + spaCy `en_core_web_sm`/`md` 3.8.0 + Stanza 1.10 English + UDPipe 1 models (sha256-checked); `--external` clones AMALGrAM, DISC, STREUSLE at pinned commits |
| `scripts/amalgram_docker.sh` | AMALGrAM in a `python:2.7` container: tries the original model, then retrains the unmodified code on STREUSLE train |
| `scripts/amalgram_predict_docker.sh` | predicts every `WORKDIR/*.wdpos` with the retrained model |
| `scripts/setup_disc.sh` | DISC in its own venv (`.venv_disc`), checkpoint download attempt |
| `lab5k/engines.py` | one parser -> common token JSONL (`start`/`end` 0-based exclusive, `upos`, `lemma`, `head`, `deprel`) + timing / peak RSS |
| `lab5k/rules.py` | the ONE rule set applied to every parser's tree (frozen as `5K-rules-v2` before any test/final run) |
| `lab5k/bench.py` | candidates from the Dart trace, gold per set, two-level metrics, safety metrics, McNemar, slices, STREUSLE span metrics |
| `lab5k/audit.py` | read-only suspicion scan of all `expr` rows -> `docs/nlp_engine_research/EXPRESSION_MATCH_AUDIT_5K.tsv` |
| `lab5k/streusle_io.py`, `lab5k/amalgram_io.py` | STREUSLE JSON reader, AMALGrAM input/output |
| `dart/baseline_trace_test.dart` | the real Storilex path (matcher, `isLiteral`, `resolve`, reader's longest-first rule) as JSONL |
| `sets/build_final_5k.py`, `sets/final5k_LOCKED.sha256` | the new locked MAGPIE final (local only) and the STREUSLE test hash |
| `data/mini_suite_5k.*` | the 14 transparent sentences of the brief with proxy gold (written by Claude, not human-verified) |
| `requirements-lock.txt`, `requirements-disc-lock.txt` | exact versions installed |
| `tests/test_lab5k.py` | offline tests; model-backed ones skip when models are absent |

`models/`, `external/`, `.venv*`, `logs/`, `out/` are git-ignored: no weights, third-party code or licensed text is committed.

## Reproduce

```bash
tools/nlp_lab_5k/setup.sh --external                     # network: developer setup only
O=/tmp/lab5k; mkdir -p $O/streusle
cp tools/nlp_lab_5k/data/mini_suite_5k.tsv $O/mini.tsv
for s in dev test; do tools/nlp_lab_5k/.venv/bin/python -m lab5k.streusle_io tsv $s $O/streusle/$s.tsv; done   # run from tools/nlp_lab_5k
# Storilex baseline trace (read-only dict.db), from the repository root:
NLP_5K_IN=$O/mini.tsv NLP_5K_OUT=$O/mini.baseline.jsonl flutter test tools/nlp_lab_5k/dart/baseline_trace_test.dart
# each parser (offline):
for e in spacy_sm spacy_md stanza udpipe_ewt25 udpipe_bnosac21; do python -m lab5k.engines $e $O/mini.tsv $O/mini.$e.jsonl $O/perf.jsonl; done
python -m lab5k.bench mini $O                             # metrics + decisions (common JSONL schema)
python -m lab5k.audit ../../assets/dict.db audit.tsv $O   # read-only
python -m pytest -q tests
```
final5k needs MAGPIE (github.com/hslh/magpie-corpus @7fa677b) and the earlier sets rebuilt with
`tools/nlp_research_5f..5j/build_sets_*.py`; `build_final_5k.py` checks every earlier lock and writes the set locally.

## Result schema (`<set>.decisions.jsonl`)

`{"item", "set", "sentence_id", "gold": EXPR|LIT|MENTION, "phrase", "<system>": {"dec": EXPR|UNDECIDED|LIT|MENTION|NONE,
"rule", "shown", "conf": sure|likely|none, "card", "exact", "tr": var|taslak-yeterli-kaynak-yok|yok}}`

The three questions per system: span (`shown`, `exact`), idiomatic vs literal (`dec`), verified Turkish in Storilex (`tr`).

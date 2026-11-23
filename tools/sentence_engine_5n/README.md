# Task 5N tools

Report: `docs/nlp_engine_research/SENTENCE_ENGINE_5N.md`.

- `demo_5n_test.dart`: sentence breakdowns as Markdown (`NLP_5N_IN`, `NLP_5N_OUT`, optional `NLP_5N_MODEL`,
  `NLP_5N_SENSE`, `NLP_5N_DEBUG`).
- `cands_5n_test.dart`, `words_5n_test.dart`: expression candidates / word-meaning choices of sentences (for labelling).
- `check_cls_5n_test.dart`, `export_idiom_cls.py`: export a trained model to the Dart format and check it.
- `train/`: the scripts as run (they use the absolute scratch paths of the run; MAGPIE is read only for evaluation).
- `data/`: our training data: `synthetic_contrastive.jsonl` (written for this project), `pd_expr_labels.jsonl` and
  `pd_sense_labels.jsonl` (public-domain Project Gutenberg sentences, Claude labels), `pg_holdout_phrases.json`,
  and the Python reference outputs of the shipped models.

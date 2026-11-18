# Own English-Turkish dictionary (auto-generated, not yet reviewed)

## Files
- `entries.jsonl.gz`: one record per headword (33,491 in total).
  - `status`: `auto_generated` (written by the AI model, not checked by a person) or `invalid_candidate` (no usable meaning, waiting for approval).
  - `reviewed`: always `false` for now. Nothing here is marked as human-verified.
  - `action`:
    - `replaces_source_tr`: a word whose Turkish in the app today comes only from damdafayton. The new meaning would replace it after review.
    - `add_new`: an expression with no Turkish in the app. Added after review.
    - `skip_existing_turkish`: an expression that already has Turkish in the app. Not imported, so nothing is duplicated.
    - `wait_for_approval`: invalid, typo or uncertain headwords. Nothing is deleted.
  - `qc`: quality-check categories that matched (see `../qc/suspicious.tsv` for details).
  - `existing_tr` (only in the note for words): the meaning the app shows today.
- `invalid_candidates.tsv`: the 12 headwords with no usable meaning, with a verdict and a short note.
- `summary.json`: counts used in the report.

## Source and licence
- Turkish meanings and examples were written by an AI model from the English headword only. No Turkish text from damdafayton (or any other Turkish dictionary) was sent to the model.
- The only extra input was short English hints from WordNet (WordNet licence, free to use).
- The output is our own text, not copied. Facts about word meanings are not protected by copyright, and the wording here is new.
- This is an engineering note, not legal advice. Before the dictionary is published commercially, a short check of the AI provider's terms and of the dictionary's licence is recommended.

## Quality check (no API used)
Run: `python3 tools/own_dict/qc/qc.py <results> <out>`. Main checks:
- empty meanings or examples
- English words left in Turkish meanings
- duplicate senses for one headword
- headword missing from its English example
- sensitive register (slang, insulting uses)

The results are in `../qc/suspicious.tsv` (264 rows). Only 31 headwords need a new translation (16 with English in the Turkish, 15 with empty examples, and 1 with an empty meaning). Duplicate senses can be removed without the API.

## Next steps (waiting for approval)
1. Re-translate the 31 headwords from the high-severity list (one more API run, a few cents).
2. Remove the 93 duplicate senses (no API).
3. Fix the 12 invalid or typo headwords.
4. Decide whether to import the 24,305 replacement words and the 7,856 new expressions into the app database.

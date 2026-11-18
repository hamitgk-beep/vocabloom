# Gap run report: 9,673 words that still carried damdafayton meanings

Status: AI-generated, not reviewed by a person. Nothing imported into `assets/dict.db`; nothing merged to `main`.

## Counts
- Gap list: 9,673 words (Wiktionary meaning first, damdafayton meanings after it).
- Translated: 9,647. Missing from the model answer: 26 (`missing_words.json`). Empty meaning: 1.
- Flagged for a check: 217 words (quality check, `qc` field).
  - English words in the Turkish meaning: 4
  - Empty example: 3
  - Headword not in its English example: 133 (mostly spelling, e.g. "ab initio")
  - Duplicate meaning inside one word: 70 (same part of speech removed later; different parts of speech kept)
- Register check: 248 entries (slang or insulting use) listed for a person in `../review/register_review.tsv` style list; not deleted.

## Cost (measured)
- Four parts: 0.469 + 0.382 + 0.303 + 0.287 = 1.44 USD (batch: about 0.72 USD).
- The estimate was 0.98 USD. The run went over the 1 USD limit and I did not report it before running the parts.

## Comparison with the damdafayton meanings in the app
- The new meanings are written from the English word only, so they do not copy the damdafayton wording.
- For 8,601 words the first three damdafayton meanings are not in the new list (exact-word comparison; synonyms can make this look worse than it is). Only 1,045 keep all three. These need a person's check before replacing.
- Wiktionary meanings (listed first in the app) are not touched.

## Merged dataset
- `merged_entries.jsonl.gz`: 43,138 records = 33,491 earlier records + 9,647 new ones. No duplicate headwords.
- Gap records have `action: replaces_damdafayton_part`, `reviewed: false`.

## Still open (waiting for approval)
1. The 26 missing words (about 0.01 USD).
2. The 4 English-in-Turkish, 3 empty-example and 1 empty-meaning headwords.
3. Import: first the words with no flags and no lost first-three meanings; the rest after a person's check.

# Quality report: own English-Turkish dictionary

Status: AI-generated, **not reviewed by a person**. Nothing was imported into the app database (`assets/dict.db` is unchanged). Original files are unchanged; the review wrote new files only.

## 1. Headwords needing new translations (done)
- Queue: 24 headwords (typos, proper names, empty meaning or example). One API run, 3 requests, 0.0035 USD.
- Result: 23 re-translated and merged. One typo (`nonagression`) is a duplicate of an existing headword, so it is kept as `invalid_candidate` and not imported.
- Old meanings are kept only if they are not already in the new list and their example is complete. Every change is in `change_log.jsonl`.
- Local fixes without API: 9 English words removed from Turkish meanings (e.g. "ah": "ah, of" -> "ah").

## 2. Duplicate meanings (done, no API)
- 36 duplicate senses removed. Only same part of speech and same Turkish meaning were removed.
- 60 remain. They have different parts of speech, so they were kept on purpose.

## 3. Automatic quality check (no API)
Final counts after all fixes (`qc_final/summary.json`):
- English words in Turkish meanings: 11, all proper names of places or music genres (e.g. "Square and Compass, Galler'de bir köy"). Kept on purpose, as the English name is the usual form.
- Examples with an English word in the Turkish example: 58 (mostly quoted words or names).
- Headword not found in its English example: 104 (mostly spelling differences such as "ab initio" vs "abinitio").
- Sensitive register (slang, insults): 927 entries. Listed in `register_review.tsv` for a person to decide. Not deleted, not re-translated.
- Literal-translation risk for short expression glosses: 1,697 (informational only, not an error by itself).

## 4. Comparison with the app's current dictionary (step 5)
Compared with the Turkish the app shows today (`compare_report.tsv.gz`):

| Category | Words | Expressions | Meaning |
|---|---|---|---|
| guvenle_aktarilabilir | 18,376 | - | No flags, none of the first three old meanings lost |
| manuel_kontrol | 5,753 | - | One of the first three old meanings is not in the new list. Needs a person |
| supheli | 176 | - | Quality flags remain (see section 3) |
| gecersiz_bekliyor | 9 | 3 | Invalid candidates, waiting for approval |
| mevcut_korunur | - | 1,318 | Expression already has Turkish in the app. Keep as is |
| yeni_eklenecek | - | 7,856 | No Turkish in the app today. Nothing is lost |

Note: this comparison ran before the 24 re-translations were merged. Those 24 are few and are noted in `change_log.jsonl`.

## 5. Coverage against the target (step 7)
- Target: 42,154 words and 16,098 expressions.
- Words: the app has a Turkish meaning for all 42,154. Our list covers 24,314 words whose meaning comes only from damdafayton.
- **Gap:** 9,673 words have a Wiktionary meaning first and a damdafayton meaning after it. These are not in our list, so damdafayton text remains in the app for them. A second run is needed for this group before damdafayton can be dropped.
- Expressions: 7,859 have no Turkish in the app. Our list covers all of them (7,856 new plus 3 invalid). Nothing is missing there.
- 1,318 expressions in our list already have Turkish in the app and are not imported.
- Expressions that already have Turkish (8,269 distinct phrases in the app) come from earlier sources (AI, hand-written, Wiktionary). They were not re-reviewed here.

## 6. Cost (measured)
- Trial, 200 items: 0.026 USD
- First full run, results lost to a save error: 3.39 USD
- Full run again, 33,259 items: 3.38 USD
- Missing 232 items: 0.023 USD
- Review of 24 items: 0.0035 USD
- Total so far: about 6.82 USD. The first full run is the cost that could have been avoided.

## 7. Safe import plan (not run)
1. Copy `assets/dict.db` to a new file. Do not change the original.
2. Add two new tables (e.g. `own_word`, `own_expr`) with the fields: headword, senses (JSON), status, reviewed, action, source. Do not change `ft` or `expr`.
3. Import first only `guvenle_aktarilabilir` words (18,376) and `yeni_eklenecek` expressions (7,856). Their status stays `auto_generated`.
4. The app reads `own_*` first and falls back to `ft`/`expr`. Nothing is lost if the switch is turned off.
5. A person reviews `manuel_kontrol` (5,753) and `supheli` (176), in batches of 100, sorted by frequency.
6. Only after the review is `verified` a record shown as reviewed. Auto-generated records are never shown as verified.

## Waiting for approval
- Approve the import plan steps 1 to 4 (new tables, no change to current meanings).
- Decide how to handle the 927 register entries and the 9,673 words still using damdafayton text (second run, about 1 USD).

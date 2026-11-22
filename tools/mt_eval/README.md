# Offline OPUS-MT (MarianMT) prototype, English → Turkish

A measurement, not an app feature. It checks whether a free, offline sentence
translator could stand in for Google ML Kit on Windows, where ML Kit does not
run. **Nothing in this folder is bundled with the app, and the app does not
download anything.** No Dart code changes.

## Model and license

| | |
|---|---|
| Model | `Helsinki-NLP/opus-mt-tc-big-en-tr` (Marian transformer-big, OPUS + Tatoeba data), revision `e539fc16a8a1a0ea5950eb339b595bfcce990e90` |
| ONNX export used | `onnx-community/opus-mt-tc-big-en-tr`, **pinned revision `ce128ea834a090aca240e4e113e7756e06cc78e0`** (its model card names the Helsinki-NLP model as `base_model`) |
| Source | https://huggingface.co/onnx-community/opus-mt-tc-big-en-tr · https://huggingface.co/Helsinki-NLP/opus-mt-tc-big-en-tr |
| License | **CC BY 4.0** on both model cards (`license: cc-by-4.0` in the card metadata, checked again on 2026-11-22 through the Hugging Face API). Commercial use is allowed with credit: "OPUS-MT, Helsinki-NLP (Tiedemann et al.), opus-mt-tc-big-en-tr, CC BY 4.0". The app shows this credit in Settings > Offline translation and in Privacy and licenses. |
| Total size | 533,340,371 bytes (about 530 MB, int8). Too large to bundle; the app only offers it as an opt-in download. |
| Special ids | decoder start = pad = 57059, eos = 43741, unk = 52508, vocab 57060 |

Files the app downloads (all from
`https://huggingface.co/onnx-community/opus-mt-tc-big-en-tr/resolve/ce128ea834a090aca240e4e113e7756e06cc78e0/<file>`):

| File | Bytes | SHA-256 |
|---|---:|---|
| `config.json` | 1,099 | `f377425d2cd0b78df07c120c621f1924d3215c46ff4d6e100707054d0a526f8c` |
| `vocab.json` | 1,501,287 | `01ef522455d2bf22b0716416ee34688cc2b3f5fa257f742665d21b6acc450ac1` |
| `source.spm` | 796,953 | `180d3f94ddfee5585d78b702290ded0f4f9bd40f299349c8383b32a579fefad4` |
| `onnx/encoder_model_int8.onnx` | 135,730,164 | `58bfc076347346049a52a8d53b1f6e4664af74e9737aded374d7d1f78805f46e` |
| `onnx/decoder_model_int8.onnx` | 395,310,868 | `44264bac42bc67e6ef5a9f37b9ef364e1b93277026399ca6d90eb5752ee5164b` |

How the hashes were checked: the two ONNX hashes are the Git LFS SHA-256
values the Hugging Face API lists for that revision (`?blobs=true`); the three
small files were downloaded from the pinned revision and hashed with
`sha256sum`. They match the files measured below. The app
(`lib/mt/offline_mt.dart`, PR #108) carries the same list and refuses any file
whose size or SHA-256 differs. `target.spm` is not needed by the app (decoding
uses `vocab.json`), so it is not downloaded.

Reported upstream scores: Tatoeba test chrF 0.687 / BLEU 42.3; FLORES-101 chrF
0.628 / BLEU 31.4.

A smaller alternative, `Helsinki-NLP/opus-mt-en-trk` (Apache-2.0), covers several
Turkic targets with one model and needs a target-language token. It was not
measured here.

## How to run

```
pip install onnxruntime sentencepiece numpy
# download the six files above into <dir> (by hand, not committed)
python3 -I tools/mt_eval/opus_mt_eval.py --model <dir> --dict assets/dict.db \
    --out results.jsonl --tatoeba 200 > results_summary.json
```

`assets/dict.db` is opened read-only; the script reads 200 random Tatoeba
pairs (seed 7, at least 6 words) from the `exs` table as references.
`corpus.tsv` holds the four reported sentences (A–D) and the 64 test-corpus
sentences from `test/sentence_translation_match_test.dart` (PR #105).

The decoding loop is the one a Dart port would run over the app's existing
ONNX Runtime binding (`lib/tts/ort.dart`, float32/int64 tensors):
SentencePiece → vocab ids + `</s>` → encoder once → greedy decoder steps
without a key/value cache (one decoder file) → ids → text.

## Results (4-core Xeon 2.1 GHz, CPU, onnxruntime 1.29, 4 threads)

Full output: `results.jsonl` (256 sentences), `results_summary.json`.

| | |
|---|---|
| Model load | 1.7 s |
| Time per sentence | median 168 ms, p90 302 ms; long academic sentences up to 1.3 s |
| chrF, Tatoeba (200 pairs) | 65.4 |
| chrF, reported sentences A and C | 57.9 (A 62.7, C 53.0) |

Examples:

| English | OPUS-MT |
|---|---|
| where one brother slays the other and buries him under a bush. | Bir kardeş diğerini öldürür ve onu bir çalının altına gömer. ✔ |
| "Mr. Fox, is that you?" whispered Lady Mary. | "Bay Fox, siz misiniz?" diye fısıldadı Leydi Mary. ✔ |
| The painting by J. M. W. Turner was sold in the U.S. for 3.5 million dollars. | J. M. W. Turner'ın resmi ABD'de 3,5 milyon dolara satıldı. ✔ |
| He sat on the bank of the river. / She put her money in the bank. | Nehrin kıyısında oturdu. / Parasını bankaya yatırdı. ✔ |
| They ran out of money before the end of the trip. | Yolculuk bitmeden paraları bitmişti. ✔ |
| I have had greater confidence in my young friends, and have deleted the fairy who did not occur in the tale, as I was told. (C) | Genç arkadaşlarıma daha fazla güvendim ve masalda olmayan periyi bana söylendiği gibi sildim. (meaning drifts: "as I was told" attaches to the wrong verb) |
| For the Beanstalk elsewhere, see Ralston, Russian Folk Tales, 293-8. (D) | Fasulyeler için başka bir yerde, … ✘ ("Beanstalk" is the tale's name) |
| It is raining cats and dogs. | Kediler ve köpekler yağıyor. ✘ (literal idiom) |
| Don't beat around the bush and tell me the truth. | Çalılıklarda gevezelik edip bana gerçeği söyleme. ✘ (idiom and negation wrong) |
| There was a run on the bank that morning. | O sabah bankada bir koşu vardı. ✘ (polysemy) |
| He opened the box …, lay a golden key … | … altın bir anahtar bıraktı. ✘ ("lay" read as "laid") |

## Independent check of the 56 book sentences

Each OPUS-MT answer for the corpus sentences (`corpus.tsv`: the reported
notes, references, long sentences, dialogue, phrasal verbs, idioms, words
with several meanings) was read and graded by hand. The grading was done by
Claude, not by a native speaker, so treat it as indicative.

| Grade | Sentences | Share |
|---|---:|---:|
| Correct (meaning right, Turkish natural enough) | 45 | 80 % |
| Partly right (one word or clause off) | 6 | 11 % |
| Wrong (meaning lost) | 5 | 9 % |

Wrong: "Beanstalk" → "Fasulyeler"; "lay a golden key" → "bıraktı";
"raining cats and dogs" → literal; "beat around the bush" → literal and
negation lost; "a run on the bank" → "koşu". Partly right: the reported
sentence C ("as told to me" attached to "deleted"), "The Constitutional" →
"Anayasa", "Book of Noodles" → "Erişte Kitabı", "hiding in the copper" →
"bakır", "a bag of stones" → "taş bir çanta", and an awkward reference
sentence.

The idiom and several-meanings set in PR #108
(`test/fixtures/mt_eval_cases.json`, 31 sentences, checked with expected and
forbidden Turkish words) gives: idioms 2/9, phrasal verbs 4/4, words with
several meanings 13/17, tale names 0/1. Idioms are the clear weak spot, which
is why the app labels these lines as automatic translation that may contain
mistakes and never uses them for meanings, idioms or review scoring.

## Caveats

- OPUS training data includes Tatoeba, so the Tatoeba chrF is likely
  optimistic. The reported-book sentences are the fairer check.
- chrF punishes correct paraphrases: the lowest Tatoeba scores
  ("Öfkesini kontrol altına alamadı" for "Gazabını zaptedemedi") are mostly
  right. A human check of a sample is still needed.
- Measured on Linux in a cloud container; Windows speed on a typical laptop
  still has to be checked with the same script.
- Idioms and fixed tale names are the weak spot, as with ML Kit.

## Verdict and next steps

Quality on plain narrative sentences is good and comparable to what users see
from ML Kit; speed (about 0.2 s per sentence on CPU) is fine for a tap-to-show
line. Size (530 MB) rules out bundling. If Hamit approves, the next step is a
separate PR that:

1. Ports the loop above to Dart over `lib/tts/ort.dart` (plus a SentencePiece
   tokenizer in Dart or via FFI), Windows only, behind a feature flag.
2. Offers the model as an explicit opt-in download in settings with size, hash
   check and the CC-BY credit, never automatic.
3. Feeds results into the existing sentence cache with
   `engine: 'mt:opus-tc-big-en-tr'`, `dir: 'en>tr'`, so it slots into the
   order verified record → cache → device MT → paid AI (only with permission).
4. Keeps the same hide-on-failure rule: no translation line rather than a
   wrong or placeholder one.

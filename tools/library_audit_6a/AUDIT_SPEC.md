# Library audit (Task 6A): checking the reader's readings of the bundled stories

Input: a JSONL file. Each line is one sentence from a children's story bundled with the app:
`{"sid", "text", "prev", "next", "items": [...]}`. `prev` / `next` are the sentences around it (context only).
Each item asks one question about this sentence. Judge as a careful lexicographer and English teacher.

## Item kinds

### `"kind": "expr"`: is this multi-word expression used here?

`{"q": "e3", "kind": "expr", "phrase": "run after", "cat": "phrasal_verbs", "words": "runs after", "choices": [...]}`

`words` are the words of the sentence the dictionary matched to `phrase` (they may be split: "turned … off").
Answer `"unit": true` when these words ARE used as the expression `phrase` in this sentence (its fixed,
dictionary meaning), `"unit": false` when they are just the separate words with their ordinary meanings
("He kicked the bucket across the yard" is NOT "kick the bucket"; "lived in Kansas" is NOT "live in" =
reside in a college; "look at the sky" IS "look at"). A phrasal verb or prepositional verb whose meaning is the
plain sum of its words but which is still a common fixed combination ("run after" = chase, "look at", "go back")
counts as `true`. A collocation category (`cat` "collocations") is `true` when the words go together as that
collocation here.

When `unit` is true and `choices` lists two or more numbered meanings `"pos: English definition"`, add `"pick"`:
the index of the meaning that fits here, or -1 if none fits.

### `"kind": "word"`: which meaning of this word?

`{"q": "w7", "kind": "word", "word": "sees", "head": "see", "choices": [...]}`

`choices`: every meaning the dictionary has for `head`, numbered, as `"pos: English definition"`.
Answer `"pick"`: the index of the meaning that fits the word in THIS sentence: the right part of speech and the
right sense. Several meanings can be near-duplicates; pick the closest one. If none fits, `"pick": -1` with
`"why"`:

- `"name"`: the word is a name here (a person, animal or place called "Blacky", "Bear" as a name, "King" as a title
  before a name is still the word).
- `"expr"`: the word only makes sense as part of a fixed expression around it that has no item here
  ("hold" in "get hold of", "far" in "far more").
- `"missing"`: an ordinary use of the word, but the dictionary has no fitting meaning. Then also give `"need"`:
  a short English definition of the missing meaning (e.g. "move quickly on foot") in your own words.
- `"other"`: anything else (broken text, a typo, not English); add a few words in `"note"`.

Do not invent Turkish. You never write Turkish here.

## Output

JSONL, one line per item, in input order: `{"q": "<q>", "unit": true|false, "pick": <int>}` for expr items
(`pick` only when asked), `{"q": "<q>", "pick": <int>}` or `{"q": "<q>", "pick": -1, "why": "...", ...}` for words.

Rules for writing the file: write your answers in numbered groups and check each group's count, so a shifted index
cannot go unnoticed. Then check with a short Python one-liner that every input `q` appears exactly once, in order,
with valid values (`pick` in range or -1). Report only: the output path, the number of lines, the number of
`unit: false` and the number of `pick: -1` by `why`.

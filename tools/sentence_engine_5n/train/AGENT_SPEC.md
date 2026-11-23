# Writing contrastive training sentences (Task 5N)

Input: a TSV file, one dictionary expression per line: id, phrase, category, English definition(s) (";"-separated).
Output: a JSONL file (one JSON object per line), for EVERY input line:

{"id": <id>, "phrase": "<phrase>", "sentence": "<sentence with the expression's own words wrapped in [ ]>", "label": "i" | "l"}

- "i" = the words are used as the expression (its dictionary meaning). Write 3 such sentences.
- "l" = the same words appear together (same or very close word order) but are NOT the expression: literal / compositional
  use, or a different structure ("He was on the bridge" for "be on"; "The boy kicked the bucket across the yard";
  "She looked up at the sky" for "look up" = search). Write 3 such sentences when a literal or non-expression use is at
  all natural; if it really is impossible, write 1–2 near-miss sentences where the words co-occur in another structure.
- Wrap exactly the expression's words in square brackets, each continuous piece separately if split:
  "She [turned] the radio [off]." / "He [kicked the bucket] last week." Placeholders like "sb"/"sth"/"one's" are NOT
  bracketed (the object/possessive filler stays outside the brackets).
- Vary naturally: tense, person, plural, negation, questions, possessives, an adverb or adjective inside, passive where
  natural. Everyday English, 6–25 words, learner-readable. Never copy sentences from books, corpora or dictionaries;
  write new ones. Do not reuse the same frame across expressions.
- The sentence alone must make the reading clear to a careful human reader (no ambiguous coin-flips).
- Write the file with the Write tool (not a shell heredoc), then check it with a short Python one-liner that every line
  parses as JSON, every id of the input appears, and every sentence has at least one [ ... ] pair. Fix and rewrite if not.
Report only: the output path, number of lines, number of "i" and "l" lines.

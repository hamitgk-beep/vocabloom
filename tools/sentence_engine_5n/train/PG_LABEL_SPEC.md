# Labelling expression candidates in public-domain book sentences (Task 5N)

Input: a JSONL file; each line {"key", "phrase", "def", "sentence"}. The sentence comes from a public-domain book;
the words a dictionary matcher matched to the expression "phrase" are wrapped in [ ] ("def" is one English
definition of the expression, sometimes empty; the expression may have other meanings too).

Decide for EVERY line whether, in this sentence, the bracketed words are used AS THE EXPRESSION:

- "i": the bracketed words work together as the expression (one of its fixed/idiomatic/phrasal meanings, or its
  fixed grammatical pattern, e.g. "belong to" = be owned by / be a member of, "start out" = begin a journey,
  "in fact" as a discourse marker). A learner should learn these words as one unit here.
- "l": they are NOT the expression here: each word keeps its own plain meaning, or the words only happen to stand
  next to each other in a different structure ("a lesson [in perspective]" = a lesson about perspective; "he [looked
  up] at the sky" for look up = search; "the boy [kicked the bucket] over"; "[in] the [case] of the clock").
- "u": you genuinely cannot decide from the sentence (use rarely).

Judge carefully, as a linguist would, from the whole sentence. Do not let the label depend on how common the
expression is. Old-fashioned language is normal here.

Output: a JSONL file with one line per input line, in the same order: {"key": "<key>", "label": "i" | "l" | "u"}.
Write the file with the Write tool (not a shell heredoc); you may write it in several parts and join them with a
short Python command. Then check with a short Python one-liner that every input key appears exactly once with a
valid label. Report only: the output path and the counts of i, l, u.

Scratch files: use ONLY your own private folder /tmp/claude-0/-home-user/5e73f4d5-1e15-53a0-a389-22f86d51c073/scratchpad/<your output file name without .jsonl>/
(other workers run at the same time). If you write labels as a list and join them with the keys, write them in
numbered groups (e.g. "0-49: i i l ...") and check the count of each group, so a shifted index cannot go unnoticed.

# Choosing a word's meaning in public-domain book sentences (Task 5N)

Input: JSONL, each line {"key", "word", "sentence", "choices"}. In the sentence (from a public-domain book) one word is
wrapped in [ ]; "word" is its dictionary base form; "choices" is a numbered list (0, 1, 2 …) of dictionary definitions
"pos: definition" (pos n = noun, v = verb, a/s = adjective, r = adverb).

For EVERY line pick the index of the definition that best fits the bracketed word in this sentence: the right part
of speech and the right meaning. If none of them fits (wrong part of speech for all, or the word is part of a fixed
expression/name and no definition fits), answer -1. Judge as a careful lexicographer; old-fashioned language is normal.

Output: JSONL, one line per input line in the same order: {"key": "<key>", "pick": <index or -1>}.
Scratch files: use ONLY your own private folder
/tmp/claude-0/-home-user/5e73f4d5-1e15-53a0-a389-22f86d51c073/scratchpad/<your output file name without .jsonl>/
(other workers run at the same time). If you write the picks as a list and join them with the keys, write them in
numbered groups (e.g. "0-49: 1 0 -1 ...") and check each group's count, so a shifted index cannot go unnoticed.
Write files with the Write tool (a short Python command may join parts). Then check with a short Python one-liner that
every input key appears exactly once, in order, with an integer pick in range. Report only: the output path, the
number of lines and the number of -1 picks.

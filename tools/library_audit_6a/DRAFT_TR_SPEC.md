# Turkish drafts for dictionary meanings that have none (Task 6A)

Input: JSONL, one line per dictionary meaning: `{"id", "lemma", "pos", "en", "examples": [up to 3 sentences from the
app's stories where this meaning was checked to be the one used]}`. `en` is the English (WordNet) definition.

For every line write a short Turkish equivalent of THIS meaning, as a Turkish dictionary would list it: one to three
comma-separated words or short phrases, most common first, the part of speech kept (a verb as a Turkish verb in the
infinitive, "-mak/-mek"; a noun as a noun; an adjective as an adjective). Write it for a Turkish learner of English
reading these sentences. Do not translate the definition; give the word(s) a Turkish speaker would use. If you are not
sure of a good Turkish equivalent, say so with `"unsure": true` instead of guessing.

Output: JSONL, one line per input line, in order: `{"id": "<id>", "tr": "<Turkish>"}` or
`{"id": "<id>", "tr": "<best try or empty>", "unsure": true}`.

Check with a short Python one-liner that every input id appears once, in order. Report only: output path, line count,
number of unsure.

These are drafts. A person checks them before anything enters the dictionary; nothing here is shown as certain.

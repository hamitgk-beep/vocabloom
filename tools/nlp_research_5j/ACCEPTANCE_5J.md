# Task 5J: go / no-go rule, frozen before the final run

Written after development on 5H dev/tune and the dictionary review audit, before any system ran on
`final5j_magpie.tsv` / `hold5j_magpie.tsv` (hashes locked in `final5j_LOCKED.sha256`, commit 719dfe6).

Candidate (chosen on dev/tune): `SenseEngine.wordCardGuard = WordCardGuard.idiom` with `cardCarries = true`.
Fallback candidate: `WordCardGuard.undecided` with `cardCarries = true`.

Unit: a word card (a content word of the matched expression in a MAGPIE sentence), card path "quiz"
(ReviewQuiz.answerFor with the sentence, nothing saved; graded = four choices).

The candidate is switched on by default only if ALL hold on final5j:
- G1 Safety: fewer graded cards on gold-idiom sentences than the 5I engine, McNemar exact p < 0.05.
- G2 No new grading anywhere (a guard only vetoes), expression readings and expression-card verdicts identical.
- G3 Net per card at the natural idiomatic share of MAGPIE (pi = 0.71, 40,011 / 56,179 i+l labels):
  pi * r_i * w_i  >  (1 - pi) * r_l * w_l, where r_i / r_l are the vetoed-accept rates on idiom / literal word
  cards of final5j and w_i / w_l the shares of those vetoes that were really wrong / really right accepts,
  read by hand (by Claude, an AI; not a human label) on up to 30 vetoed cards each, with weights 1 : 1.
  Must also hold with w_i = w_l = 1 (MAGPIE labels alone).
- G4 Ordinary sentences (dictionary review audit, 1,500 most frequent words): at most 3 % of graded cards lost.
If the candidate fails, the fallback is checked with the same rule; if it fails too, the default stays OFF.
hold5j (new sentences of the development idioms) is reported apart and never used to decide.

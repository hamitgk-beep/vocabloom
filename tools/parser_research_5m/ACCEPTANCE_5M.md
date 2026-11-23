# Task 5M: acceptance criteria, written BEFORE the single final run

Final set: `final_tweets` (DiMSUM 2016 train, Lowlands + Ritter tweets, 969 sentences), hashed in
`final_5m_LOCKED.sha256` (commit 433b8b7) before any 5M code existed. It is run **once**, with the code and weights
frozen in the commit that adds this file. Nothing is tuned on it. Development used only sets already opened before:
STREUSLE train+dev (training data of the unit scorer and of the neural taggers), DiMSUM test and PARSEME 1.1 EN
(opened in 5L; used here to choose C, the threshold and the lexical features).

Baseline `cur` = the app today (5L default: PhraseMatcher + SenseEngine with rule A).

Neural taggers (secondary): trained only on STREUSLE train+dev with the fixed settings of `neural_tagger_5m.py`
(3 epochs); their final predictions are made once, after this commit.

Primary system: `unit` = `tpl` (sequence matches + template matches on the one parse) and the unit scorer
(`lib/nlp/unit_weights_5m.dart`, C = 1.0, lexical features on, threshold 0.40) hides a candidate shown with a
meaning when it scores below the threshold. Secondary, reported but not decided on: `tpl` alone, `unitS` (`unit`
but a candidate SenseEngine calls "sure" with a checked meaning is never hidden), and the neural taggers.

`unit` is accepted (may be proposed as default ON in a later task) only if ALL hold on final_tweets vs `cur`:

1. More decisions fixed than broken, exact McNemar p < 0.05.
2. Candidate-level F1 higher.
3. Wrong "sure" (gold not a unit, shown sure) not higher.
4. Right "sure" lost at most max(2, 10 % of `cur`'s right "sure").
5. Exact-span F1 not lower by more than 0.01.
6. `assets/dict.db` and `assets/tr_en.db` SHA-256 unchanged.

If any criterion fails, the flag stays OFF and the report says which one failed. Either way the flag stays OFF in
this PR: turning it on is Hamit's decision (known trade-off: "The TV was on all night" loses its "be on" underline).

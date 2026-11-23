# Task 5L — acceptance criteria (written and committed before any 5L rule exists)

## Sets and their roles
| set | labels | role |
|---|---|---|
| mini suite 5K (14 sentences) + 5L contrast pairs | written by Claude (proxy) | regression / demo only, never success evidence |
| dev_streusle (STREUSLE 4.x train+dev, 3,279) | human | design and ablation (already seen in 5K) |
| hold_dimsum (DiMSUM 2016 test, 1,000: TrustPilot, Tweebank, TED) | human, strong MWEs | locked holdout, run once per frozen candidate |
| hold_parseme (PARSEME 1.1 EN, 6,844, STREUSLE/mini sentences removed) | human, verbal MWEs | locked holdout; scored only on `phrasal_verbs` candidates (PARSEME labels verbal MWEs only) |

Neither holdout was used by 5F–5K. They are **partly independent**: new sentences and new annotators, but the
annotation guidelines (DiMSUM follows STREUSLE) and the dictionary's expression types are not new. MAGPIE
(5F–5K) and STREUSLE test (5K) are not reused as finals.

## Label unit
Gold EXPR for a Storilex candidate = all its tokens are inside one gold MWE of the sentence (strong or weak for
STREUSLE; strong for DiMSUM; any VMWE category for PARSEME). Else LIT. This is "is it a lexical unit here", not
"is the Turkish right" and not "is a single-word card wrong".

## Decision of a system on a candidate
EXPR = the reader underlines it (not hidden as literal, wins its tokens) and the panel shows its meaning;
UNDECIDED = shown with "cannot tell"/none; LIT = hidden or loses all its tokens. Wrong sure = gold LIT and EXPR+sure.
Card accept (proxy) = EXPR + sure + checked Turkish (not an AI draft).

## A rule becomes default ON only if, on hold_dimsum + hold_parseme together
1. changed decisions: fixed >= 3 and broken <= fixed / 4;
2. wrong "sure" does not go up, and lost right "sure" <= fixed wrong "sure" + 1;
3. right card accepts blocked <= 1;
4. span exact-match F1 does not drop by more than 0.005 on either holdout;
5. the regression pairs keep: "The TV was on all night" still offers `be on`, "on the run" / "hot air" (5I) unchanged.
Otherwise the rule stays OFF (research). Too few changed decisions (< 3) = not enough evidence = OFF.

## Frozen candidate (added after the dev ablation, before any holdout run)
Dev (STREUSLE train+dev, 2,033 candidates; vs the 5K engine): A +13/−0 (all in `be`+particle, wrong sure 92→88,
cards unchanged); A2 +20/−7 (3 right cards blocked); B +18/−10; C wrong sure 92→85 but right sure 153→145 and
3 right cards blocked; D wrong sure 92→88, no decision changed; A+B +28/−10. Only **A** (`copulaObject`) meets the
dev bar; it is the one candidate run against the holdouts. A2, B, C, D are reported there for information only and
cannot be switched on from that run.

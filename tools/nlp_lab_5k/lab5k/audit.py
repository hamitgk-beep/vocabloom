"""Read-only audit of every expression record in assets/dict.db (Task 5K, section B4/G-D).

usage: python -m lab5k.audit assets/dict.db OUT.tsv [EVIDENCE_DIR]
Opens the database read-only (mode=ro). Changes nothing: every row is a SUSPICION for human review, never a fix.
EVIDENCE_DIR (optional, local): STREUSLE train+dev decision files from lab5k.bench; only counts are written.
The TSV holds dictionary keys, classes and counts only: no sentence text from any licensed corpus.
"""
import json
import os
import sqlite3
import sys
from collections import Counter, defaultdict

FUNCTION = {"the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "for", "with", "by", "is", "are", "was",
            "were", "be", "been", "being", "it", "this", "that", "he", "she", "they", "we", "you", "i", "his", "her", "their",
            "as", "from", "not", "so", "if", "than", "then", "there", "have", "has", "had", "do", "does", "did", "my",
            "your", "its", "our", "me", "him", "them", "one", "some", "any", "all", "what", "which", "who", "when", "where",
            "how", "into", "out", "up", "down", "off", "over", "about", "away", "back", "around", "through", "get", "go",
            "come", "make", "take", "put", "set", "let", "sb", "sth", "one's", "oneself", "someone", "something", "no", "yes"}
PARTICLES = {"up", "down", "on", "off", "in", "out", "away", "back", "over", "around", "about", "through", "by", "along",
             "after", "for", "with", "into", "onto", "across", "at", "to", "from", "of", "under"}
LIGHT = {"be", "have", "get", "go", "come", "make", "take", "do", "put", "set", "let", "give", "keep"}
# Grammar-style categories: STREUSLE does not annotate most of them as MWEs, so "not an MWE in STREUSLE" is
# no evidence of an error there (only of a different convention).
GRAMMAR_CATS = {"conjunctions", "modal_verbs", "dependent_prepositions", "polite_phrases", "discourse_markers", "chunks"}
MULTI_CATS = {"phrasal_verbs", "idioms", "collocations", "prepositional_phrases", "binomials", "chunks", "proverbs",
              "similes", "polite_phrases", "dependent_prepositions", "discourse_markers"}


def classes(phrase, cat, starts_pp):
    w = phrase.lower().split()
    c = []
    if len(w) == 1 and cat in MULTI_CATS:
        c.append("SINGLE_WORD_IN_MULTIWORD_CATEGORY")
    if len(w) >= 2 and all(x in FUNCTION for x in w):
        c.append("FUNCTION_WORDS_ONLY")
    if len(w) == 2 and w[0] == "be" and w[1] in PARTICLES:
        c.append("BE_PLUS_PARTICLE")
    elif len(w) == 2 and w[0] in LIGHT and w[1] in PARTICLES:
        c.append("LIGHT_VERB_PLUS_PARTICLE")
    if cat == "phrasal_verbs" and len(w) == 2 and w[-1] in PARTICLES and starts_pp.get(w[-1], 0) > 0:
        c.append("PARTICLE_ALSO_STARTS_PREP_PHRASES")
    if cat == "idioms" and len(w) == 2 and not any(x in FUNCTION for x in w):
        c.append("TWO_CONTENT_WORD_IDIOM_LITERAL_RISK")
    if any(x in ("sb", "sth", "someone", "something") for x in w) and len(w) <= 2:
        c.append("WILDCARD_SHORT_PATTERN")
    return c


def main():
    dbp, outp = sys.argv[1], sys.argv[2]
    ev = sys.argv[3] if len(sys.argv) > 3 else None
    db = sqlite3.connect(f"file:{dbp}?mode=ro", uri=True)
    own = {}
    for p, c, st, rev in db.execute("SELECT phrase, cat, status, reviewed FROM own_expr"):
        own[(p, c)] = (st, rev)
    rows = list(db.execute("SELECT id, phrase, cat, tr FROM expr"))
    starts_pp = Counter(p.split()[0] for _, p, c, _ in rows if c == "prepositional_phrases" and " " in p)
    occ = defaultdict(Counter)
    if ev:
        for name in ("streusle_train", "streusle_dev"):
            fp = os.path.join(ev, name + ".decisions.jsonl")
            if not os.path.exists(fp):
                continue
            for l in open(fp, encoding="utf-8"):
                r = json.loads(l)
                b = r["baseline"]
                o = occ[r["phrase"]]
                o["occ"] += 1
                o["gold_" + r["gold"]] += 1
                if b["dec"] == "EXPR" and r["gold"] != "EXPR":
                    o["baseline_fp"] += 1
                if b["conf"] == "sure" and r["gold"] != "EXPR":
                    o["baseline_wrong_sure"] += 1
    total = Counter()
    with open(outp, "w", encoding="utf-8") as f:
        f.write("expr_id\tphrase\tcategory\tn_words\tsuspicion_classes\tturkish_source\town_expr_status\t"
                "streusle_trdev_occurrences\tstreusle_gold_expr\tstreusle_gold_literal\tbaseline_false_expr\tbaseline_wrong_sure\t"
                "risk\tevidence_note\n")
        for i, p, c, tr in rows:
            cl = classes(p, c, starts_pp)
            o = occ.get(p, Counter())
            if o.get("baseline_fp", 0) >= 2 and o["baseline_fp"] >= o.get("gold_EXPR", 0):
                cl.append("STREUSLE_CONVENTION_DIFFERS" if c in GRAMMAR_CATS else "OBSERVED_MOSTLY_FALSE_IN_STREUSLE")
            if not cl:
                continue
            st = own.get((p, c))
            src = "dictionary" if (tr or "").strip() else ("ai_draft_only" if st and st[0] == "ai_draft_unreviewed" else "none")
            risk = "high" if ({"BE_PLUS_PARTICLE", "FUNCTION_WORDS_ONLY", "OBSERVED_MOSTLY_FALSE_IN_STREUSLE"} & set(cl)) else \
                   "medium" if ({"LIGHT_VERB_PLUS_PARTICLE", "TWO_CONTENT_WORD_IDIOM_LITERAL_RISK", "WILDCARD_SHORT_PATTERN"} & set(cl)) else "low"
            note = []
            if "PARTICLE_ALSO_STARTS_PREP_PHRASES" in cl:
                note.append(f"{starts_pp[p.split()[-1]]} prepositional_phrases entries start with '{p.split()[-1]}' (overlap conflicts like be on / on hand)")
            if "STREUSLE_CONVENTION_DIFFERS" in cl:
                note.append("grammar-style category: STREUSLE leaves it unannotated; not evidence of an error")
            if "BE_PLUS_PARTICLE" in cl:
                note.append("matches every 'was/is/are + particle' through the lemma be")
            f.write("\t".join(map(str, [i, p, c, len(p.split()), ",".join(cl), src, f"{st[0]}/{st[1]}" if st else "-",
                                        o.get("occ", 0), o.get("gold_EXPR", 0), o.get("gold_LIT", 0), o.get("baseline_fp", 0),
                                        o.get("baseline_wrong_sure", 0), risk, "; ".join(note) or "-"])) + "\n")
            total["rows"] += 1
            total["risk_" + risk] += 1
            for x in cl:
                total[x] += 1
    total["expr_rows_scanned"] = len(rows)
    print(json.dumps(dict(sorted(total.items())), indent=1))


if __name__ == "__main__":
    main()

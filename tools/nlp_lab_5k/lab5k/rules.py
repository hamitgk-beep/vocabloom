"""Task 5K candidate filter: the SAME hand-written rules applied to the output of every parser.

The parsers (spaCy, Stanza, UDPipe) only give tokens, POS, lemmas and dependency trees. None of them is an idiom
classifier. Every decision below is a rule written for this task (by Claude), kept apart from the model output so
the ablation can tell what the parser contributes and what the rule contributes.

Candidates are ALWAYS the real Storilex matcher's matches (tools/nlp_lab_5k/dart/baseline_trace_test.dart), so
every system sees the same dictionary and the same candidate spans. A rule can only lower certainty (EXPR ->
UNDECIDED -> LIT); it never raises a baseline 'likely' to 'sure' and never invents a candidate.

Decisions: EXPR (shown as the expression), UNDECIDED (shown, but the system cannot tell; never 'sure'),
LIT (the words are there but this is not the expression: hidden), MENTION (quoted / talked about: hidden).
"""
PARTICLES = {"up", "down", "on", "off", "in", "out", "away", "back", "over", "around", "about", "through", "by",
             "along", "after", "for", "with", "into", "onto", "across", "ahead", "apart", "aside", "forward",
             "together", "under", "round", "at", "to", "from", "of", "upon", "behind", "past", "without"}
QUOTES_OPEN = set("'\"‘“`")
QUOTES_CLOSE = set("'\"’”`")
NOMINAL = {"NOUN", "PROPN", "PRON", "NUM", "ADJ", "X"}
FREEZE = "5K-rules-v2"
CAP = "|cap-likely"  # shown as the expression, but never 'sure' (so no word card is graded on it)


class Parse:
    """One parser's tree, normalised (UD and spaCy/ClearNLP labels), indexed by STORILEX token."""

    def __init__(self, ptoks, stoks):
        self.p = ptoks
        self.s2p = []
        for t in stoks:
            best, ov = None, 0
            for j, q in enumerate(ptoks):
                o = min(t["end"], q["end"]) - max(t["start"], q["start"])
                if o > ov:
                    best, ov = j, o
            self.s2p.append(best)
        self.p2s = {}
        for i, j in enumerate(self.s2p):
            if j is not None:
                self.p2s.setdefault(j, i)
        self.children = {}
        for j, q in enumerate(ptoks):
            self.children.setdefault(q["head"], []).append(j)

    def ok(self, idx):
        return all(self.s2p[i] is not None for i in idx)

    def rel(self, j):
        r = self.p[j]["deprel"].lower()
        return {"prt": "compound:prt", "dobj": "obj", "root": "root"}.get(r, r)

    def upos(self, j):
        return self.p[j]["upos"]

    def head(self, j):
        return self.p[j]["head"]

    def pp_object(self, j):
        """The nominal a preposition introduces (UD: P is 'case' of it; ClearNLP: its 'pobj' child), or None."""
        r = self.rel(j)
        if r == "case" and self.head(j) >= 0 and self.upos(self.head(j)) in NOMINAL:
            return self.head(j)
        if r in ("prep", "agent", "dative"):
            for c in self.children.get(j, []):
                if self.rel(c) in ("pobj", "pcomp"):
                    return c
        return None

    def is_particle_of(self, j, v):
        return self.rel(j) == "compound:prt" and self.head(j) == v

    def compound_of_outside(self, j, span):
        """Token j is a compound modifier of a noun right after the span ('hot air BALLOON')."""
        h = self.head(j)
        return self.rel(j) == "compound" and h > j and h not in span and self.upos(h) in ("NOUN", "PROPN")


def quoted(text, toks, idx):
    a, b = toks[idx[0]]["start"], toks[idx[-1]]["end"]
    before = text[a - 1] if a > 0 else ""
    after = text[b] if b < len(text) else ""
    return before in QUOTES_OPEN and after in QUOTES_CLOSE


def baseline_decision(m):
    """What the reader does today with a multiword match (see dart/baseline_trace_test.dart)."""
    if m["literal_hidden"]:
        return "LIT"
    return "EXPR" if m["conf"] in ("sure", "likely") else "UNDECIDED"


def decide(rec, m, parse, use_parser=True, use_surface=True):
    """(decision, rule tag) for one candidate. parse=None or use_parser=False -> parser-free rules only."""
    toks, idx = rec["tokens"], sorted(m["tokens"])
    pat = m["phrase"].split()
    base = baseline_decision(m)
    if use_surface and quoted(rec.get("text", ""), toks, idx):
        return "MENTION", "R0-quoted"
    if use_surface and m["cat"] == "phrasal_verbs" and pat[0] == "be" and len(pat) == 2:
        # copula + particle: a state ('the TV was on') or a preposition ('was on the bridge'); never sure
        if use_parser and parse is not None and parse.ok(idx):
            p = parse.s2p[idx[1]]
            if parse.pp_object(p) is not None:
                return "LIT", "R1-be+prep-has-object"
        return "UNDECIDED", "R1-be+particle"
    if not use_parser or parse is None or not parse.ok(idx):
        return base, "baseline" if parse is None or not use_parser else "noalign"
    pj = [parse.s2p[i] for i in idx]
    if base == "LIT":
        return base, "baseline-literal"
    if m["cat"] == "phrasal_verbs" and len(pat) >= 2:
        v = pj[0]
        parts = [j for i, j in zip(idx[1:], pj[1:]) if rec["tokens"][i]["text"].lower() in PARTICLES]
        if parts:
            p = parts[0]
            if parse.is_particle_of(p, v):
                return base, "R2-particle-of-verb"
            # The parser cannot tell 'look for the keys' (an expression) from 'walked into the room' (free words)
            # (STREUSLE train: about half each), so these stay shown but are never 'sure' (no card is graded).
            if parse.pp_object(p) is not None and parse.pp_object(p) not in pj:
                return base, "R3-preposition-with-own-object" + CAP
            return base, "R4-particle-not-attached" + CAP
        return base, "pv-other"
    content = [i for i, w in zip(idx, pat) if w not in PARTICLES and w not in ("a", "an", "the", "sb", "sth", "one's")]
    if m["cat"] == "prepositional_phrases" and toks[idx[0]]["text"].lower() in PARTICLES and content:
        obj = parse.pp_object(pj[0])
        if obj is not None and obj in pj:
            return base, "R5-pp-constituent"
        return "UNDECIDED", "R5-pp-not-constituent"
    last = pj[-1]
    if parse.upos(last) in ("NOUN", "PROPN") and parse.compound_of_outside(last, set(pj)):
        return "LIT", "R6-modifier-of-outside-noun"
    return base, "baseline-kept"


def resolve_overlaps(rec, ms, decisions, parse, use_parser=True):
    """R7: a candidate holding a preposition but not its object loses to one holding both ('was on' vs 'on hand')."""
    if not use_parser or parse is None:
        return decisions
    out = list(decisions)
    for a, ma in enumerate(ms):
        if out[a][0] in ("LIT", "MENTION") or not parse.ok(ma["tokens"]):
            continue
        for b, mb in enumerate(ms):
            if a == b or out[b][0] in ("LIT", "MENTION") or not parse.ok(mb["tokens"]):
                continue
            shared = set(ma["tokens"]) & set(mb["tokens"])
            for i in shared:
                j = parse.s2p[i]
                obj = parse.pp_object(j)
                if obj is None:
                    continue
                objs = parse.p2s.get(obj)
                if (objs in mb["tokens"] and objs not in ma["tokens"] and not out[a][1].startswith("R2")
                        and not set(ma["tokens"]) <= set(mb["tokens"])):
                    out[a] = ("LIT", "R7-loses-preposition-to-" + mb["phrase"])
    return out


def winners(rec, ms, decisions, order):
    """Per token, the shown candidate: not LIT/MENTION, longest first, then filter order (as the reader does)."""
    n = len(rec["tokens"])
    win = [None] * n
    for i in range(n):
        c = [k for k, m in enumerate(ms) if i in m["tokens"] and decisions[k][0] in ("EXPR", "UNDECIDED")]
        c.sort(key=lambda k: (-len(ms[k]["tokens"]), order.get(ms[k]["cat"], 99)))
        win[i] = c[0] if c else None
    return win

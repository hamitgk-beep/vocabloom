"""AMALGrAM input/output: tokens+PTB POS in, MWE groups (as character spans) out.

wdpos: "word\\tPOS\\t\\tsentid" per token, blank line between sentences (AMALGrAM's 4-column input).
pred.tags (AMALGrAM output): offset, word, lemma, POS, tag, parent offset, strength, label, sentid.
"""
import json
import sys


def write_wdpos(sents, path, sidecar):
    """sents: [(sid, [(word, pos, start, end), ...])]. sidecar keeps the offsets for reading the output back."""
    side = {}
    with open(path, "w", encoding="utf-8") as f:
        for sid, toks in sents:
            side[sid] = [(a, b) for _, _, a, b in toks]
            for w, p, _, _ in toks:
                f.write(f"{w}\t{p}\t\t{sid}\n")
            f.write("\n")
    json.dump(side, open(sidecar, "w"))


def read_groups(tags_path, sidecar):
    side = json.load(open(sidecar))
    out, cur, sid = {}, [], None

    def flush():
        if sid is None or not cur:
            return
        par = {}
        for off, parent in cur:
            par[off] = parent
        root = {}

        def find(x):
            while par.get(x, 0):
                x = par[x]
            return x
        groups = {}
        for off, _ in cur:
            r = find(off)
            groups.setdefault(r, []).append(off)
        spans = side[sid]
        out[sid] = [[spans[o - 1] for o in sorted(g)] for g in groups.values() if len(g) >= 2]

    for line in open(tags_path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip():
            flush()
            cur, sid = [], None
            continue
        c = line.split("\t")
        sid = c[8] if len(c) > 8 else sid
        cur.append((int(c[0]), int(c[5]) if c[5] not in ("", "_") else 0))
    flush()
    return out


if __name__ == "__main__":
    tags, side, outp = sys.argv[1:4]
    json.dump(read_groups(tags, side), open(outp, "w"))

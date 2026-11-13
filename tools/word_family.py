"""Word families (create / creation / creator / creative / creatively ...) from
WordNet's lexical links: derivationally related forms (+), pertainyms (\\)
and antonyms (!), plus common negative prefixes (un-, in-, dis- ...).

build_families(wordnet_dir) -> {word: (root, [(lemma, pos), ...], [(neg, pos, base)])}
"""
import os
import re

POS = {'n': 'n', 'v': 'v', 'a': 'a', 's': 'a', 'r': 'r'}
NEG_PREFIXES = ('un', 'in', 'im', 'il', 'ir', 'dis', 'non')


def _read(wn):
    synwords = {}  # (offset, pos) -> [words]
    links = []     # ((offset,pos), src, sym, (offset,pos), tgt)
    for name in ('noun', 'verb', 'adj', 'adv'):
        with open(os.path.join(wn, f'data.{name}'), encoding='utf-8') as f:
            for line in f:
                if line.startswith(' '):
                    continue
                t = line.partition('|')[0].split()
                off, pos = t[0], POS[t[2]]
                wcnt = int(t[3], 16)
                words = [re.sub(r'\(.*\)$', '', t[4 + 2 * i]).lower() for i in range(wcnt)]
                synwords[(off, pos)] = words
                k = 4 + 2 * wcnt
                pcnt = int(t[k])
                for i in range(pcnt):
                    sym, toff, tpos, st = t[k + 1 + 4 * i: k + 5 + 4 * i]
                    if sym in ('+', '\\', '!') and st != '0000':
                        links.append(((off, pos), int(st[:2], 16), sym, (toff, POS[tpos]), int(st[2:], 16)))
    return synwords, links


def build_families(wn):
    synwords, links = _read(wn)
    lemmas = {}  # word -> set(pos)
    for (off, pos), ws in synwords.items():
        for w in ws:
            lemmas.setdefault(w, set()).add(pos)
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            parent[x] = parent.get(parent[x], parent[x])
            x = parent[x]
        return x

    def union(a, b):
        parent.setdefault(a, a)
        parent.setdefault(b, b)
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    antonyms = {}
    for s, si, sym, t, ti in links:
        try:
            a = (synwords[s][si - 1], s[1])
            b = (synwords[t][ti - 1], t[1])
        except (KeyError, IndexError):
            continue
        if '_' in a[0] or '_' in b[0] or not a[0].isalpha() or not b[0].isalpha():
            continue
        if sym == '!':
            antonyms.setdefault(a, set()).add(b)
            continue
        # Same family only when the words look alike (avoids die/death-like
        # semantic chains joining unrelated groups).
        if a[0][:3] != b[0][:3]:
            continue
        union(a, b)
    groups = {}
    for x in list(parent):
        groups.setdefault(find(x), set()).add(x)

    out = {}
    for members in groups.values():
        if len(members) < 2 or len(members) > 40:
            continue
        # Gerunds and comparatives add little ("deciding", "quicker").
        members = {m for m in members if not (
            (m[0].endswith('ing') and m[1] in ('n', 'a') and any(o[1] == 'v' for o in members))
            or (m[1] in ('a', 'r') and re.search(r'(er|est)$', m[0]) and any(m[0].startswith(o[0]) for o in members if o != m)))}
        if len(members) < 2:
            continue
        words = {w for w, _ in members}
        # root: shortest word, verb first on ties
        root = min(members, key=lambda m: (len(m[0]), {'v': 0, 'n': 1, 'a': 2, 'r': 3}[m[1]], m[0]))[0]
        mem = sorted(members, key=lambda m: ({'v': 0, 'n': 1, 'a': 2, 'r': 3}[m[1]], len(m[0]), m[0]))
        negs = []
        seen = set()
        for w, p in mem:
            if p not in ('a', 'n', 'r', 'v'):
                continue
            for pre in NEG_PREFIXES:
                if len(w) < (5 if pre in ('in', 'im', 'il', 'ir') else 4):
                    continue
                cand = pre + w
                if cand in lemmas and p in lemmas[cand] and cand not in words and cand not in seen:
                    negs.append((cand, p, w))
                    seen.add(cand)
            for ant, ap in antonyms.get((w, p), ()):
                if ant.endswith(w) and ant != w and ant not in words and ant not in seen:
                    negs.append((ant, ap, w))
                    seen.add(ant)
        group = (root, mem, negs)
        for w in words | {n for n, _, _ in negs}:
            if w not in out or len(mem) > len(out[w][1]):
                out[w] = group
    return out


if __name__ == '__main__':
    import sys
    fam = build_families(sys.argv[1])
    print(len(fam))
    for w in sys.argv[2:]:
        print(w, fam.get(w))

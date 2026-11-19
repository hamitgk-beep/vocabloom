"""Pilot: Turkish -> English meanings from open data only (no AI).

usage: python3 sample.py KAIKKI_TURKISH.jsonl FREQ_tr_50k.txt OUT_DIR [TATOEBA_PAIRS.tsv]

Sources: Kaikki (English Wiktionary, CC BY-SA 4.0), FrequencyWords tr_50k
(OpenSubtitles, CC BY-SA 4.0), Tatoeba tur-eng pairs (CC BY 2.0 FR).
Writes coverage.md (how many frequent words are covered) and sample.tsv
(the 300 most frequent lemmas with their English meanings and one example).
"""
import json, re, sys, os, collections

kaikki, freq_path, out = sys.argv[1:4]
pairs_path = sys.argv[4] if len(sys.argv) > 4 else None
os.makedirs(out, exist_ok=True)

lemmas = collections.defaultdict(list)   # word -> [(pos, [glosses])]
form_of = collections.defaultdict(set)    # form -> lemmas
for line in open(kaikki, encoding='utf-8'):
    e = json.loads(line)
    if e.get('lang_code') not in (None, 'tr'):
        continue
    w = e.get('word', '').strip()
    gl = []
    for s in e.get('senses', []):
        if s.get('form_of') or s.get('alt_of'):
            for f in (s.get('form_of') or []) + (s.get('alt_of') or []):
                if f.get('word'):
                    form_of[w.lower()].add(f['word'].lower())
            continue
        g = '; '.join(s.get('glosses', [])[-1:])
        if g:
            gl.append(g)
    if gl:
        lemmas[w.lower()].append((e.get('pos', ''), gl))
    for f in e.get('forms', []):
        t = f.get('form', '').strip().lower()
        if t and ' ' not in t and t != w.lower():
            form_of[t].add(w.lower())

freq = []
for line in open(freq_path, encoding='utf-8'):
    p = line.split()
    if p:
        freq.append(p[0].lower())

def resolve(t):
    if t in lemmas:
        return [t]
    return [l for l in form_of.get(t, ()) if l in lemmas]

cov = []
for n in (1000, 5000, 10000, 20000, 50000):
    top = freq[:n]
    direct = sum(1 for t in top if t in lemmas)
    viaform = sum(1 for t in top if t not in lemmas and resolve(t))
    cov.append((n, direct, viaform))

examples = collections.defaultdict(list)
if pairs_path and os.path.exists(pairs_path):
    for line in open(pairs_path, encoding='utf-8'):
        p = line.rstrip('\n').split('\t')
        if len(p) < 2:
            continue
        tr, en = p[0], p[1]
        if len(tr) > 70:
            continue
        for tok in set(re.findall(r"[a-zçğıöşüâîû]+", tr.lower())):
            for l in resolve(tok):
                if len(examples[l]) < 1:
                    examples[l].append((tr, en))

seen, rows = set(), []
for t in freq:
    for l in resolve(t):
        if l in seen:
            continue
        seen.add(l)
        senses = lemmas[l]
        mean = ' | '.join(f"{pos}: {'; '.join(g[:3])}" for pos, g in senses[:3])
        ex = examples.get(l, [('', '')])[0]
        rows.append((len(rows) + 1, l, t, mean, ex[0], ex[1]))
    if len(rows) >= 300:
        break

with open(os.path.join(out, 'sample.tsv'), 'w', encoding='utf-8') as f:
    f.write('rank\tlemma\tseen_as\tenglish_meanings\texample_tr\texample_en\n')
    for r in rows:
        f.write('\t'.join(str(x).replace('\t', ' ') for x in r) + '\n')

with open(os.path.join(out, 'coverage.md'), 'w', encoding='utf-8') as f:
    f.write(f'Kaikki Turkish lemmas with English glosses: {len(lemmas)}\n')
    f.write(f'Inflected forms mapped to a lemma: {len(form_of)}\n')
    f.write(f'Lemmas with a Tatoeba example: {len(examples)}\n\n')
    f.write('| top N frequent tokens | headword itself | only via inflected form | not covered |\n|---|---|---|---|\n')
    for n, d, v in cov:
        f.write(f'| {n} | {d} | {v} | {n - d - v} |\n')
    miss = [t for t in freq[:2000] if not resolve(t)][:80]
    f.write('\nNot covered among the top 2,000: ' + ', '.join(miss) + '\n')

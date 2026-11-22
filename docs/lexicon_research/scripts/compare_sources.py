"""Task 5A source comparison (read-only on both dictionaries; writes only to OUT_DIR).

usage: python3 -I compare_sources.py assets/dict.db assets/tr_en.db english-wordnet-2025.xml.gz MAGPIE_unfiltered.jsonl OUT_DIR

Needs wordfreq 3.1.1 (Apache-2.0 code, CC BY-SA 4.0 data) in the interpreter; the lists are used for
measuring only and nothing from them is written into the dictionaries.
Full scans are marked FULL, samples SAMPLE (fixed seed). Sample classification is done afterwards by
reading the sample files; it is not a human review.
"""
import collections, gzip, json, random, re, sqlite3, sys, xml.etree.ElementTree as ET

dict_p, tren_p, oewn_p, magpie_p, out = sys.argv[1:6]
from wordfreq import top_n_list, zipf_frequency

R = {}
rnd = random.Random(20261122)
db = sqlite3.connect(f'file:{dict_p}?mode=ro', uri=True)
tr = sqlite3.connect(f'file:{tren_p}?mode=ro', uri=True)

# ---------------------------------------------------------------- English side
wn30 = collections.defaultdict(set)  # lemma -> pos set (dict.db sense/syn = WordNet 3.0 + KeNet Turkish)
for lemma, pos in db.execute('SELECT x.lemma, s.pos FROM sense x JOIN syn s ON s.id = x.syn_id'):
    wn30[lemma].add('a' if pos == 's' else pos)
ft = {w: json.loads(t) for w, t in db.execute('SELECT word, tr FROM ft')}
POSMAP = {'isim': 'n', 'fiil': 'v', 'sıfat': 'a', 'zarf': 'r', 'noun': 'n', 'verb': 'v', 'adjective': 'a', 'adverb': 'r'}
own = {}
for w, s, st, rv in db.execute('SELECT word, senses, status, reviewed FROM own_word'):
    own[w] = (json.loads(s), st, rv)
own_pos = {w: {POSMAP.get((x.get('pos') or '').strip().lower(), '?') for x in v[0]} for w, v in own.items()}
exc = collections.defaultdict(set)
for f, l, p in db.execute('SELECT form, lemma, pos FROM exc'):
    exc[f].add(l)
known = set(wn30) | set(ft) | set(own)

# OEWN 2025
oe = collections.defaultdict(set)
oe_forms = {}
for ev, el in ET.iterparse(gzip.open(oewn_p), events=('end',)):
    if el.tag == 'LexicalEntry':
        lem = el.find('Lemma')
        w = lem.get('writtenForm')
        p = lem.get('partOfSpeech')
        oe[w.lower()].add('a' if p == 's' else p)
        for f in el.findall('Form'):
            oe_forms[f.get('writtenForm').lower()] = w.lower()
        el.clear()
R['oewn2025_lemmas'] = len(oe)
R['dictdb_wn30_lemmas'] = len(wn30)
new_in_oewn = sorted(w for w in oe if w not in wn30)
R['oewn2025_lemmas_not_in_dictdb_wordnet'] = len(new_in_oewn)
R['oewn2025_lemmas_not_anywhere_in_dictdb'] = sum(1 for w in new_in_oewn if w not in known)
gone = [w for w in wn30 if w not in oe]
R['dictdb_wordnet_lemmas_not_in_oewn2025'] = len(gone)


def base_known(w):
    if w in known:
        return True
    for l in exc.get(w, ()):
        if l in known:
            return True
    for suf, rep in (('ies', 'y'), ('es', ''), ('s', ''), ('ied', 'y'), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e'), ('er', ''), ('est', ''), ('ly', '')):
        if w.endswith(suf) and len(w) > len(suf) + 2:
            b = w[:-len(suf)] + rep
            if b in known or (len(b) > 2 and b[-1] == b[-2] and b[:-1] in known):
                return True
    return False


# Frequent English words missing (FULL over wordfreq top 30,000 alphabetic)
top = [w for w in top_n_list('en', 30000) if re.fullmatch(r"[a-z]+(?:-[a-z]+)?", w)]
miss = [w for w in top if not base_known(w)]
R['en_top_alpha'] = len(top)
R['en_top_missing_any_form'] = len(miss)
bands = collections.Counter()
for i, w in enumerate(top):
    if not base_known(w):
        bands[f'{(i // 5000 + 1) * 5}k'] += 1
R['en_missing_by_band'] = dict(sorted(bands.items(), key=lambda x: int(x[0][:-1])))
sample = rnd.sample(miss, min(80, len(miss)))
with open(f'{out}/en_missing_sample.tsv', 'w') as f:
    f.write('word\tzipf\tin_oewn2025\n')
    for w in sample:
        f.write(f'{w}\t{zipf_frequency(w, "en"):.2f}\t{int(w in oe or w in oe_forms)}\n')
R['en_missing_in_oewn2025'] = sum(1 for w in miss if w in oe or w in oe_forms)

# Missing parts of speech (FULL, top 10,000 lemmas known to both): OEWN has a POS the app has nowhere
top10 = [w for w in top[:12000] if w in oe and w in known]
pos_miss = []
for w in top10:
    have = wn30.get(w, set()) | own_pos.get(w, set())
    lack = (oe[w] - {'s'}) - have
    if lack and have:
        pos_miss.append((w, ''.join(sorted(lack)), ''.join(sorted(have))))
R['en_pos_checked'] = len(top10)
R['en_pos_missing_vs_oewn'] = len(pos_miss)
with open(f'{out}/en_pos_missing.tsv', 'w') as f:
    for x in pos_miss:
        f.write('\t'.join(x) + '\n')

# Phrasal verbs: OEWN verb entries "verb particle" vs expr phrasal_verbs (FULL)
PART = {'up', 'down', 'off', 'out', 'away', 'back', 'on', 'over', 'in', 'around', 'about', 'through', 'along', 'apart', 'aside', 'by', 'forward', 'together'}
expr = collections.defaultdict(set)
for p, c in db.execute('SELECT phrase, cat FROM expr'):
    expr[p].add(c)
own_expr = {p for (p,) in db.execute('SELECT phrase FROM own_expr')}
pv_oewn = [w for w, ps in oe.items() if 'v' in ps and len(w.split()) == 2 and w.split()[1] in PART]
pv_oewn_freq = [w for w in pv_oewn if zipf_frequency(w.split()[0], 'en') >= 4.0]
R['oewn_phrasal_verbs'] = len(pv_oewn)
R['oewn_phrasal_verbs_common_verb'] = len(pv_oewn_freq)
R['oewn_pv_missing_in_expr'] = sum(1 for w in pv_oewn if w not in expr)
R['oewn_pv_common_missing_in_expr'] = sum(1 for w in pv_oewn_freq if w not in expr)
with open(f'{out}/en_pv_missing_sample.tsv', 'w') as f:
    for w in rnd.sample([w for w in pv_oewn_freq if w not in expr], min(40, sum(1 for w in pv_oewn_freq if w not in expr))):
        f.write(w + '\n')

# Idioms: MAGPIE idiom types (agreement 1.0) in expr (FULL)
mi = set()
for line in open(magpie_p):
    j = json.loads(line)
    if j['confidence'] == 1.0:
        mi.add(j['idiom'])
R['magpie_idiom_types'] = len(mi)
R['magpie_in_expr'] = sum(1 for x in mi if x in expr)

# Examples (FULL)
n_syn, n_syn_ex = db.execute("SELECT count(*), sum(examples != '[]') FROM syn").fetchone()
R['wordnet_synsets'] = n_syn
R['wordnet_synsets_with_example'] = n_syn_ex
n_tr, n_tr_ex = db.execute("SELECT count(*), sum(extr IS NOT NULL AND extr != '[]') FROM syn WHERE examples != '[]'").fetchone()
R['wordnet_examples_with_turkish'] = (n_tr_ex, n_tr)
osz = sum(len(v[0]) for v in own.values())
R['own_word_senses'] = osz
R['own_word_senses_with_example'] = sum(1 for v in own.values() for s in v[0] if (s.get('ex') or s.get('en')))
R['own_word_rows'] = collections.Counter(f'{v[1]}/reviewed={v[2]}' for v in own.values())
R['expr_by_cat'] = {c: n for c, n in db.execute('SELECT cat, count(*) FROM expr GROUP BY cat')}
R['expr_without_turkish'] = db.execute("SELECT count(*) FROM expr WHERE tr IS NULL OR tr = ''").fetchone()[0]
R['expr_without_example'] = db.execute("SELECT count(*) FROM expr e WHERE (ex IS NULL OR ex = '') AND NOT EXISTS (SELECT 1 FROM exs x WHERE x.key = e.phrase || '|' || e.cat)").fetchone()[0]

# Duplicates (FULL)
dup_phr = {p: c for p, c in expr.items() if len(c) > 1}
R['expr_same_phrase_in_2plus_categories'] = len(dup_phr)
ft_dup = 0
for w, lst in ft.items():
    seen = collections.Counter(t.strip().lower() for x in lst for t in re.split('[,;]', x) if t.strip())
    if any(n > 1 for n in seen.values()):
        ft_dup += 1
R['ft_words_with_repeated_turkish'] = ft_dup
own_dup = 0
for w, v in own.items():
    seen = collections.Counter((s.get('pos'), (s.get('tr') or '').strip().lower()) for s in v[0])
    if any(n > 1 for n in seen.values()):
        own_dup += 1
R['own_words_with_duplicate_sense'] = own_dup

# Proper nouns (FULL): headwords that are first names / places, by EWT+wordfreq heuristics is weak;
# use the dictionary's own frequency table: top entries vs. OEWN proper-noun-only lemmas.
names = {'tom', 'mary', 'john', 'jack', 'mike', 'ken', 'bill', 'bob', 'jim', 'sam', 'tim', 'dan', 'joe', 'ann', 'kate', 'pat', 'sue', 'ted'}
wf_top = [w for w, n in db.execute('SELECT word, n FROM wfreq ORDER BY n DESC LIMIT 200')]
R['wfreq_top200_first_names'] = [w for w in wf_top if w in names]
R['first_names_with_wordnet_common_noun'] = sorted(w for w in names if 'n' in wn30.get(w, set()))

# English-Turkish conflicts (FULL): ft main list vs AI draft vs KeNet synset Turkish
def toks(s):
    return {t.strip().lower() for t in re.split('[,;/]', re.sub(r'\([^)]*\)', '', s)) if t.strip()}


kenet = collections.defaultdict(set)
for lemma, t in db.execute("SELECT x.lemma, s.tr FROM sense x JOIN syn s ON s.id = x.syn_id WHERE s.tr IS NOT NULL AND s.tr != '[]' AND x.rank < 3"):
    for v in json.loads(t):
        kenet[lemma] |= toks(v)
both = agree = 0
dis = []
for w, v in own.items():
    if w not in ft or v[1] != 'ai_draft_unreviewed':
        continue
    f1 = toks(ft[w][0]) if ft[w] else set()
    d1 = toks(v[0][0].get('tr', '')) if v[0] else set()
    if not f1 or not d1:
        continue
    both += 1
    if f1 & d1:
        agree += 1
    else:
        dis.append((w, ft[w][0], v[0][0].get('tr', '')))
R['first_meaning_ft_vs_ai_draft'] = {'compared': both, 'share_a_word': agree, 'no_common_word': len(dis)}
with open(f'{out}/en_conflict_sample.tsv', 'w') as f:
    f.write('word\tft_first\tai_draft_first\tkenet_top3\n')
    for w, a, b in rnd.sample(dis, min(60, len(dis))):
        f.write(f'{w}\t{a}\t{b}\t{", ".join(sorted(kenet.get(w, set()))[:6])}\n')
k_both = k_agree = 0
for w in ft:
    if w in kenet and ft[w]:
        k_both += 1
        if toks(' , '.join(ft[w][:3])) & kenet[w]:
            k_agree += 1
R['ft_top3_vs_kenet_top3_synsets'] = {'compared': k_both, 'share_a_word': k_agree}

# Possibly broken Turkish in ft (FULL): words unknown to the Turkish lexicon of tr_en.db
trforms = {f for (f,) in tr.execute('SELECT form FROM form')} | {w for (w,) in tr.execute('SELECT word FROM lemma')}
unk = collections.Counter()
tot = 0
unk_ex = collections.defaultdict(set)
for w, lst in ft.items():
    for x in lst:
        for t in re.findall(r"[a-zçğıöşüâîû]+", x.lower()):
            tot += 1
            if t not in trforms and len(t) > 2:
                unk[t] += 1
                unk_ex[t].add(w)
R['ft_turkish_tokens'] = tot
R['ft_tokens_unknown_to_tr_lexicon'] = sum(unk.values())
R['ft_unknown_token_types'] = len(unk)
with open(f'{out}/ft_unknown_tokens_sample.tsv', 'w') as f:
    f.write('token\tcount\theadwords\n')
    for t in rnd.sample(sorted(unk), min(80, len(unk))):
        f.write(f'{t}\t{unk[t]}\t{", ".join(sorted(unk_ex[t])[:4])}\n')
R['ft_bad_label_glued'] = sum(1 for lst in ft.values() for x in lst if re.search(r'[a-zçğıöşü]\([^)]*\)[a-zçğıöşü]', x.lower()))
R['ft_with_english_letters_qwx'] = sum(1 for lst in ft.values() for x in lst if re.search(r'\b\w*[qwx]\w*\b', x.lower()))

# ---------------------------------------------------------------- Turkish side
tlem = {w: json.loads(s) for w, s in tr.execute('SELECT word, senses FROM lemma')}
formmap = collections.defaultdict(set)
for f, l in tr.execute('SELECT form, lemma FROM form'):
    formmap[f].add(l)
ttop = [w for w in top_n_list('tr', 30000) if re.fullmatch(r"[a-zçğıöşüâîû]+", w)]
tmiss = [w for w in ttop if w not in tlem and w not in formmap]
R['tr_top_alpha'] = len(ttop)
R['tr_top_not_found_as_lemma_or_form'] = len(tmiss)
tb = collections.Counter()
for i, w in enumerate(ttop):
    if w not in tlem and w not in formmap:
        tb[f'{(i // 5000 + 1) * 5}k'] += 1
R['tr_missing_by_band'] = dict(sorted(tb.items(), key=lambda x: int(x[0][:-1])))
with open(f'{out}/tr_missing_sample.tsv', 'w') as f:
    f.write('word\tzipf\n')
    for w in rnd.sample(tmiss, min(80, len(tmiss))):
        f.write(f'{w}\t{zipf_frequency(w, "tr"):.2f}\n')
R['tr_lemmas'] = len(tlem)
R['tr_lemmas_with_example'] = tr.execute('SELECT count(DISTINCT lemma) FROM ex').fetchone()[0]
R['tr_forms_with_2plus_lemmas'] = sum(1 for v in formmap.values() if len(v) > 1)
R['tr_lemma_pos'] = collections.Counter(s.get('p') for v in tlem.values() for s in v).most_common(12)
R['tr_senses_marked_s'] = collections.Counter(s.get('s') for v in tlem.values() for s in v if s.get('s')).most_common(5)
tdup = 0
for w, v in tlem.items():
    gl = collections.Counter(g.strip().lower() for s in v for g in s.get('g', []))
    if any(n > 1 for n in gl.values()):
        tdup += 1
R['tr_lemmas_with_repeated_gloss'] = tdup
# proper nouns as Turkish headwords: capitalised in Wiktionary are lowered in the table; check common names
trnames = ['ahmet', 'mehmet', 'ayşe', 'fatma', 'ali', 'can', 'deniz', 'ankara', 'istanbul', 'türkiye', 'tom', 'john']
R['tr_names_as_headwords'] = {n: (n in tlem) for n in trnames}

with open(f'{out}/compare_results.json', 'w') as f:
    json.dump(R, f, ensure_ascii=False, indent=1, default=lambda x: dict(x) if isinstance(x, collections.Counter) else str(x))
print(json.dumps(R, ensure_ascii=False, indent=1, default=lambda x: dict(x) if isinstance(x, collections.Counter) else str(x)))

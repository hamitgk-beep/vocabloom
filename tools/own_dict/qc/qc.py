"""Offline quality check for our own dictionary output. No API calls.

usage: python3 tools/own_dict/qc/qc.py RESULTS.jsonl[.gz] OUT_DIR [--dict assets/dict.db]
Writes OUT_DIR/flags.tsv (one row per problem) and OUT_DIR/summary.json.
"""
import argparse, collections, gzip, json, os, re, sqlite3

# Only words that are not also Turkish words (on, at, in, is, by, one, it are Turkish words and are left out)
EN_STOP = set('the and or of to with for from are was were which that who someone something '
              'person thing into onto upon about over under these those their there they its'.split())
TR_CHARS = set('çğıöşüÇĞİÖŞÜ')
SUSPECT_NOTE = ('argo', 'aşağıla', 'küçümse', 'kaba', 'vulgar', 'cinsel')


def load(path):
    op = gzip.open if path.endswith('.gz') else open
    with op(path, 'rt', encoding='utf-8') as f:
        return [json.loads(l) for l in f]


def english_words(text):
    # ASCII-only words that are not Turkish-looking proper names; only English stopwords count
    return [w for w in re.findall(r"[^\W\d_]+", text.lower()) if w in EN_STOP]


def check(rec, out, dup_index):
    w, kind, senses = rec['w'], rec['kind'], rec['senses']
    flags = []

    def add(sev, cat, i, detail):
        flags.append((sev, cat, w, kind, i, detail))

    if not senses:
        add('high', 'empty_senses', -1, 'no meaning returned')
        return flags
    if len(senses) > 6:
        add('low', 'many_senses', -1, f'{len(senses)} senses, check the weak ones')
    seen_tr = set()
    for i, s in enumerate(senses):
        tr, en, ext = s.get('tr', '').strip(), s.get('en', '').strip(), s.get('ex_tr', '').strip()
        if not tr:
            add('high', 'empty_tr', i, 'Turkish meaning is empty')
        if not en or not ext:
            add('high', 'empty_example', i, 'example or its translation is empty')
        if english_words(tr):
            add('high', 'english_in_turkish', i, f'English words in Turkish: {english_words(tr)}')
        if english_words(ext):
            add('medium', 'english_in_example_tr', i, 'English words in Turkish example')
        if en and kind == 'word' and not rec.get('base'):
            # compare without spaces and hyphens, so "ab initio" or "bain-marie" match "abinitio" / "bainsmarie"
            norm = lambda x: re.sub(r'[\s\-\'.]', '', x.lower())
            stem = norm(w)[:max(4, len(norm(w)) - 3)]
            if stem not in norm(en):
                add('medium', 'example_missing_word', i, 'headword not found in English example')
        if tr:
            key = re.sub(r'\s+', ' ', tr.lower())
            if key in seen_tr:
                add('medium', 'duplicate_sense', i, f'same meaning repeated: {tr}')
            seen_tr.add(key)
            if re.search(r'\s{2,}|\s[,.;]|[,;]\s*$|\(\s*$|\(\)', tr) or tr.count('(') != tr.count(')'):
                add('low', 'format', i, f'odd spacing or brackets: {tr!r}')
            if re.search(r'[A-Za-z]', tr) and not english_words(tr) and kind == 'expr' and len(tr.split()) <= 2:
                add('low', 'literal_risk', i, f'short Turkish gloss for an expression, may be literal: {tr}')
        note = s.get('note', '').lower()
        if any(k in note for k in SUSPECT_NOTE):
            add('low', 'register', i, f'sensitive register, check wording: {s.get("note")}')
    if w.lower() in dup_index and len(dup_index[w.lower()]) > 1:
        add('medium', 'duplicate_headword', -1, f'headword appears {len(dup_index[w.lower()])} times')
    return flags


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('results')
    ap.add_argument('out')
    ap.add_argument('--dict', default='assets/dict.db')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    recs = load(a.results)
    dup = collections.defaultdict(list)
    for r in recs:
        dup[r['w'].lower()].append(r['kind'])
    flags = []
    for r in recs:
        flags += check(r, a.out, dup)
    with open(os.path.join(a.out, 'flags.tsv'), 'w', encoding='utf-8') as f:
        f.write('severity\tcategory\tw\tkind\tsense_index\tdetail\n')
        for fl in sorted(flags, key=lambda x: ({'high': 0, 'medium': 1, 'low': 2}[x[0]], x[1], x[2])):
            f.write('\t'.join(str(x) for x in fl) + '\n')
    cats = collections.Counter((fl[0], fl[1]) for fl in flags)
    words_flagged = {(fl[2], fl[3]) for fl in flags if fl[0] in ('high', 'medium')}
    summary = {
        'entries': len(recs),
        'entries_with_high_or_medium_flag': len(words_flagged),
        'flags_by_severity_and_category': {f'{s}/{c}': n for (s, c), n in sorted(cats.items())},
    }
    json.dump(summary, open(os.path.join(a.out, 'summary.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(json.dumps(summary, ensure_ascii=False, indent=1))


if __name__ == '__main__':
    main()

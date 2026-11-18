"""Classifies the gap words without any API call, using stems instead of exact matches.

A Turkish meaning is compared by its first five letters (Turkish suffixes change the end of a word).
Writes tools/own_dict/fix/classify_gap.tsv.gz and prints the counts.
"""
import gzip, json, re, collections, sys
import openpyxl
sys.path.insert(0, 'tools/own_dict/qc')
from qc import english_words

D = 'tools/own_dict/gap'


def stem(x):
    return re.sub(r'[^\w]+', '', x.lower())[:5]


def tokens(text):
    return [t.strip() for t in re.split(r'[;,|]', text or '') if t.strip()]


gap = [json.loads(l) for l in gzip.open(f'{D}/gap_entries.jsonl.gz', 'rt', encoding='utf-8')]
wb = openpyxl.load_workbook('/mnt/project-files/sozluk/vocabloom-sozluk-kaynaklari.xlsx', read_only=True)
dam = {r[0]: r[5] for r in wb['Kelimeler'].iter_rows(min_row=2, values_only=True) if r[0] and r[5] and r[2] != 'damdafayton'}

rows = []
cnt = collections.Counter()
for r in gap:
    w = r['w']
    old = tokens(dam.get(w, ''))
    new_st = {stem(t) for s in r['senses'] for t in tokens(s['tr'])}
    bad = (not r['senses']) or any(english_words(s['tr']) or not s['tr'].strip() or not s['ex_tr'].strip() for s in r['senses'])
    top3_ok = any(stem(t) in new_st for t in old[:3])
    any_ok = any(stem(t) in new_st for t in old)
    if bad:
        cat = 'supheli'
    elif not old:
        cat = 'uyumlu'
    elif top3_ok or (len(old) <= 2 and any_ok):
        cat = 'uyumlu'
    elif len(old) >= 3 and not any_ok:
        cat = 'onemli_anlam_kaybi_riski'
    else:
        cat = 'manuel_kontrol'
    cnt[cat] += 1
    rows.append((w, cat, '; '.join(old[:3]), '; '.join(s['tr'] for s in r['senses'])[:200],
                 ', '.join(t for t in old if stem(t) not in new_st)[:200]))

with gzip.open('tools/own_dict/fix/classify_gap.tsv.gz', 'wt', encoding='utf-8') as f:
    f.write('kelime\tkategori\tdamdafayton_ilk_uc\tyeni_anlam\tkaybolabilecek\n')
    for row in rows:
        f.write('\t'.join(row) + '\n')
print(json.dumps(dict(cnt), ensure_ascii=False))

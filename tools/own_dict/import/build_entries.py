"""Builds the import file for the app from the translation run's results.

usage: python3 tools/own_dict/import/build_entries.py RESULTS.jsonl.gz OUT.jsonl.gz

Keeps only entries that are safe to show in a Turkish interface:
  * no empty meaning, and no meaning equal to the headword
  * no English inside the Turkish text (english_in_turkish flag)
  * no copy-risk match with existing glosses (exact or near)
  * every sense has an English example translation and a gloss
Part-of-speech labels are mapped to Turkish, so no English label reaches the screen.
"""
import gzip, json, re, sys

POS_RULES = [  # checked in order on the lower-cased label
    ('phrasal', 'deyimsel fiil'), ('modal', 'fiil'), ('proper', 'özel isim'), ('özel', 'özel isim'),
    ('discourse', 'söylem belirteci'), ('marker', 'söylem belirteci'), ('proverb', 'atasözü'),
    ('interjection', 'ünlem'), ('conjunction', 'bağlaç'), ('preposition', 'edat'), ('pronoun', 'zamir'),
    ('numeral', 'sayı'), ('number', 'sayı'), ('determiner', 'belirleyici'), ('prefix', 'önek'),
    ('abbreviation', 'kısaltma'), ('adverb', 'zarf'), ('adjective', 'sıfat'), ('sıfat', 'sıfat'),
    ('verb', 'fiil'), ('fiil', 'fiil'), ('noun', 'isim'), ('isim', 'isim'),
    ('idiom', 'deyim'), ('expression', 'deyim'), ('phrase', 'deyim'), ('deyim', 'deyim'),
]


def pos_tr(label):
    s = (label or '').lower()
    for key, tr in POS_RULES:
        if key in s:
            return tr
    return 'diğer'


def main(src, out):
    rows = [json.loads(l) for l in gzip.open(src, 'rt', encoding='utf-8') if l.strip()]
    kept, dropped = [], {}

    def drop(why):
        dropped[why] = dropped.get(why, 0) + 1

    for r in rows:
        fl = {f[1] for f in r.get('flags', [])}
        senses = r.get('senses') or []
        if not senses:
            drop('empty'); continue
        if fl & {'copy_risk_exact_match', 'copy_risk_near_match'}:
            drop('copy_risk'); continue
        if 'english_in_turkish' in fl:
            drop('english_in_turkish'); continue
        if any(not s.get('tr', '').strip() or s.get('tr', '').strip().lower() == r['w'].lower() for s in senses):
            drop('empty_or_same_tr'); continue
        if any(not s.get('en', '').strip() or not s.get('ex_tr', '').strip() for s in senses):
            drop('missing_en_or_example'); continue
        for s in senses:
            s['pos'] = pos_tr(s.get('pos', ''))
        kept.append({'w': r['w'], 'kind': r['kind'], 'senses': senses, 'status': 'ai_draft_unreviewed',
                     'source': 'ai_generated', 'provider': r.get('provider', ''),
                     'reviewed_by_ai': True, 'reviewed_by_human': False})
    with gzip.open(out, 'wt', encoding='utf-8') as f:
        for r in kept:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    print(json.dumps({'kept': len(kept), 'dropped': dropped}, ensure_ascii=False))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

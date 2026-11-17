"""Extract English multiword expressions from a Wiktextract (kaikki.org) dump.

Reads JSON lines on stdin (kaikki.org-dictionary-English.jsonl) and writes a
compact JSON list to argv[1]:
  [{"p": phrase, "c": category, "en": [glosses], "tr": [turkish], "ex": example}, ...]

Wiktionary content is CC BY-SA 4.0 / GFDL.
"""
import gzip
import json
import re
import sys

SKIP_TAGS = {'obsolete', 'archaic', 'rare', 'dated', 'historical', 'nonstandard',
             'dialectal', 'misspelling', 'vulgar', 'offensive', 'derogatory', 'ethnic', 'slur'}
PHRASE_RE = re.compile(r"[a-z][a-z' -]*[a-z]")

CAT_MAP = [
    # (category-name substring, our category)
    ('English proverbs', 'proverbs'),
    ('English phrasal verbs', 'phrasal_verbs'),
    ('English coordinated pairs', 'binomials'),
    ('English binomials', 'binomials'),
    ('English prepositional phrases', 'prepositional_phrases'),
    ('English collocations', 'collocations'),
    ('English discourse markers', 'discourse_markers'),
    ('English filler words', 'discourse_markers'),
    ('English modal verbs', 'modal_verbs'),
    ('English idioms', 'idioms'),
    ('English similes', 'idioms'),
    ('English sayings', 'proverbs'),
    ('English conjunctions', 'conjunctions'),
]


def cat_names(obj):
    out = []
    for c in obj.get('categories', []) or []:
        out.append(c['name'] if isinstance(c, dict) else str(c))
    return out


def classify(e, senses):
    pos = e.get('pos', '')
    names = cat_names(e)
    for s in senses:
        names += cat_names(s)
    tags = {t for s in senses for t in s.get('tags', [])}
    if pos == 'proverb':
        return 'proverbs'
    for sub, cat in CAT_MAP:
        if any(n == sub or n.startswith(sub + ' ') for n in names):
            return cat
    if pos == 'conj':
        return 'conjunctions'
    if pos == 'prep_phrase':
        return 'prepositional_phrases'
    if pos == 'verb' and ' ' in e['word'] and len(e['word'].split()) == 2:
        last = e['word'].split()[1]
        if last in PARTICLES:
            return 'phrasal_verbs'
    if 'idiomatic' in tags and ' ' in e['word']:
        return 'idioms'
    return None


PARTICLES = {'up', 'down', 'in', 'out', 'on', 'off', 'over', 'away', 'back', 'about', 'around',
             'through', 'along', 'across', 'by', 'forward', 'apart', 'aside', 'together', 'into', 'after'}


def main():
    out = {}
    src = sys.stdin.buffer
    n = 0
    for line in src:
        n += 1
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get('lang_code', 'en') != 'en':
            continue
        w = (e.get('word') or '').strip()
        lw = w.lower().replace('’', "'")
        pos = e.get('pos', '')
        if not PHRASE_RE.fullmatch(lw):
            continue
        multi = ' ' in lw
        if not multi and pos != 'conj':
            continue
        if len(lw.split()) > 9:
            continue
        senses = [s for s in e.get('senses', [])
                  if s.get('glosses') and not (set(s.get('tags', [])) & SKIP_TAGS)
                  and 'form-of' not in s.get('tags', []) and 'alt-of' not in s.get('tags', [])]
        if not senses:
            continue
        cat = classify(e, senses)
        if not cat:
            continue
        glosses = []
        ex = None
        for s in senses[:4]:
            g = s['glosses'][-1].strip()
            if g and g not in glosses:
                glosses.append(g[:300])
            if ex is None:
                for x in s.get('examples', []) or []:
                    t = (x.get('text') or '').strip()
                    if 15 < len(t) < 220:
                        ex = t
                        break
        tr = []
        # Translation tables sit on the entry in older dumps and on each sense
        # in newer ones; the language is "code" or "lang_code".
        tables = list(e.get('translations', []) or [])
        for s in e.get('senses', []) or []:
            tables += s.get('translations', []) or []
        for t in tables:
            if t.get('code') == 'tr' or t.get('lang_code') == 'tr' or t.get('lang') in ('Turkish', 'Türkçe'):
                v = (t.get('word') or '').strip()
                if v and v not in tr:
                    tr.append(v)
        key = (lw, cat)
        prev = out.get(key)
        if prev:
            prev['en'] = (prev['en'] + [g for g in glosses if g not in prev['en']])[:4]
            prev['tr'] = (prev['tr'] + [t for t in tr if t not in prev['tr']])[:6]
            prev['ex'] = prev['ex'] or ex
        else:
            out[key] = {'p': lw, 'c': cat, 'en': glosses, 'tr': tr[:6], 'ex': ex}
    if len(sys.argv) > 2:
        add_tr_wiktionary(out, sys.argv[2])
    rows = sorted(out.values(), key=lambda r: (r['c'], r['p']))
    counts = {}
    for r in rows:
        counts[r['c']] = counts.get(r['c'], 0) + 1
    print('lines', n, 'kept', len(rows), counts, file=sys.stderr)
    with_tr = [r for r in rows if r['tr']]
    print('with turkish', len(with_tr), {c: sum(1 for r in with_tr if r['c'] == c) for c in counts}, file=sys.stderr)
    for r in with_tr[::max(1, len(with_tr) // 40)]:
        print('  sample', r['c'], '|', r['p'], '|', ', '.join(r['tr'][:4]), file=sys.stderr)
    with gzip.open(sys.argv[1], 'wt', encoding='utf-8') as f:
        json.dump(rows, f, ensure_ascii=False, separators=(',', ':'))


TR_POS = {'phrase': 'idioms', 'idiom': 'idioms', 'proverb': 'proverbs', 'prep_phrase': 'prepositional_phrases'}


def tr_terms(gloss):
    """Short Turkish meanings from one Turkish Wiktionary gloss; long
    explanations are left out."""
    g = re.sub(r'\([^)]*\)', '', gloss).strip(' .;')
    terms = [x.strip(' .') for x in re.split(r'[,;]', g) if x.strip(' .')]
    return [x for x in terms if len(x) <= 40 and len(x.split()) <= 5]


def add_tr_wiktionary(out, path):
    """English expressions in the Turkish Wiktionary (kaikki.org trwiktionary
    dump): their Turkish definitions fill in [out]'s Turkish, and phrases no
    other entry has are added when their kind is clear."""
    by_phrase = {}
    for (p, c), r in out.items():
        by_phrase.setdefault(p, []).append(r)
    opener = gzip.open if path.endswith('.gz') else open
    seen = filled = added = 0
    with opener(path, 'rt', encoding='utf-8') as f:
        for line in f:
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get('lang_code') != 'en':
                continue
            lw = (e.get('word') or '').strip().lower().replace('’', "'")
            if ' ' not in lw or not PHRASE_RE.fullmatch(lw) or len(lw.split()) > 9:
                continue
            seen += 1
            tr = []
            for s in e.get('senses', []) or []:
                for g in s.get('glosses', []) or []:
                    tr += [t for t in tr_terms(g) if t not in tr]
            if not tr:
                continue
            if lw in by_phrase:
                for r in by_phrase[lw]:
                    if not r['tr']:
                        filled += 1
                    r['tr'] = (r['tr'] + [t for t in tr if t not in r['tr']])[:6]
                continue
            pos = e.get('pos', '')
            toks = lw.split()
            cat = TR_POS.get(pos)
            if pos == 'verb' and len(toks) == 2 and toks[1] in PARTICLES:
                cat = 'phrasal_verbs'
            if not cat:
                continue
            r = {'p': lw, 'c': cat, 'en': [], 'tr': tr[:6], 'ex': None}
            out[(lw, cat)] = r
            by_phrase[lw] = [r]
            added += 1
    print('tr wiktionary: english expressions', seen, 'turkish filled', filled, 'added', added, file=sys.stderr)


if __name__ == '__main__':
    main()

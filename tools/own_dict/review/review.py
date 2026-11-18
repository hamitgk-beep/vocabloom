"""Step 1-4 and 6-7 of the review, without an API call except for the queue it writes.

Reads  tools/own_dict/dictionary/entries.jsonl.gz (never changed)
Writes tools/own_dict/review/*  (all new files; the originals stay as they were)

  entries_reviewed.jsonl.gz  records after local fixes (english tokens removed, same-POS duplicates dropped,
                             typo headwords kept with original_w and corrected_w)
  change_log.jsonl           every local change with the before and after values
  api_queue.json             the few headwords that still need a new translation (one API run, after approval)
  register_review.tsv        926 sensitive-register entries for a person to decide on
  compare_report.tsv.gz      new meaning vs the meaning the app shows today, with lost meanings and a category
  coverage.json              coverage against the 42,154 word / 16,098 expression target
"""
import collections, gzip, json, os, re, sqlite3, sys

sys.path.insert(0, 'tools/own_dict/qc')
from qc import english_words, check  # noqa: E402

D = 'tools/own_dict/review'
os.makedirs(D, exist_ok=True)
R = [json.loads(l) for l in gzip.open('tools/own_dict/dictionary/entries.jsonl.gz', 'rt', encoding='utf-8')]
db = sqlite3.connect('assets/dict.db')

# ---------- existing app meanings
ft = {}
for w, t in db.execute('select word, tr from ft'):
    try:
        ft[w.lower()] = json.loads(t)
    except Exception:
        ft[w.lower()] = [t]
expr_now = collections.defaultdict(list)
for p, t in db.execute('select phrase, tr from expr'):
    expr_now[p.lower()].append(t)


def norm(x):
    return re.sub(r'\s+', ' ', x.strip().lower())


def tokens(text):
    out = []
    for part in re.split(r'[;,|]', text or ''):
        p = norm(part)
        if p and p not in ('(', ')'):
            out.append(p)
    return out


changes = []
TYPO = {"monar'chical": 'monarchical', 'nonagression': 'nonaggression'}
HAND_API = {'beeston with bittering', 'drum and bass', 'elephant and castle', 'flasby with winterburn',
            'hen and chicken islands', 'square and compass', 'hit-and-run'}
LOCAL_OK = {'ah', 'phew', 'bah', 'oof', 'pah', 'alack and alas', 'for crying out loud', 'shoot the gold', 'ovarian'}

out = []
for r in R:
    w, kind = r['w'], r['kind']
    lw = w.lower()
    rec = dict(r)
    rec['senses'] = [dict(s) for s in r['senses']]
    rec['qc_before'] = []
    if kind == 'word' and lw in TYPO:
        rec['original_w'] = w
        rec['corrected_w'] = TYPO[lw]
        changes.append({'w': w, 'kind': kind, 'change': 'typo_headword', 'before': w, 'after': TYPO[lw]})
    if not rec['senses']:
        out.append(rec)
        continue
    # local fix: English words removed from Turkish, only for the simple interjection/idiom cases
    if lw in LOCAL_OK:
        for s in rec['senses']:
            if english_words(s['tr']):
                before = s['tr']
                keep = [t.strip() for t in s['tr'].split(',') if t.strip() and not english_words(t)]
                s['tr'] = ', '.join(keep)
                changes.append({'w': w, 'kind': kind, 'change': 'english_token_removed', 'before': before,
                                'after': s['tr']})
    # same POS and same Turkish meaning: keep the first, drop the rest (different POS kept)
    seen = set()
    kept = []
    for s in rec['senses']:
        key = (s['pos'], norm(s['tr']))
        if key in seen and s['tr'].strip():
            changes.append({'w': w, 'kind': kind, 'change': 'duplicate_sense_removed', 'before': s['tr'],
                            'after': ''})
            continue
        seen.add(key)
        kept.append(s)
    rec['senses'] = kept
    out.append(rec)

# API queue: typo headwords, the hand-picked proper-name cases, and headwords with an empty meaning or example
src = {it['w']: it for it in json.load(open('tools/own_dict/full_items.json', encoding='utf-8'))}
api = []
for rec in out:
    w, kind = rec['w'], rec['kind']
    lw = w.lower()
    if rec.get('corrected_w'):
        target = rec['corrected_w']
    elif lw in HAND_API:
        target = w
    elif rec['senses'] and any(not (s.get('tr') or '').strip() or not (s.get('ex_tr') or '').strip()
                               or not (s.get('en') or '').strip() for s in rec['senses']):
        target = w
    else:
        continue
    item = {'k': kind, 'group': rec['group'], 'w': target}
    if kind == 'word':
        item['wn'] = ['%s: %s' % (p, g) for p, g in db.execute(
            'select s.pos,s.gloss from sense e join syn s on s.id=e.syn_id where e.lemma=? order by e.pos,e.rank limit 6', (target,))]
    else:
        item['en'] = (src.get(w, {}).get('en') or '')[:300]
    api.append(item)
    rec['api_pending'] = True
json.dump(api, open(f'{D}/api_queue.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

with gzip.open(f'{D}/entries_reviewed.jsonl.gz', 'wt', encoding='utf-8') as f:
    for rec in out:
        f.write(json.dumps(rec, ensure_ascii=False) + '\n')
with open(f'{D}/change_log.jsonl', 'w', encoding='utf-8') as f:
    for c in changes:
        f.write(json.dumps(c, ensure_ascii=False) + '\n')

# register list for a person to decide on
flags = [l.rstrip('\n').split('\t') for l in open('tools/own_dict/qc/full/flags.tsv', encoding='utf-8')][1:]
with open(f'{D}/register_review.tsv', 'w', encoding='utf-8') as f:
    f.write('kelime\ttür\tanlam\tnot\tmevcut_uygulama_anlamı\tkarar\n')
    by = {(r['w'], r['kind']): r for r in out}
    for fl in flags:
        if fl[1] != 'register':
            continue
        rec = by.get((fl[2], fl[3]))
        if not rec:
            continue
        s = rec['senses'][int(fl[4])] if rec['senses'] and int(fl[4]) < len(rec['senses']) else {}
        existing = ', '.join(ft.get(fl[2].lower(), [])) if fl[3] == 'word' else ''
        f.write('\t'.join([fl[2], fl[3], s.get('tr', ''), s.get('note', ''), existing[:200], '']) + '\n')

# compare with the app today (words only; expressions with Turkish are kept as they are)
cmp_rows = []
cats = collections.Counter()
flagged = collections.defaultdict(set)
for rec in out:
    for fl in check(rec, D, collections.defaultdict(list)):
        flagged[(rec['w'], rec['kind'])].add(fl[1] if fl[0] in ('high', 'medium') else '')
for rec in out:
    w, kind, lw = rec['w'], rec['kind'], rec['w'].lower()
    new_tr = '; '.join(s['tr'] for s in rec['senses'])
    if kind == 'word' and lw in ft:
        old = ft[lw]
        old_tokens = [t for part in old for t in tokens(part)]
        new_tokens = {t for s in rec['senses'] for t in tokens(s['tr'])}
        lost = [t for t in old_tokens if t not in new_tokens and not any(t in n or n in t for n in new_tokens)]
        bad = {c for c in flagged.get((w, kind), set()) if c}
        if not rec['senses']:
            cat = 'gecersiz_bekliyor'
        elif bad:
            cat = 'supheli'
        elif any(t in lost for t in old_tokens[:3]) and len(old_tokens) >= 3:
            cat = 'manuel_kontrol'  # one of the first three (most important) old meanings is missing now
        else:
            cat = 'guvenle_aktarilabilir'
        action = 'degistir_damdafayton' if rec.get('action', '') else ''
        cmp_rows.append((w, kind, cat, '; '.join(old)[:300], new_tr[:300], ', '.join(lost[:15])))
    elif kind == 'expr':
        if expr_now.get(lw) and any(t and t.strip() and 'Türkçesi yok' not in t for t in expr_now[lw]):
            cat = 'mevcut_korunur'
            cmp_rows.append((w, kind, cat, ' | '.join(str(t) for t in expr_now[lw] if t)[:300], new_tr[:300], ''))
        elif not rec['senses']:
            cat = 'gecersiz_bekliyor'
            cmp_rows.append((w, kind, cat, '', '', ''))
        else:
            cat = 'yeni_eklenecek'
            cmp_rows.append((w, kind, cat, '', new_tr[:300], ''))
    else:
        continue
    cats[(kind, cat)] += 1
with gzip.open(f'{D}/compare_report.tsv.gz', 'wt', encoding='utf-8') as f:
    f.write('kelime\ttür\tkategori\tmevcut_anlam\tyeni_anlam\tkaybolabilecek\n')
    for row in cmp_rows:
        f.write('\t'.join(str(x).replace('\t', ' ').replace('\n', ' ') for x in row) + '\n')

# coverage vs the target
dam_only = db.execute("select count(*) from ft").fetchone()[0]
coverage = {
    'target_words': 42154, 'target_expressions': 16098,
    'app_words_in_db': dam_only,
    'app_expressions_in_db_distinct': len(expr_now),
    'expressions_without_turkish_in_app': sum(1 for p, ts in expr_now.items() if not any(t and t.strip() and 'Türkçesi yok' not in t for t in ts)),
    'our_words_replacing_damdafayton': sum(1 for r in out if r['kind'] == 'word'),
    'our_expressions_new': sum(1 for r in out if r['kind'] == 'expr' and not any(t and t.strip() and 'Türkçesi yok' not in t for t in expr_now.get(r['w'].lower(), []))),
    'changes_local': collections.Counter(c['change'] for c in changes),
    'api_queue_items': len(api),
    'compare_categories': {f'{k}/{c}': n for (k, c), n in sorted(cats.items())},
}
json.dump(coverage, open(f'{D}/coverage.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1, default=dict)
print(json.dumps(coverage, ensure_ascii=False, indent=1, default=dict))

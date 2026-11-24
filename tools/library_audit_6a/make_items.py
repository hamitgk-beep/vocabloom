"""Task 6A: turn the engine's dump of the library sentences into audit items (AUDIT_SPEC.md) in batches.

usage: python3 -I tools/library_audit_6a/make_items.py DUMP.jsonl [DUMP2.jsonl ...] OUTDIR [--per N]

Writes OUTDIR/batch_XX.jsonl (one line per sentence with its items) and OUTDIR/index.jsonl (every item with what it
refers to, so the answers can be joined back). Standard library only.
"""
import hashlib, json, os, re, sys

MAX_CHOICES = 24
MAX_DEF = 110
# Words on which today's panel and the 5N engine show the same Turkish: only this share is checked (a measured
# sample); the rest keep the engine's answer and are not in the checked readings.
AGREE_SAMPLE = 0.12


def sampled(key):
    return int(hashlib.sha1(key.encode('utf-8')).hexdigest()[:8], 16) / 0xffffffff < AGREE_SAMPLE


def short(t):
    t = ' '.join(t.split())
    return t if len(t) <= MAX_DEF else t[:MAX_DEF - 1] + '…'


def pos_label(c):
    return {'n': 'noun', 'v': 'verb', 'a': 'adj', 's': 'adj', 'r': 'adv'}.get(c.get('pos') or '', c.get('pos') or '?')


def word_choices(w):
    out, seen = [], set()
    for c in w['all']:
        if c.get('literal') or not (c.get('en') or '').strip():
            continue
        k = (c.get('pos'), c['en'].strip().lower())
        if k in seen:
            continue
        seen.add(k)
        out.append(c)
        if len(out) >= MAX_CHOICES:
            break
    return out


def main(argv):
    per = 120
    if '--per' in argv:
        i = argv.index('--per')
        per = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    *dumps, outdir = argv
    os.makedirs(outdir, exist_ok=True)
    sents = []
    for p in dumps:
        with open(p, encoding='utf-8') as f:
            sents += [json.loads(l) for l in f if l.strip()]
    sents.sort(key=lambda x: (x['story'], x['text']))
    index, lines, q = [], [], 0
    skipped_agree = 0
    for k, s in enumerate(sents):
        sid = f's{k}'
        items = []
        # expressions: today's reader, the 5N units and the 5N rejected, once each
        exprs = {}
        for src, lst in (('reader', s['reader']), ('unit', s['units']), ('rejected', s['rejected'])):
            for e in lst:
                key = (e['phrase'], e['cat'], tuple(sorted(e['tokens'])))
                d = exprs.setdefault(key, {'phrase': e['phrase'], 'cat': e['cat'], 'eid': e['eid'], 'tokens': sorted(e['tokens']), 'src': {}})
                d['src'][src] = e
        toks = [w for w in s['words']]
        bytok = {w['i']: w['w'] for w in toks}
        for key, d in exprs.items():
            words = []
            prev = None
            for t in d['tokens']:
                if prev is not None and t != prev + 1:
                    words.append('…')
                words.append(bytok.get(t, '?'))
                prev = t
            rd = d['src'].get('reader')
            ch = []
            if rd:
                seen = set()
                for c in rd['choices']:
                    if c.get('literal') or not c.get('en') or not c.get('tr') or c['en'] in seen:
                        continue
                    seen.add(c['en'])
                    ch.append(c)
            q += 1
            item = {'q': f'e{q}', 'kind': 'expr', 'phrase': d['phrase'], 'cat': d['cat'], 'words': ' '.join(words)}
            if len(ch) >= 2:
                item['choices'] = [f'{i}. {pos_label(c)}: {short(c["en"])}' for i, c in enumerate(ch)]
            items.append(item)
            index.append({'q': item['q'], 'sid': sid, 'text': s['text'], 'kind': 'expr', 'phrase': d['phrase'], 'cat': d['cat'],
                          'eid': d['eid'], 'tokens': d['tokens'], 'choice_ids': [c['id'] for c in ch],
                          'reader': None if rd is None else {'literal': rd['literal'], 'tr': rd['tr'], 'best': rd['best']},
                          'unit5n': d['src'].get('unit'), 'rejected5n': d['src'].get('rejected')})
        # words with meanings to choose between
        for w in s['words']:
            if w['reason'] == 'grammar word':
                continue
            ch = word_choices(w)
            if not ch:
                continue
            if len(ch) == 1 and w['cur'] is not None and w.get('eng_tr') in (None, w['cur']):
                continue  # one meaning, shown: nothing to choose
            agree = w['cur'] is not None and w['cur'] == w.get('eng_tr')
            if agree and not sampled(f"{s['text']}|{w['i']}"):
                skipped_agree += 1
                continue
            q += 1
            item = {'q': f'w{q}', 'kind': 'word', 'word': w['w'], 'head': w['head'],
                    'choices': [f'{i}. {pos_label(c)}: {short(c["en"])}' for i, c in enumerate(ch)]}
            items.append(item)
            index.append({'q': item['q'], 'sid': sid, 'text': s['text'], 'kind': 'word', 'agree_sample': agree, 'i': w['i'], 'word': w['w'], 'head': w['head'],
                          'choice_ids': [c['id'] for c in ch], 'choice_tr': [c.get('tr') for c in ch],
                          'choice_flags': [[f for f in ('derived', 'unverified') if c.get(f)] for c in ch],
                          'cur': w['cur'], 'cur_id': w['cur_id'], 'conf': w['conf'], 'reason': w['reason'],
                          'eng_tr': w.get('eng_tr'), 'eng_en': w.get('eng_en'), 'in_expr': w.get('in_expr')})
        if items:
            lines.append({'sid': sid, 'text': s['text'], 'prev': s['prev'], 'next': s['next'], 'items': items})
    # batches of about [per] items, whole sentences
    b, cur, n = 0, [], 0
    def flush():
        nonlocal b, cur, n
        if cur:
            with open(os.path.join(outdir, f'batch_{b:03d}.jsonl'), 'w', encoding='utf-8') as f:
                for l in cur:
                    f.write(json.dumps(l, ensure_ascii=False) + '\n')
            b += 1
        cur, n = [], 0
    for l in lines:
        cur.append(l)
        n += len(l['items'])
        if n >= per:
            flush()
    flush()
    with open(os.path.join(outdir, 'index.jsonl'), 'w', encoding='utf-8') as f:
        for x in index:
            f.write(json.dumps(x, ensure_ascii=False) + '\n')
    ne = sum(1 for x in index if x['kind'] == 'expr')
    print(f'{len(sents)} sentences, {len(lines)} with items, {ne} expr items, {len(index) - ne} word items, {b} batches; {skipped_agree} agreeing words not checked')


if __name__ == '__main__':
    main(sys.argv[1:])

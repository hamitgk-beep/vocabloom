"""Task 6A: join the audit answers to the items and build the app's checked readings and the audit tables.

usage: python3 -I tools/library_audit_6a/build_overlay.py ITEMS_DIR ANSWERS_DIR OUT_ASSET.json.gz OUT_DIR

ITEMS_DIR: make_items.py's output (index.jsonl). ANSWERS_DIR: answer files *.jsonl ({"q", "unit", "pick", "why", ...}).
Writes OUT_ASSET (assets/library/verified_6a.json.gz, lib/nlp/verified_readings.dart) and in OUT_DIR:
  labels.jsonl  every item with its answer (training data for later rounds)
  stats.json    agreement of today's reader and of the 5N engine with the audit
  gaps.tsv      words where no dictionary meaning fits ("missing"), or the fitting one has no Turkish
Standard library only. Reads nothing else; writes only these files.
"""
import collections, glob, gzip, json, os, sys


def main(items_dir, answers_dir, out_asset, out_dir):
    idx = {}
    with open(os.path.join(items_dir, 'index.jsonl'), encoding='utf-8') as f:
        for l in f:
            x = json.loads(l)
            idx[x['q']] = x
    ans = {}
    for p in sorted(glob.glob(os.path.join(answers_dir, '*.jsonl'))):
        with open(p, encoding='utf-8') as f:
            for l in f:
                l = l.strip()
                if not l:
                    continue
                a = json.loads(l)
                if a.get('q') in idx:
                    ans[a['q']] = a
    os.makedirs(out_dir, exist_ok=True)
    s = collections.defaultdict(lambda: {'w': {}, 'e': {}, 'm': {}})
    st = collections.Counter()
    gaps = []
    labels = []
    for q, x in idx.items():
        a = ans.get(q)
        if a is None:
            st['unanswered'] += 1
            continue
        labels.append({**x, 'answer': a})
        text = x['text']
        if x['kind'] == 'expr':
            unit = bool(a.get('unit'))
            st['expr'] += 1
            st['expr_unit' if unit else 'expr_literal'] += 1
            rd = x['reader']
            if rd is not None:
                shown = not rd['literal']
                st['reader_expr'] += 1
                st['reader_expr_ok' if shown == unit else 'reader_expr_wrong'] += 1
                if shown and not unit:
                    st['reader_false_shown'] += 1
                if unit and not shown:
                    st['reader_missed'] += 1
                key = f"{x['phrase']}|{x['cat']}|{','.join(str(t) for t in x['tokens'])}"
                s[text]['e'][key] = 1 if unit else 0
                pick = a.get('pick')
                if unit and isinstance(pick, int) and 0 <= pick < len(x['choice_ids']):
                    s[text]['m'][key] = x['choice_ids'][pick]
                if unit and pick == -1:
                    st['expr_no_meaning_fits'] += 1
                    gaps.append((x['phrase'], x['cat'], 'expr_meaning_missing', '', '', text))
            else:
                st['expr_not_in_reader'] += 1
                if unit:
                    st['expr_not_in_reader_unit'] += 1
            eng = x['unit5n'] is not None
            st['eng_expr_ok' if eng == unit else 'eng_expr_wrong'] += 1
            if eng and not unit:
                st['eng_false_shown'] += 1
            if unit and not eng:
                st['eng_missed'] += 1
            continue
        st['word'] += 1
        pick = a.get('pick')
        ids = x['choice_ids']
        if isinstance(pick, int) and 0 <= pick < len(ids):
            pid = ids[pick]
            tr = x['choice_tr'][pick]
            st['word_fit'] += 1
            if tr is None:
                st['word_fit_no_turkish'] += 1
                gaps.append((x['head'], x['word'], 'no_turkish', pid, '', text))
            # today's panel: right when it shows the picked meaning's Turkish
            if x['cur'] is None:
                st['cur_none'] += 1
            elif x['cur_id'] == pid or (tr is not None and x['cur'] == tr):
                st['cur_ok'] += 1
            else:
                st['cur_wrong'] += 1
            if x['eng_tr'] is not None and tr is not None:
                st['eng_ok' if x['eng_tr'] == tr else 'eng_wrong'] += 1
            elif x['in_expr']:
                st['eng_in_expr'] += 1
            else:
                st['eng_none'] += 1
            if tr is None:
                # the fitting meaning has no Turkish: the engine's Turkish may still say the same thing ("okul"), so it
                # stays, but never as sure ('~')
                if x['cur'] is not None and x['conf'] == 'sure':
                    s[text]['w'][str(x['i'])] = '~'
            elif not (x['cur_id'] == pid and x['conf'] == 'sure'):
                s[text]['w'][str(x['i'])] = pid
        else:
            why = a.get('why') or 'other'
            st[f'word_none_{why}'] += 1
            if why == 'other' and ' ' in x['head'] and x['head'].split()[0] != x['word'].lower():
                st['word_wrong_phrasal_head'] += 1
            if why == 'other':
                gaps.append((x['head'], x['word'], 'engine_wrong_head', '', a.get('note') or '', text))
            if why == 'missing':
                gaps.append((x['head'], x['word'], 'missing', '', a.get('need') or '', text))
                if x['cur'] is not None:
                    st['cur_wrong'] += 1
                    s[text]['w'][str(x['i'])] = '-'
                else:
                    st['cur_none_ok'] += 1
    out = {'v': 1, 's': {k: {kk: vv for kk, vv in v.items() if vv} for k, v in sorted(s.items()) if any(v.values())}}
    with gzip.open(out_asset, 'wt', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
    with open(os.path.join(out_dir, 'labels.jsonl'), 'w', encoding='utf-8') as f:
        for l in labels:
            f.write(json.dumps(l, ensure_ascii=False) + '\n')
    with open(os.path.join(out_dir, 'gaps.tsv'), 'w', encoding='utf-8') as f:
        f.write('headword\tword_or_cat\tkind\tsense_id\tneeded_meaning_en_or_note\tsentence\n')
        for g in sorted(gaps):
            f.write('\t'.join(str(v).replace('\t', ' ') for v in g) + '\n')
    st['sentences_in_asset'] = len(out['s'])
    st['asset_word_entries'] = sum(len(v.get('w', {})) for v in out['s'].values())
    st['asset_expr_entries'] = sum(len(v.get('e', {})) for v in out['s'].values())
    with open(os.path.join(out_dir, 'stats.json'), 'w', encoding='utf-8') as f:
        json.dump(dict(sorted(st.items())), f, indent=1)
    print(json.dumps(dict(sorted(st.items())), indent=1))


if __name__ == '__main__':
    main(*sys.argv[1:5])

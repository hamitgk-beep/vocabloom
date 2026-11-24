"""Task 6A: carry answers given on one item set over to a rebuilt item set, and batch what is still unanswered.

usage: python3 -I tools/library_audit_6a/carry_answers.py OLD_ITEMS OLD_ANSWERS NEW_ITEMS NEW_ANSWERS TODO_DIR [--per N]

An answer carries over only when the item is the same: same sentence, same word place (or expression and words) and
the same meanings in the same order. Used once, after the meaning cache fix (the first dump had 232 of 113,462 words
read with another word's cached answer). Standard library only.
"""
import glob, json, os, sys


def key(x):
    if x['kind'] == 'expr':
        return (x['text'], 'expr', x['phrase'], x['cat'], tuple(x['tokens']), tuple(x['choice_ids']))
    return (x['text'], 'word', x['i'], x['head'], tuple(x['choice_ids']))


def main(old_items, old_ans, new_items, new_ans, todo, per=600):
    old = {}
    with open(os.path.join(old_items, 'index.jsonl'), encoding='utf-8') as f:
        for l in f:
            x = json.loads(l)
            old[x['q']] = x
    answers = {}
    for p in glob.glob(os.path.join(old_ans, '*.jsonl')):
        with open(p, encoding='utf-8') as f:
            for l in f:
                if l.strip():
                    a = json.loads(l)
                    if a.get('q') in old:
                        answers[key(old[a['q']])] = a
    os.makedirs(new_ans, exist_ok=True)
    os.makedirs(todo, exist_ok=True)
    carried, open_q = [], set()
    with open(os.path.join(new_items, 'index.jsonl'), encoding='utf-8') as f:
        for l in f:
            x = json.loads(l)
            a = answers.get(key(x))
            if a is None:
                open_q.add(x['q'])
            else:
                carried.append({**a, 'q': x['q']})
    with open(os.path.join(new_ans, 'carried.jsonl'), 'w', encoding='utf-8') as f:
        for a in carried:
            f.write(json.dumps(a, ensure_ascii=False) + '\n')
    lines = []
    for p in sorted(glob.glob(os.path.join(new_items, 'batch_*.jsonl'))):
        with open(p, encoding='utf-8') as f:
            for l in f:
                s = json.loads(l)
                items = [it for it in s['items'] if it['q'] in open_q]
                if items:
                    lines.append({**s, 'items': items})
    b, cur, n = 0, [], 0
    for s in lines + [None]:
        if s is not None:
            cur.append(s)
            n += len(s['items'])
        if cur and (s is None or n >= per):
            with open(os.path.join(todo, f'batch_{b:03d}.jsonl'), 'w', encoding='utf-8') as f:
                for x in cur:
                    f.write(json.dumps(x, ensure_ascii=False) + '\n')
            b, cur, n = b + 1, [], 0
    print(f'{len(carried)} answers carried, {len(open_q)} items open in {b} batches')


if __name__ == '__main__':
    a = sys.argv[1:]
    per = 600
    if '--per' in a:
        i = a.index('--per')
        per = int(a[i + 1])
        a = a[:i] + a[i + 2:]
    main(*a, per=per)

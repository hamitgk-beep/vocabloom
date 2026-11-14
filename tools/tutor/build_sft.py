#!/usr/bin/env python3
"""Builds the fine-tuning data for the VocaBloom tutor models.

Steps (see README.md):
  1. python3 tools/tutor/build_sft.py sentences 3000   # pick book-like sentences with human Turkish translations
  2. python3 tools/tutor/errors.py                      # learner texts with known corrections
  3. flutter test tools/tutor/export_prompts_test.dart  # prompts exactly as the app builds them
  4. python3 tools/tutor/teacher.py ...                 # answers for the explain and chat tasks (optional)
  5. python3 tools/tutor/build_sft.py build             # data/train.jsonl and data/eval.jsonl

Output lines are {"messages": [{"role": "system"|"user"|"assistant", "content": ...}], "task": ...},
the format Unsloth / TRL SFTTrainer read directly.
"""
import json
import os
import random
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(HERE, 'data')


def read_jsonl(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8') as f:
        return [json.loads(l) for l in f if l.strip()]


# Tatoeba has some adult, violent and religious-polemic sentences; a teaching
# app for all ages leaves them out.
BLOCK = re.compile(r'\b(sex\w*|clitoris|penis|vagina|porn\w*|nude|naked|rape\w*|kill\w*|murder\w*|suicide|drug|'
                   r'cocaine|heroin|gun|guns|shoot\w*|bomb\w*|terror\w*|nazi\w*|hitler|breast\w*|condom|fuck\w*|'
                   r'shit|bitch|whore|prostitut\w*|god|allah|jesus|bible|quran|koran|prophet|noah|satan|devil|drunk|'
                   r'beer|wine|vodka|whisky|cigarette\w*)\b', re.I)


def pick_sentences(n, seed=3):
    """Everyday and book-like sentences from Tatoeba (in the bundled dictionary),
    spread over lengths so short and long sentences are both learned."""
    db = sqlite3.connect(os.path.join(ROOT, 'assets', 'dict.db'))
    rows = db.execute('SELECT DISTINCT en, tr FROM exs WHERE length(en) BETWEEN 25 AND 160').fetchall()
    rnd = random.Random(seed)
    rnd.shuffle(rows)
    good = []
    seen = set()
    for en, tr in rows:
        if not tr or en in seen or '\t' in en or '\t' in tr or BLOCK.search(en):
            continue
        if not re.match(r'^[A-Z"\']', en) or not re.search(r'[.!?]["\']?$', en):
            continue
        if re.search(r'[A-Za-z]', tr) and not re.search(r'[çğıöşüÇĞİÖŞÜ]|[aeiou]', tr):
            continue
        seen.add(en)
        good.append((en, tr))
    # Balance by length: a third short, a third medium, a third long.
    short = [x for x in good if len(x[0]) < 50]
    mid = [x for x in good if 50 <= len(x[0]) < 90]
    long_ = [x for x in good if len(x[0]) >= 90]
    out = short[:n // 3] + mid[:n // 3] + long_[:n - 2 * (n // 3)]
    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, 'sentences.tsv'), 'w', encoding='utf-8') as f:
        for en, tr in out:
            f.write('%s\t%s\n' % (en, tr))
    print('sentences', len(out), '(short %d, medium %d, long %d available)' % (len(short), len(mid), len(long_)))


HEAD_EXPLAIN = ['**Çeviri:**', '**Yapı:**']
HEAD_CORRECT = ['**Doğru hâli:**', '**Hatalar:**']


def valid(task, answer):
    if not answer or len(answer) > 2500:
        return False
    if task == 'explain':
        return all(h in answer for h in HEAD_EXPLAIN)
    if task == 'correct':
        return all(h in answer for h in HEAD_CORRECT) or '**İngilizcesi:**' in answer
    return True


def build(eval_share=0.06, seed=11):
    prompts = {p['id']: p for p in read_jsonl(os.path.join(DATA, 'prompts.jsonl'))}
    answers = {}
    for name in ('gold_correct.jsonl', 'teacher.jsonl', 'seed_explain.jsonl', 'seed_correct.jsonl'):
        for a in read_jsonl(os.path.join(DATA, name)):
            answers[a['id']] = a['answer']
    rows = []
    skipped = 0
    for id_, p in prompts.items():
        if p['task'] in ('chat', 'grade'):
            continue
        a = answers.get(id_)
        if not valid(p['task'], a):
            skipped += 1
            continue
        rows.append({'task': p['task'], 'id': id_, 'messages': [
            {'role': 'system', 'content': p['system']},
            {'role': 'user', 'content': p['user']},
            {'role': 'assistant', 'content': a.strip()},
        ]})
    # Grammar practice feedback (teacher.py grade): user turns carry their own text.
    grade_sys = prompts.get('grade-system', {}).get('system')
    for g in read_jsonl(os.path.join(DATA, 'teacher_grade.jsonl')):
        if grade_sys and g.get('user') and g.get('answer'):
            rows.append({'task': 'grade', 'id': g['id'], 'messages': [
                {'role': 'system', 'content': grade_sys},
                {'role': 'user', 'content': g['user']},
                {'role': 'assistant', 'content': g['answer'].strip()},
            ]})
    # Conversations: the app's chat system prompt + multi-turn dialogs.
    chat_sys = {p['id'].split('-')[-1]: p['system'] for p in prompts.values() if p['task'] == 'chat'}
    for name in ('seed_chat.jsonl', 'teacher_chat.jsonl'):
        for c in read_jsonl(os.path.join(DATA, name)):
            sys_ = chat_sys.get(c.get('level', 'B1'))
            if not sys_ or len(c.get('turns', [])) < 2:
                continue
            msgs = [{'role': 'system', 'content': sys_}]
            for t in c['turns']:
                msgs.append({'role': 'assistant' if t['role'] in ('assistant', 'bloom') else 'user', 'content': t['text']})
            if msgs[1]['role'] == 'assistant':
                msgs.insert(1, {'role': 'user', 'content': 'Start the conversation with a short, friendly question.'})
            if msgs[-1]['role'] != 'assistant':
                msgs.pop()
            rows.append({'task': 'chat', 'id': c['id'], 'messages': msgs})
    rnd = random.Random(seed)
    rnd.shuffle(rows)
    n_eval = max(1, int(len(rows) * eval_share))
    with open(os.path.join(DATA, 'eval.jsonl'), 'w', encoding='utf-8') as f:
        for r in rows[:n_eval]:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    with open(os.path.join(DATA, 'train.jsonl'), 'w', encoding='utf-8') as f:
        for r in rows[n_eval:]:
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    by = {}
    for r in rows:
        by[r['task']] = by.get(r['task'], 0) + 1
    print('examples', len(rows), by, 'eval', n_eval, 'prompts without a valid answer', skipped)


if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] == 'sentences':
        pick_sentences(int(sys.argv[2]) if len(sys.argv) > 2 else 3000)
    elif len(sys.argv) >= 2 and sys.argv[1] == 'build':
        build()
    else:
        print(__doc__)

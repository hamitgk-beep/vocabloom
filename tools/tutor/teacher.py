#!/usr/bin/env python3
"""Writes model answers for the explain task and practice conversations with a
large "teacher" model, so the small phone models can learn from them.

Any OpenAI-compatible chat API works. Free options:
  * Google AI Studio (free tier):  TEACHER_URL=https://generativelanguage.googleapis.com/v1beta/openai
                                    TEACHER_MODEL=gemini-flash-latest   TEACHER_KEY=<AI Studio key>
  * Ollama on your own computer:    TEACHER_URL=http://localhost:11434/v1  TEACHER_MODEL=qwen3:32b
Paid APIs (Anthropic, OpenAI ...) work the same way but cost money.

    python3 tools/tutor/teacher.py explain [limit]   # -> data/teacher.jsonl (resumes)
    python3 tools/tutor/teacher.py chat [count]      # -> data/teacher_chat.jsonl (resumes)

The teacher gets the human Turkish translation of each sentence (Tatoeba) and
the app's dictionary facts, and must keep the exact answer format of the app.
"""
import json
import os
import random
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')

URL = os.environ.get('TEACHER_URL', 'http://localhost:11434/v1').rstrip('/')
KEY = os.environ.get('TEACHER_KEY', '')
MODEL = os.environ.get('TEACHER_MODEL', 'qwen3:32b')
DELAY = float(os.environ.get('TEACHER_DELAY', '4'))  # seconds between calls (free tiers limit requests per minute)

QUALITY = '''
Kalite kuralları (çok önemli):
- Türkçe yazımın kusursuz olsun: TDK yazım kuralları, doğru ekler, doğal cümle yapısı. Çeviri kokan ifadelerden kaçın.
- Dilbilgisi terimlerinin İngilizce adını ver, Türkçe karşılığını parantezde yaz: Present Perfect (yakın geçmiş).
- Verilen "İnsan çevirisi" doğruysa çeviri satırında onu esas al; hatalıysa düzelt.
- Sözlük analizi bir yapıyı gösteriyorsa ama yanlışsa (ör. "was" yardımcı fiil değil ana fiilse) doğrusunu söyle.
- Kısa ol: en fazla 120 kelime. Gereksiz giriş cümlesi yazma ("Tabii!", "Harika bir soru" gibi).
- Biçim tam olarak: **Çeviri:** … / **Yapı:** ve "- " maddeler / **Kalıplar:** (yoksa bu satırı yazma) / **İpucu:** …
'''

CHAT_TASK = '''Write a realistic practice conversation between a Turkish learner of English (level {level}) and
"Bloom", an English conversation partner, about: {topic}.
Rules for Bloom are given in the system prompt below; follow them exactly. The learner makes 2-3 typical
Turkish-speaker mistakes across the conversation (articles, tenses, prepositions, word order, false friends)
and once writes a sentence in Turkish. 8 to 12 turns, starting with Bloom.
Return only JSON: {{"turns": [{{"role": "bloom"|"learner", "text": "..."}}]}}

System prompt of Bloom:
"""{system}"""'''

TOPICS = [
    'weekend plans', 'a favourite book', 'ordering food in a restaurant', 'a job interview', 'travelling abroad',
    'family', 'hobbies', 'the weather', 'shopping for clothes', 'a doctor visit', 'school memories', 'films',
    'a day at work', 'cooking', 'sports', 'moving to a new city', 'asking for directions', 'holidays in Turkey',
    'technology and phones', 'learning a language', 'a birthday party', 'public transport', 'music', 'pets',
    'a problem with a neighbour', 'booking a hotel', 'healthy habits', 'the news', 'a childhood friend', 'dreams',
]


def call(system, user, temperature=0.4, json_mode=False):
    body = {'model': MODEL, 'temperature': temperature,
            'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': user}]}
    if json_mode:
        body['response_format'] = {'type': 'json_object'}
    req = urllib.request.Request(URL + '/chat/completions', data=json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json',
                                          **({'Authorization': 'Bearer ' + KEY} if KEY else {})})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                out = json.loads(r.read())['choices'][0]['message']['content']
            if '</think>' in out:
                out = out.split('</think>', 1)[1]
            return out.strip()
        except Exception as e:  # rate limits, timeouts
            wait = 20 * (attempt + 1)
            print('  retry in %ds: %s' % (wait, e))
            time.sleep(wait)
    return None


def done_ids(path):
    if not os.path.exists(path):
        return set()
    with open(path, encoding='utf-8') as f:
        return {json.loads(l)['id'] for l in f if l.strip()}


def explain(limit):
    human = {}
    with open(os.path.join(DATA, 'sentences.tsv'), encoding='utf-8') as f:
        for line in f:
            en, _, tr = line.rstrip('\n').partition('\t')
            human[en] = tr
    out_path = os.path.join(DATA, 'teacher.jsonl')
    done = done_ids(out_path)
    n = 0
    with open(os.path.join(DATA, 'prompts.jsonl'), encoding='utf-8') as f, open(out_path, 'a', encoding='utf-8') as out:
        for line in f:
            p = json.loads(line)
            if p['task'] != 'explain' or p['id'] in done:
                continue
            if n >= limit:
                break
            en = p['user'].split('Cümle: "', 1)[1].split('"\n', 1)[0]
            user = p['user'] + ('\n\nİnsan çevirisi: ' + human[en] if human.get(en) else '')
            ans = call(p['system'] + '\n' + QUALITY, user, temperature=0.3)
            if ans and '**Çeviri:**' in ans and '**Yapı:**' in ans:
                out.write(json.dumps({'id': p['id'], 'answer': ans}, ensure_ascii=False) + '\n')
                out.flush()
                n += 1
                print(n, en[:70])
            time.sleep(DELAY)


def chat(count):
    prompts = [json.loads(l) for l in open(os.path.join(DATA, 'prompts.jsonl'), encoding='utf-8')]
    systems = {p['id'].split('-')[-1]: p['system'] for p in prompts if p['task'] == 'chat'}
    out_path = os.path.join(DATA, 'teacher_chat.jsonl')
    done = done_ids(out_path)
    rnd = random.Random(5)
    with open(out_path, 'a', encoding='utf-8') as out:
        for i in range(count):
            id_ = 'tchat-%d' % i
            if id_ in done:
                continue
            level = rnd.choice(sorted(systems))
            topic = rnd.choice(TOPICS)
            txt = call('You write training data for an English tutoring app. Output JSON only.',
                       CHAT_TASK.format(level=level, topic=topic, system=systems[level]), temperature=0.8,
                       json_mode=True)
            try:
                turns = json.loads(txt)['turns']
                assert len(turns) >= 4
            except Exception:
                print('  skipped (bad JSON)')
                continue
            turns = [{'role': 'assistant' if t['role'] == 'bloom' else 'user', 'text': t['text']} for t in turns]
            out.write(json.dumps({'id': id_, 'level': level, 'topic': topic, 'turns': turns}, ensure_ascii=False) + '\n')
            out.flush()
            print(i, level, topic)
            time.sleep(DELAY)


if __name__ == '__main__':
    if len(sys.argv) >= 2 and sys.argv[1] == 'explain':
        explain(int(sys.argv[2]) if len(sys.argv) > 2 else 10 ** 9)
    elif len(sys.argv) >= 2 and sys.argv[1] == 'chat':
        chat(int(sys.argv[2]) if len(sys.argv) > 2 else 600)
    else:
        print(__doc__)

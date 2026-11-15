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
    python3 tools/tutor/teacher.py grade [count]     # -> data/teacher_grade.jsonl (resumes): grammar practice feedback
    python3 tools/tutor/teacher.py lessons [per_topic] [max_topics]
                                                     # -> tools/grammar/generated.jsonl: more translation sentences
                                                     #    per grammar topic, each checked by a second call

The teacher gets the human Turkish translation of each sentence (Tatoeba) and
the app's dictionary facts, and must keep the exact answer format of the app.
"""
import json
import os
import re
import random
import sys
import time
import urllib.error
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


FALLBACK = []


def next_model(reason):
    """Moves on to the next model in TEACHER_MODELS; False when none is left."""
    global MODEL, _failures
    if not FALLBACK:
        return False
    print('model %s stopped (%s), switching to %s' % (MODEL, reason[:120], FALLBACK[0]), flush=True)
    MODEL = FALLBACK.pop(0)
    _failures = 0
    return True


def pick_model():
    """With TEACHER_MODEL=auto: the models in TEACHER_MODELS that the key can
    use, in that order, else the newest general "flash" model."""
    global MODEL
    if MODEL != 'auto':
        return
    req = urllib.request.Request(URL + '/models', headers={**({'Authorization': 'Bearer ' + KEY} if KEY else {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        ids = [m['id'].split('/')[-1] for m in json.loads(r.read()).get('data', [])]
    good = [i for i in ids if 'flash' in i and not re.search(r'lite|image|tts|live|audio|thinking|exp|preview|embed|8b', i)]
    good = good or [i for i in ids if 'flash' in i and not re.search(r'image|tts|live|audio|embed', i)]
    def ver(i):
        m = re.search(r'(\d+(?:\.\d+)?)', i)
        return (float(m.group(1)) if m else 0, 'latest' in i)
    MODEL = max(good, key=ver) if good else ids[0]
    wanted = [m for m in os.environ.get('TEACHER_MODELS', '').split(',') if m.strip() in ids]
    if wanted:
        MODEL = wanted[0]
        FALLBACK.extend(wanted[1:])
    print('models:', ', '.join(sorted(ids))[:1500], flush=True)
    print('teacher model:', MODEL, flush=True)


class TeacherDown(Exception):
    """The API keeps failing (bad key, wrong model, daily quota used up)."""


_failures = 0


def call(system, user, temperature=0.4, json_mode=False):
    global _failures
    body = {'model': MODEL, 'temperature': temperature,
            'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': user}]}
    if json_mode:
        body['response_format'] = {'type': 'json_object'}
    req = urllib.request.Request(URL + '/chat/completions', data=json.dumps(body).encode(),
                                 headers={'Content-Type': 'application/json',
                                          **({'Authorization': 'Bearer ' + KEY} if KEY else {})})
    for attempt in range(8):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                out = json.loads(r.read())['choices'][0]['message']['content'] or ''
            if '</think>' in out:
                out = out.split('</think>', 1)[1]
            _failures = 0
            return out.strip()
        except urllib.error.HTTPError as e:
            full = ' '.join(e.read().decode('utf-8', 'replace').split())
            detail = full[:400]
            quota_ids = sorted(set(re.findall(r'"quotaId": "([^"]+)"', full)))
            print('  HTTP %d: %s %s' % (e.code, detail[:160], ' '.join(quota_ids)), flush=True)
            per_day = any('PerDay' in q for q in quota_ids) or 'per day' in full.lower()
            if e.code == 429 and not per_day:
                # Requests-per-minute limit: wait for the next minute.
                wait = 65
                m = re.search(r'retry in ([0-9.]+)s', full, re.I) or re.search(r'"retryDelay": "([0-9.]+)s"', full)
                if m:
                    wait = min(120, float(m.group(1)) + 3)
                time.sleep(wait)
                continue
            if e.code in (400, 401, 403, 404) or e.code == 429:
                if next_model('HTTP %d' % e.code):
                    body['model'] = MODEL
                    req.data = json.dumps(body).encode()
                    continue
                raise TeacherDown('HTTP %d: %s' % (e.code, detail))
            time.sleep(min(120, 30 * (attempt + 1)))
        except Exception as e:  # timeouts, network
            print('  retry: %s' % e, flush=True)
            time.sleep(min(90, 20 * (attempt + 1)))
    _failures += 1
    if _failures >= 5:
        if next_model('5 requests in a row failed'):
            return None
        raise TeacherDown('5 requests in a row failed')
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
    n = tried = 0
    with open(os.path.join(DATA, 'prompts.jsonl'), encoding='utf-8') as f, open(out_path, 'a', encoding='utf-8') as out:
        for line in f:
            p = json.loads(line)
            if p['task'] != 'explain' or p['id'] in done:
                continue
            if n >= limit or tried >= 2 * limit:
                break
            tried += 1
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


GRADE_TASK = """You write training data for the grammar-practice feature of an English app for Turkish speakers.
Topic: {title}. Rule: {rule}
Turkish sentence: "{tr}"
Correct English versions: {answers}

Write {n} different answers a Turkish learner (level {level}) might really type for this sentence: mostly with
typical Turkish-speaker mistakes (tense, articles, prepositions, word order, the topic's rule, missing words,
spelling), and one that is different from the correct versions but still fully correct and natural.
For each, write the tutor's feedback in Turkish, following the system prompt below exactly (same headings,
numbered corrections, encouraging first line, never invent mistakes, accept a correct alternative).
Return only JSON: {{"items": [{{"answer": "...", "feedback": "..."}}]}}

System prompt of the tutor:
\"\"\"{system}\"\"\"
"""


def grade_user(t, e, answer):
    """The user turn exactly as Tutor.checkTranslation builds it."""
    rule = e['note'] if e['note'] else ' / '.join(t['structure'])
    return ('Konu: %s (%s)\nKural: %s\nTürkçe: "%s"\nDoğru cevaplar:\n%s\nÖğrencinin cevabı: "%s"' % (
        t['title_tr'], t['title_en'], rule, e['tr'], '\n'.join('- "%s"' % a for a in e['answers']), answer.strip()))


def grade(count):
    root = os.path.dirname(os.path.dirname(HERE))
    topics = json.load(open(os.path.join(root, 'assets', 'grammar', 'lessons.json'), encoding='utf-8'))['topics']
    prompts = [json.loads(l) for l in open(os.path.join(DATA, 'prompts.jsonl'), encoding='utf-8')]
    system = next(p['system'] for p in prompts if p['id'] == 'grade-system')
    out_path = os.path.join(DATA, 'teacher_grade.jsonl')
    done = {i.rsplit('-a', 1)[0] for i in done_ids(out_path)}
    n = 0
    with open(out_path, 'a', encoding='utf-8') as out:
        for t in topics:
            for e in t['exercises']:
                if e['id'] in done or n >= count:
                    continue
                txt = call('You write training data for an English tutoring app. Output JSON only.',
                           GRADE_TASK.format(title=t['title_en'], rule=e['note'], tr=e['tr'], answers=json.dumps(e['answers']),
                                             n=4, level=t['level'], system=system), temperature=0.7, json_mode=True)
                try:
                    items = json.loads(txt)['items']
                except Exception:
                    print('  skipped (bad JSON)', e['id'])
                    continue
                for k, it in enumerate(items):
                    fb = it.get('feedback', '')
                    if not it.get('answer') or '**Doğru ve doğal kurulumlar:**' not in fb:
                        continue
                    out.write(json.dumps({'id': '%s-a%d' % (e['id'], k), 'exercise': e['id'], 'answer': fb,
                                          'user': grade_user(t, e, it['answer'])}, ensure_ascii=False) + '\n')
                out.flush()
                n += 1
                print(n, e['id'])
                time.sleep(DELAY)


LESSON_TASK = '''Grammar topic: {title} (CEFR {level}).
Rule summary (Turkish): {rule}
Sentence patterns: {structure}
Existing practice sentences (do not repeat or paraphrase them):
{existing}

Write {n} NEW, original practice sentences for Turkish learners at level {level}. Each one:
- a natural, everyday Turkish sentence (perfect Turkish spelling and suffixes) that can only be translated well
  with this topic's structure;
- 1 to 3 correct, natural English translations, the most common one first (British or American spelling);
- a one-line Turkish note on the rule the sentence practises.
Vary subjects, tenses of the context and everyday situations (work, school, family, travel, health, shopping).
Do not use content from any textbook. Return only JSON:
{{"items": [{{"tr": "...", "answers": ["...", "..."], "note": "..."}}]}}'''

CHECK_TASK = '''You check practice sentences for an English learning app. For each item, decide whether every English
answer is a correct, natural translation of the Turkish sentence and uses the topic "{title}". Fix small problems;
drop an answer that is wrong. Mark "ok": false if the Turkish is unnatural or the item does not practise the topic.
Return only JSON: {{"items": [{{"tr": "...", "answers": ["..."], "note": "...", "ok": true}}]}}

Items:
{items}'''


def lessons(per_topic, max_topics):
    root = os.path.dirname(os.path.dirname(HERE))
    topics = json.load(open(os.path.join(root, 'assets', 'grammar', 'lessons.json'), encoding='utf-8'))['topics']
    out_path = os.path.join(root, 'tools', 'grammar', 'generated.jsonl')
    have = {}
    if os.path.exists(out_path):
        for l in open(out_path, encoding='utf-8'):
            if l.strip():
                g = json.loads(l)
                have.setdefault(g['topic'], []).append(g)
    # Topics with the fewest sentences first.
    order = sorted(topics, key=lambda t: len(t['exercises']) + len(have.get(t['id'], [])))
    done = 0
    with open(out_path, 'a', encoding='utf-8') as out:
        for t in order:
            if done >= max_topics or t['category'] == 'mixed':
                continue
            existing = [e['tr'] for e in t['exercises']] + [g['tr'] for g in have.get(t['id'], [])]
            txt = call('You are an expert ELT author writing original material. Output JSON only.',
                       LESSON_TASK.format(title=t['title_en'], level=t['level'], rule=t['explanation'][:900],
                                          structure=' | '.join(t['structure']), existing='\n'.join('- ' + x for x in existing),
                                          n=per_topic), temperature=0.8, json_mode=True)
            time.sleep(DELAY)
            try:
                items = json.loads(txt)['items']
                checked = json.loads(call('You are a careful English and Turkish editor. Output JSON only.',
                                          CHECK_TASK.format(title=t['title_en'], items=json.dumps(items, ensure_ascii=False)),
                                          temperature=0.1, json_mode=True))['items']
            except Exception:
                print('  skipped (bad JSON)', t['id'])
                continue
            seen = {x.strip().lower() for x in existing}
            n = 0
            for it in checked:
                tr, ans = (it.get('tr') or '').strip(), [a.strip() for a in it.get('answers') or [] if a and a.strip()]
                if not it.get('ok') or not tr or not ans or tr.lower() in seen:
                    continue
                seen.add(tr.lower())
                out.write(json.dumps({'topic': t['id'], 'tr': tr, 'answers': ans[:3], 'note': (it.get('note') or '').strip()},
                                     ensure_ascii=False) + '\n')
                n += 1
            out.flush()
            done += 1
            print(done, t['id'], '+%d' % n)
            time.sleep(DELAY)


def main():
    pick_model()
    if len(sys.argv) >= 2 and sys.argv[1] == 'explain':
        explain(int(sys.argv[2]) if len(sys.argv) > 2 else 10 ** 9)
    elif len(sys.argv) >= 2 and sys.argv[1] == 'grade':
        grade(int(sys.argv[2]) if len(sys.argv) > 2 else 10 ** 9)
    elif len(sys.argv) >= 2 and sys.argv[1] == 'lessons':
        lessons(int(sys.argv[2]) if len(sys.argv) > 2 else 6, int(sys.argv[3]) if len(sys.argv) > 3 else 10 ** 9)
    elif len(sys.argv) >= 2 and sys.argv[1] == 'chat':
        chat(int(sys.argv[2]) if len(sys.argv) > 2 else 600)
    else:
        print(__doc__)


if __name__ == '__main__':
    try:
        main()
    except TeacherDown as e:
        print('Teacher API stopped:', e, flush=True)
        sys.exit(3)

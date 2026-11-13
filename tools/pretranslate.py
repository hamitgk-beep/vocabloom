"""Builds the built-in Turkish library of expressions, once, at build time.

For every expression in assets/dict.db (phrasal verbs, idioms, ...) it asks an
AI model for its common senses: an English and Turkish heading, a one-sentence
explanation in both languages and two example sentences with translations.
The result is shipped inside the app, so users never need an API key.

The work is resumable: results are appended to a gzip JSON-lines file and
already translated expressions are skipped, so the job can run a little every
day within a free quota.

usage: python3 tools/pretranslate.py assets/dict.db exd.jsonl.gz
       --provider gemini|claude [--model NAME] [--minutes 300] [--limit N]

Keys come from the environment: GEMINI_API_KEY or ANTHROPIC_API_KEY.
"""
import argparse
import gzip
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request

CHUNK = 6  # expressions per request

# Categories in the order they are translated: the ones readers meet most first.
CAT_ORDER = ['phrasal_verbs', 'conjunctions', 'discourse_markers', 'chunks', 'collocations', 'modal_verbs',
             'false_friends', 'prepositional_phrases', 'idioms', 'binomials', 'proverbs', 'irregular_verbs']

PROMPT = '''You are writing a learner's dictionary of English expressions for Turkish speakers.
For each expression below, list its common senses (1 to 4), the most common meaning first.
Include the everyday literal meaning when the expression is often used that way, even if the given
definition only lists a special sense (for example "disagree with" also means "not have the same opinion as").
Skip obsolete, archaic and vulgar senses.

For every sense give:
- "title_en": a short English heading
- "title_tr": a short natural Turkish heading (e.g. "Uzman veya yardım çağırmak")
- "explain_en": one English sentence on when it is used
- "explain_tr": the same sentence in natural Turkish
- "examples": 2 objects {"en": a natural English example sentence, "tr": its natural Turkish translation}

Also give "tr": the expression's main Turkish meaning in 1 to 4 words.

Answer with JSON only: {"items": [{"p": "<expression exactly as given>", "tr": "...", "senses": [...]}]}

Expressions:
'''

SCHEMA = {
    'type': 'object',
    'properties': {
        'items': {
            'type': 'array',
            'items': {
                'type': 'object',
                'properties': {
                    'p': {'type': 'string'},
                    'tr': {'type': 'string'},
                    'senses': {
                        'type': 'array',
                        'items': {
                            'type': 'object',
                            'properties': {
                                'title_en': {'type': 'string'},
                                'title_tr': {'type': 'string'},
                                'explain_en': {'type': 'string'},
                                'explain_tr': {'type': 'string'},
                                'examples': {
                                    'type': 'array',
                                    'items': {
                                        'type': 'object',
                                        'properties': {'en': {'type': 'string'}, 'tr': {'type': 'string'}},
                                        'required': ['en', 'tr'],
                                        'additionalProperties': False,
                                    },
                                },
                            },
                            'required': ['title_en', 'title_tr', 'explain_en', 'explain_tr', 'examples'],
                            'additionalProperties': False,
                        },
                    },
                },
                'required': ['p', 'tr', 'senses'],
                'additionalProperties': False,
            },
        },
    },
    'required': ['items'],
    'additionalProperties': False,
}


class QuotaExhausted(Exception):
    pass


def describe(e):
    p, cat, en, ex = e
    s = f'- "{p}" ({cat.replace("_", " ")})'
    if en:
        s += f'; dictionary definition: {en[:300]}'
    if ex:
        s += f'; example: {ex[:200]}'
    return s


def load_todo(dict_path, done):
    db = sqlite3.connect(dict_path)
    rows = db.execute('SELECT phrase, cat, en, ex FROM expr').fetchall()
    try:
        freq = {(p, c): n for p, c, n in db.execute('SELECT phrase, cat, n FROM exfreq')}
    except sqlite3.OperationalError:
        freq = {}
    db.close()
    order = {c: i for i, c in enumerate(CAT_ORDER)}
    # Expressions people actually use (frequent in Tatoeba sentences) first, then by category.
    rows.sort(key=lambda r: (-min(freq.get((r[0], r[1]), 0), 50), order.get(r[1], 99), r[2] is None,
                             len(r[0].split()), r[0]))
    return [r for r in rows if f'{r[0]}|{r[1]}' not in done]


def clean_item(it):
    senses = []
    for s in it.get('senses') or []:
        if not s.get('title_tr') or not s.get('explain_tr'):
            continue
        senses.append({
            'title_en': s.get('title_en', '').strip(),
            'title_tr': s['title_tr'].strip(),
            'explain_en': s.get('explain_en', '').strip(),
            'explain_tr': s['explain_tr'].strip(),
            'examples': [{'en': x['en'].strip(), 'tr': x['tr'].strip()}
                         for x in (s.get('examples') or []) if x.get('en') and x.get('tr')][:3],
        })
    return senses[:4]


# ---------------------------------------------------------------- Gemini (free tier)

_use_schema = [True]


def gemini_call(model, key, chunk):
    for attempt in range(4):
        cfg = {'responseMimeType': 'application/json', 'temperature': 0.3, 'maxOutputTokens': 16000}
        if _use_schema[0]:
            cfg['responseJsonSchema'] = SCHEMA
        body = {'contents': [{'parts': [{'text': PROMPT + '\n'.join(describe(e) for e in chunk)}]}],
                'generationConfig': cfg}
        req = urllib.request.Request(
            f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent',
            data=json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'x-goog-api-key': key})
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                data = json.load(r)
            text = data['candidates'][0]['content']['parts'][0]['text']
            return json.loads(text[text.index('{'):text.rindex('}') + 1])['items']
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors='replace')[:400]
            if e.code == 429 and ('PerDay' in msg or 'per day' in msg.lower() or 'quota' in msg.lower() and attempt >= 2):
                raise QuotaExhausted(msg)
            if e.code == 400 and _use_schema[0]:
                print('  structured output not accepted, continuing without it:', msg[:200])
                _use_schema[0] = False
                continue
            if e.code in (429, 500, 503, 529):
                time.sleep(15 * (attempt + 1))
                continue
            raise RuntimeError(f'Gemini {e.code}: {msg}')
        except (ValueError, KeyError, IndexError) as e:
            print('  bad answer, retrying:', e)
            time.sleep(5)
    return None  # this chunk failed; the caller splits it


def run_gemini(todo, out, model, deadline, limit):
    key = os.environ['GEMINI_API_KEY']
    models = [model] if model else ['gemini-flash-latest', 'gemini-flash-lite-latest']
    done = 0
    i = 0
    while i < len(todo) and time.time() < deadline and done < limit and models:
        chunk = todo[i:i + CHUNK]
        t0 = time.time()
        try:
            items = gemini_call(models[0], key, chunk)
            if items is None:
                # Retry one by one; an expression that still fails is skipped this run.
                items = []
                for e in chunk:
                    r = gemini_call(models[0], key, [e])
                    if r is None:
                        print('  skipped:', e[0])
                    else:
                        items += r
        except QuotaExhausted as e:
            print(f'daily quota of {models[0]} used up: {str(e)[:200]}')
            models.pop(0)
            continue
        done += save(out, chunk, items)
        i += CHUNK
        print(f'{done} done ({models[0]}), next: {todo[i][0] if i < len(todo) else "-"}', flush=True)
        time.sleep(max(0, 7 - (time.time() - t0)))  # stay under ~9 requests per minute
    return done


# ---------------------------------------------------------------- Claude (Message Batches, half price)

def run_claude(todo, out, model, deadline, limit):
    import anthropic
    from anthropic.types.message_create_params import MessageCreateParamsNonStreaming
    from anthropic.types.messages.batch_create_params import Request

    client = anthropic.Anthropic()
    todo = todo[:limit]
    chunks = {f'c{i}': todo[i:i + CHUNK] for i in range(0, len(todo), CHUNK)}
    if not chunks:
        return 0
    batch = client.messages.batches.create(requests=[
        Request(custom_id=cid, params=MessageCreateParamsNonStreaming(
            model=model,
            max_tokens=16000,
            output_config={'effort': 'low', 'format': {'type': 'json_schema', 'schema': SCHEMA}},
            messages=[{'role': 'user', 'content': PROMPT + '\n'.join(describe(e) for e in chunk)}],
        )) for cid, chunk in chunks.items()
    ])
    print('batch', batch.id, len(chunks), 'requests')
    while True:
        b = client.messages.batches.retrieve(batch.id)
        if b.processing_status == 'ended':
            break
        if time.time() > deadline:
            print('deadline reached; the batch keeps running and its results are lost for this run')
            return 0
        print('  processing', b.request_counts.processing, flush=True)
        time.sleep(60)
    done = 0
    usage_in = usage_out = 0
    for r in client.messages.batches.results(batch.id):
        if r.result.type != 'succeeded':
            print('  ', r.custom_id, r.result.type)
            continue
        msg = r.result.message
        usage_in += msg.usage.input_tokens
        usage_out += msg.usage.output_tokens
        if msg.stop_reason != 'end_turn':
            print('  ', r.custom_id, 'stopped:', msg.stop_reason)
            continue
        text = next((x.text for x in msg.content if x.type == 'text'), '')
        try:
            items = json.loads(text)['items']
        except (ValueError, KeyError):
            continue
        done += save(out, chunks[r.custom_id], items)
    print(f'tokens in {usage_in}, out {usage_out}')
    return done


# ----------------------------------------------------------------

def save(out, chunk, items):
    by_p = {}
    for it in items or []:
        if isinstance(it, dict) and it.get('p'):
            by_p[it['p'].strip().lower()] = it
    n = 0
    with gzip.open(out, 'at', encoding='utf-8') as f:
        for p, cat, _, _ in chunk:
            it = by_p.get(p.lower())
            if not it:
                continue
            senses = clean_item(it)
            if not senses:
                continue
            f.write(json.dumps({'p': p, 'c': cat, 'tr': (it.get('tr') or '').strip(), 's': senses},
                               ensure_ascii=False) + '\n')
            n += 1
    return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dict_db')
    ap.add_argument('out')
    ap.add_argument('--provider', choices=['gemini', 'claude'], default='gemini')
    ap.add_argument('--model', default='')
    ap.add_argument('--minutes', type=float, default=300)
    ap.add_argument('--limit', type=int, default=10 ** 9)
    a = ap.parse_args()

    done = set()
    if os.path.exists(a.out):
        with gzip.open(a.out, 'rt', encoding='utf-8') as f:
            for line in f:
                try:
                    j = json.loads(line)
                    done.add(f"{j['p']}|{j['c']}")
                except (ValueError, KeyError):
                    pass  # a line cut off by an interrupted run
    todo = load_todo(a.dict_db, done)
    print(f'{len(done)} already done, {len(todo)} to go')
    deadline = time.time() + a.minutes * 60
    if a.provider == 'gemini':
        n = run_gemini(todo, a.out, a.model, deadline, a.limit)
    else:
        n = run_claude(todo, a.out, a.model or 'claude-opus-5-5', deadline, a.limit)
    print(f'added {n}; total {len(done) + n}; remaining {len(todo) - n}')


if __name__ == '__main__':
    sys.exit(main())

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
import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.request
import zlib

CHUNK = 6  # expressions per request

# Categories in the order they are translated: the ones readers meet most first.
CAT_ORDER = ['phrasal_verbs', 'conjunctions', 'discourse_markers', 'chunks', 'collocations', 'modal_verbs',
             'false_friends', 'prepositional_phrases', 'idioms', 'binomials', 'proverbs', 'irregular_verbs']

PROMPT = '''You are writing a learner's dictionary of English expressions for Turkish speakers.
For each expression below, list its common senses (1 to 4), the most common meaning first.
The first sense must be the one people use most in everyday English. The given definition often lists only a
special or rare sense: do not follow it blindly. When the words are often used in their plain meaning, that
plain meaning is a sense and usually the first one (for example "walk down" first means walking along or down
a street or stairs, "yürüyerek inmek, boyunca yürümek", and only later the boxing sense; "disagree with" also
means "not have the same opinion as"). Never leave out a common sense. Skip obsolete, archaic and vulgar senses.

For every sense give:
- "title_en": a short English heading
- "title_tr": a short natural Turkish heading (e.g. "Uzman veya yardım çağırmak")
- "explain_en": 1 to 3 English sentences, the way a good teacher explains it to a learner: what it means,
  when and how it is used (formal or informal, spoken or written), the usual pattern
  (e.g. "look forward to + -ing", "put something off"), and how it differs from a similar expression when that helps
- "explain_tr": the same explanation in natural, clear Turkish (not a word-by-word translation)
- "examples": 2 objects {"en": a natural everyday English example sentence, "tr": its natural Turkish translation}

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


FAM_PROMPT = '''You are writing a learner's dictionary for Turkish speakers.
For each English root word below, give its word family: the common English words built from the same root,
including the root itself (at most 14, only real and reasonably common words). Known members are listed
as a hint; drop rare ones and add common ones that are missing.

For each root return: "root", "root_tr" (its main Turkish meaning, 1 to 4 words), and "entries"; for each entry:
- "word"
- "pos": verb, noun, adjective or adverb
- "tr": short natural Turkish meaning
- "affix": the prefix or suffix added to the root, like "-tion" or "un-", or "" for the root itself
- "note_tr": one short Turkish sentence on how the affix changes the meaning (e.g. "-er eki işi yapan kişiyi gösterir"), "" for the root
- "note_en": the same in English, "" for the root
- "negative": true for negative or opposite forms (unhappy, disagree)
- "example_en": one short, natural everyday English sentence using exactly this word
- "example_tr": its natural Turkish translation
Every entry must have a Turkish meaning ("tr"); never leave it empty.
A note explains the affix against the word it is really built on (differentiation: differentiate + -ion,
not differentiator + -ation).

Answer with JSON only: {"items": [{"root": ..., "root_tr": ..., "entries": [...]}]}

Roots:
'''

FAM_SCHEMA = {
    'type': 'object',
    'properties': {'items': {'type': 'array', 'items': {
        'type': 'object',
        'properties': {
            'root': {'type': 'string'}, 'root_tr': {'type': 'string'},
            'entries': {'type': 'array', 'items': {
                'type': 'object',
                'properties': {
                    'word': {'type': 'string'},
                    'pos': {'type': 'string', 'enum': ['verb', 'noun', 'adjective', 'adverb']},
                    'tr': {'type': 'string'}, 'affix': {'type': 'string'},
                    'note_tr': {'type': 'string'}, 'note_en': {'type': 'string'},
                    'negative': {'type': 'boolean'},
                    'example_en': {'type': 'string'}, 'example_tr': {'type': 'string'},
                },
                'required': ['word', 'pos', 'tr', 'affix', 'note_tr', 'note_en', 'negative', 'example_en', 'example_tr'],
                'additionalProperties': False,
            }},
        },
        'required': ['root', 'root_tr', 'entries'],
        'additionalProperties': False,
    }}},
    'required': ['items'],
    'additionalProperties': False,
}


GLOSS_PROMPT = '''You are translating a learner's dictionary of English expressions for Turkish speakers.
For each expression below (with its category and English definition), give:
- "tr": its natural Turkish meaning in 1 to 5 words, the way a Turkish dictionary would put it
  (an idiom gets its real meaning, not a word-by-word translation: "above board" -> "dürüst, açık, hilesiz")
- "def_tr": the English definition translated into natural, clear Turkish; keep the "; " between senses
- "ex_tr": the natural Turkish translation of the example sentence, or "" when there is no example

Answer with JSON only: {"items": [{"p": "<expression exactly as given>", "tr": "...", "def_tr": "...", "ex_tr": "..."}]}

Expressions:
'''

GLOSS_SCHEMA = {
    'type': 'object',
    'properties': {'items': {'type': 'array', 'items': {
        'type': 'object',
        'properties': {'p': {'type': 'string'}, 'tr': {'type': 'string'}, 'def_tr': {'type': 'string'},
                       'ex_tr': {'type': 'string'}},
        'required': ['p', 'tr', 'def_tr', 'ex_tr'],
        'additionalProperties': False,
    }}},
    'required': ['items'],
    'additionalProperties': False,
}


def describe_gloss(r):
    p, cat, en, ex, _ = r
    s = f'- "{p}" ({cat.replace("_", " ")}): {(en or "(no definition)")[:400]}'
    if ex:
        s += f' | example: {ex[:250]}'
    return s


def load_gloss_todo(dict_path, done):
    """Expressions without a full built-in entry: their definition and example get Turkish.
    The most common first; among equally common ones, those with no Turkish at all."""
    db = sqlite3.connect(dict_path)
    try:
        freq = {(p, c): n for p, c, n in db.execute('SELECT phrase, cat, n FROM exfreq')}
    except sqlite3.OperationalError:
        freq = {}
    rows = [r for r in db.execute("SELECT phrase, cat, en, ex, (tr IS NOT NULL AND tr != '') FROM expr "
                                  "WHERE en IS NOT NULL OR ex IS NOT NULL")
            if f'{r[0]}|{r[1]}' not in done]
    db.close()
    rows.sort(key=lambda r: (-min(freq.get((r[0], r[1]), 0), 50), r[4]))
    return rows


def save_gloss(out, chunk, items):
    by_p = {it['p'].strip().lower(): it for it in items or [] if isinstance(it, dict) and it.get('p')}
    n = 0
    with gzip.open(out, 'at', encoding='utf-8') as f:
        for p, cat, _, ex, _ in chunk:
            it = by_p.get(p.lower())
            if not it or not (it.get('tr') or '').strip():
                continue
            f.write(json.dumps({'p': p, 'c': cat, 'tr': it['tr'].strip(), 'd': (it.get('def_tr') or '').strip(),
                                'x': (it.get('ex_tr') or '').strip() if ex else ''}, ensure_ascii=False) + '\n')
            n += 1
    return n


WORD_PROMPT = '''You are a friendly English teacher writing a learner's dictionary for Turkish speakers.
For each English word below, explain it the way you would if a learner asked you
"explain this word in English and Turkish with all the details so I can learn it".

List its common senses (1 to 6), across parts of speech, the most common first. Skip obsolete, archaic,
very technical and vulgar senses. For every sense give:
- "pos": verb, noun, adjective, adverb, preposition, conjunction, pronoun, determiner or interjection
- "title_en": a short English heading
- "title_tr": the Turkish equivalents for this sense, 1 to 4, most common first (e.g. "yine de, gene de")
- "explain_en": 1 to 3 sentences: what it means, when and how it is used (formal or informal), the usual
  patterns and collocations ("depend on something", "make a decision"), and a common mistake or a
  difference from a similar word when that helps a Turkish learner
- "explain_tr": the same explanation in natural, clear Turkish (not a word-by-word translation)
- "examples": 2 objects {"en": a natural everyday English sentence using this sense, "tr": its natural Turkish translation}

Also give "tr": the word's main Turkish meanings in 1 to 5 words.

Answer with JSON only: {"items": [{"w": "<word exactly as given>", "tr": "...", "senses": [...]}]}

Words:
'''

_WSENSE = json.loads(json.dumps(SCHEMA['properties']['items']['items']['properties']['senses']['items']))
_WSENSE['properties']['pos'] = {'type': 'string'}
_WSENSE['required'] = ['pos'] + _WSENSE['required']
WORD_SCHEMA = {
    'type': 'object',
    'properties': {'items': {'type': 'array', 'items': {
        'type': 'object',
        'properties': {'w': {'type': 'string'}, 'tr': {'type': 'string'},
                       'senses': {'type': 'array', 'items': _WSENSE}},
        'required': ['w', 'tr', 'senses'],
        'additionalProperties': False,
    }}},
    'required': ['items'],
    'additionalProperties': False,
}


def describe_word(r):
    return f'- {r[0]}'  # WordNet's parts of speech miss prepositions and pronouns, so none are given


def _inflected_of(w, known):
    for suf, rep in (('ies', 'y'), ('es', ''), ('s', ''), ('ied', 'y'), ('ed', ''), ('ed', 'e'), ('d', ''),
                     ('ing', ''), ('ing', 'e'), ('er', ''), ('est', ''), ('ier', 'y'), ('iest', 'y')):
        if w.endswith(suf) and len(w) > len(suf) + 2:
            b = w[:-len(suf)] + rep
            if b in known or (len(b) > 2 and b[-1] == b[-2] and b[:-1] in known):
                return True
    return False


def load_word_todo(dict_path, done, min_freq=5, only_missing=False):
    """Dictionary words, the ones people meet most often (Tatoeba frequency) first.
    only_missing: just the words with no Turkish at all yet ("usually", "each")."""
    db = sqlite3.connect(dict_path)
    has_tr = set()
    if only_missing:
        has_tr = {w for (w,) in db.execute('SELECT word FROM ft')}
        has_tr |= {l for (l,) in db.execute("SELECT DISTINCT x.lemma FROM sense x JOIN syn s ON s.id = x.syn_id "
                                            "WHERE s.tr IS NOT NULL AND s.tr != '[]'")}
    try:
        freq = dict(db.execute('SELECT word, n FROM wfreq'))
    except sqlite3.OperationalError:
        freq = {}
    forms = {f for f, l in db.execute('SELECT form, lemma FROM exc') if f != l}  # "are" is a form of "be"
    poss = {}
    for lemma, pos in db.execute('SELECT DISTINCT lemma, pos FROM sense'):
        if only_missing and _inflected_of(lemma, has_tr):
            continue  # "needed", "days": the app shows the base word's Turkish
        if lemma in has_tr or lemma in forms or '_' in lemma or ' ' in lemma or lemma in _SKIP or lemma in done or freq.get(lemma, 0) < min_freq:
            continue
        poss.setdefault(lemma, set()).add('a' if pos == 's' else pos)
    if only_missing:  # names ("jackson", "york"): WordNet lists them capitalized
        for w in list(poss):
            words = [json.loads(r[0]) for r in db.execute(
                'SELECT s.words FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = ?', (w,))]
            if words and all(w not in ws and any(x.lower() == w for x in ws) for ws in words):
                del poss[w]
    db.close()
    return [(w, sorted(p)) for w, p in sorted(poss.items(), key=lambda x: -freq.get(x[0], 0))]


def save_word(out, chunk, items):
    by_w = {it['w'].strip().lower(): it for it in items or [] if isinstance(it, dict) and it.get('w')}
    n = 0
    with gzip.open(out, 'at', encoding='utf-8') as f:
        for w, _ in chunk:
            it = by_w.get(w.lower())
            if not it:
                continue
            senses = clean_item(it, limit=6)
            if not senses:
                continue
            f.write(json.dumps({'w': w, 'tr': (it.get('tr') or '').strip(), 's': senses}, ensure_ascii=False) + '\n')
            n += 1
    return n


SYN_PROMPT = '''You are writing a learner's dictionary for Turkish speakers.
Each item below is one meaning (WordNet sense) of an English word: its id, the word and its synonyms,
the part of speech, the English definition and maybe example sentences.

For each item return:
- "id": the same id
- "tr": 1 to 4 short natural Turkish equivalents of the word in exactly this meaning, most common first
  (e.g. for "though" as an adverb meaning "however": ["yine de", "gene de", "bununla birlikte"])
- "examples_tr": natural Turkish translations of the given example sentences, same order ([] if none)

Answer with JSON only: {"items": [{"id": ..., "tr": [...], "examples_tr": [...]}]}

Meanings:
'''

SYN_SCHEMA = {
    'type': 'object',
    'properties': {'items': {'type': 'array', 'items': {
        'type': 'object',
        'properties': {
            'id': {'type': 'integer'},
            'tr': {'type': 'array', 'items': {'type': 'string'}},
            'examples_tr': {'type': 'array', 'items': {'type': 'string'}},
        },
        'required': ['id', 'tr', 'examples_tr'],
        'additionalProperties': False,
    }}},
    'required': ['items'],
    'additionalProperties': False,
}

POS_NAME = {'n': 'noun', 'v': 'verb', 'a': 'adjective', 's': 'adjective', 'r': 'adverb'}


def describe_syn(r):
    sid, pos, word, words, gloss, examples = r
    s = f'- id {sid}: "{word}" ({POS_NAME.get(pos, pos)})'
    others = [w for w in words if w != word][:4]
    if others:
        s += f', synonyms: {", ".join(others)}'
    s += f'; definition: {gloss[:300]}'
    if examples:
        s += '; examples: ' + ' | '.join(e[:160] for e in examples[:2])
    return s


_SKIP = {'i', 'a', 'an', 'the', 'tom', 'mary', 'john', 'us', 'it', 'he', 'she', 'we', 'me', 'my', 'no', 'not', 'one'}


def load_syn_todo(dict_path, done, min_freq=3, max_rank=8):
    """WordNet senses of words people meet (Tatoeba frequency), most common words and senses first."""
    db = sqlite3.connect(dict_path)
    try:
        freq = dict(db.execute('SELECT word, n FROM wfreq'))
    except sqlite3.OperationalError:
        freq = {}
    best = {}
    for lemma, rank, sid in db.execute('SELECT lemma, rank, syn_id FROM sense'):
        n = freq.get(lemma, 0)
        if n < min_freq or rank > max_rank or sid in done or '_' in lemma:
            continue
        score = n / (1 + rank) ** 2  # first senses of frequent words first
        if sid not in best or score > best[sid][0]:
            best[sid] = (score, lemma)
    rows = []
    for sid, pos, gloss, examples, words, tr in db.execute('SELECT id, pos, gloss, examples, words, tr FROM syn'):
        if sid not in best:
            continue
        lemma, words = best[sid][1], json.loads(words)
        # "Tom", "I" (iodine), "A" (angstrom): names and symbols, not the everyday word
        if lemma in _SKIP or any(w != lemma and w.lower() == lemma for w in words):
            continue
        if tr and tr != '[]' and examples == '[]':
            continue  # already has Turkish and nothing to translate
        rows.append((best[sid][0], (sid, pos, lemma, words, gloss, json.loads(examples))))
    db.close()
    rows.sort(key=lambda r: -r[0])
    return [r[1] for r in rows]


def save_syn(out, chunk, items):
    by_id = {}
    for it in items or []:
        try:
            by_id[int(it['id'])] = it
        except (KeyError, TypeError, ValueError):
            pass
    n = 0
    with gzip.open(out, 'at', encoding='utf-8') as f:
        for sid, _, _, _, _, examples in chunk:
            it = by_id.get(sid)
            if not it:
                continue
            tr = [t.strip() for t in it.get('tr') or [] if isinstance(t, str) and t.strip()][:4]
            if not tr:
                continue
            ex = [t.strip() for t in it.get('examples_tr') or [] if isinstance(t, str)][:len(examples)]
            f.write(json.dumps({'id': sid, 'tr': tr, 'ex': ex}, ensure_ascii=False) + '\n')
            n += 1
    return n


KINDS = {}  # filled below: kind -> (prompt, schema, describe, saver, chunk size)


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
    has_tr = {(p, c) for p, c in db.execute("SELECT phrase, cat FROM expr WHERE tr IS NOT NULL AND tr != ''")}
    try:
        freq = {(p, c): n for p, c, n in db.execute('SELECT phrase, cat, n FROM exfreq')}
    except sqlite3.OperationalError:
        freq = {}
    db.close()
    order = {c: i for i, c in enumerate(CAT_ORDER)}
    # Expressions people actually use (frequent in Tatoeba sentences) first, then by category.
    # Among equally common ones, entries with no Turkish at all come first.
    rows.sort(key=lambda r: (-min(freq.get((r[0], r[1]), 0), 50), (r[0], r[1]) in has_tr, order.get(r[1], 99), r[2] is None,
                             len(r[0].split()), r[0]))
    return [r for r in rows if f'{r[0]}|{r[1]}' not in done]


def clean_item(it, limit=4):
    senses = []
    for s in it.get('senses') or []:
        if not isinstance(s, dict) or not s.get('title_tr') or not s.get('explain_tr'):
            continue
        senses.append({
            **({'pos': s['pos'].strip()} if s.get('pos') else {}),
            'title_en': s.get('title_en', '').strip(),
            'title_tr': s['title_tr'].strip(),
            'explain_en': s.get('explain_en', '').strip(),
            'explain_tr': s['explain_tr'].strip(),
            'examples': [{'en': x['en'].strip(), 'tr': x['tr'].strip()}
                         for x in (s.get('examples') or []) if x.get('en') and x.get('tr')][:3],
        })
    return senses[:limit]


# ---------------------------------------------------------------- free services

# OpenAI-compatible services with a free tier: (base URL, key variable, default model, seconds between requests)
OPENAI_LIKE = {
    'mistral': ('https://api.mistral.ai/v1', 'MISTRAL_API_KEY', 'mistral-medium-latest', 2.0),
    'groq': ('https://api.groq.com/openai/v1', 'GROQ_API_KEY', 'openai/gpt-oss-120b', 8.0),
    'cerebras': ('https://api.cerebras.ai/v1', 'CEREBRAS_API_KEY', 'gpt-oss-120b', 4.0),
    'github': ('https://models.github.ai/inference', 'GITHUB_TOKEN', 'openai/gpt-4.1-mini', 8.0),
    'nvidia': ('https://integrate.api.nvidia.com/v1', 'NVIDIA_API_KEY', 'meta/llama-3.3-70b-instruct', 3.0),
    'openrouter': ('https://openrouter.ai/api/v1', 'OPENROUTER_API_KEY', 'deepseek/deepseek-chat-v3-0324:free', 4.0),
}

_use_schema = [True]


def _parse(text):
    return json.loads(text[text.index('{'):text.rindex('}') + 1])['items']


def gemini_call(model, key, prompt, schema):
    cfg = {'responseMimeType': 'application/json', 'temperature': 0.3, 'maxOutputTokens': 16000}
    if _use_schema[0]:
        cfg['responseJsonSchema'] = schema
    body = {'contents': [{'parts': [{'text': prompt}]}], 'generationConfig': cfg}
    req = urllib.request.Request(
        f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent',
        data=json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'x-goog-api-key': key})
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.load(r)
    return _parse(data['candidates'][0]['content']['parts'][0]['text'])


def openai_call(base, model, key, prompt, schema):
    # GitHub Models' free tier allows at most 4,000 output tokens per request.
    body = {'model': model, 'temperature': 0.3, 'max_tokens': 4000 if 'models.github.ai' in base else 16000,
            'response_format': {'type': 'json_object'},
            'messages': [{'role': 'user', 'content': prompt}]}
    req = urllib.request.Request(
        f'{base}/chat/completions', data=json.dumps(body).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': f'Bearer {key}',
                 # Cloudflare in front of some services refuses Python's default agent (403, code 1010).
                 'User-Agent': 'vocabloom-dictionary-builder/1.0', 'Accept': 'application/json',
                 **({'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'}
                    if 'models.github.ai' in base else {})})
    with urllib.request.urlopen(req, timeout=240) as r:
        raw = r.read().decode(errors='replace')
    try:
        data = json.loads(raw)
    except ValueError:
        raise ValueError(f'not JSON from {base}: {raw[:200]!r}')
    return _parse(data['choices'][0]['message']['content'] or '')


class Service:
    """One AI service; [call] returns parsed items, None for a bad answer, or raises QuotaExhausted."""

    def __init__(self, name, model):
        self.name = name
        if name == 'gemini':
            self.key = os.environ.get('GEMINI_API_KEY', '')
            self.models = [model] if model else ['gemini-flash-latest', 'gemini-flash-lite-latest']
            self.pause = 7.0
        else:
            base, env, default, pause = OPENAI_LIKE[name]
            self.base, self.key, self.models, self.pause = base, os.environ.get(env, ''), [model or default], pause
        self.misses = 0
        self.bad = 0

    def call(self, chunk, kind):
        prompt, schema, desc, _, _ = KINDS[kind]
        text = prompt + '\n'.join(desc(e) for e in chunk)
        for attempt in range(4):
            if not self.models:
                raise QuotaExhausted('no models left')
            try:
                if self.name == 'gemini':
                    r = gemini_call(self.models[0], self.key, text, schema)
                else:
                    r = openai_call(self.base, self.models[0], self.key, text, schema)
                self.misses = self.bad = 0
                return r
            except urllib.error.HTTPError as e:
                msg = e.read().decode(errors='replace')[:400]
                if e.code == 429:
                    daily = 'PerDay' in msg or 'per day' in msg.lower() or 'daily' in msg.lower()
                    self.misses += 1
                    if daily or self.misses >= 6:
                        print(f'  {self.name}/{self.models[0]}: quota used up: {msg[:160]}')
                        self.models.pop(0)
                        self.misses = 0
                        continue
                    wait = float(e.headers.get('retry-after') or 0) or 20 * (attempt + 1)
                    time.sleep(min(wait, 120))
                    continue
                if e.code == 400 and self.name == 'gemini' and _use_schema[0]:
                    print('  structured output not accepted, continuing without it:', msg[:200])
                    _use_schema[0] = False
                    continue
                if e.code in (401, 403, 404):
                    raise QuotaExhausted(f'{self.name}: {e.code} {msg[:200]}')
                if e.code >= 500:
                    time.sleep(15 * (attempt + 1))
                    continue
                print(f'  {self.name} {e.code}: {msg[:200]}')
                return None
            except (ValueError, KeyError, IndexError, TypeError) as e:
                self.bad += 1
                if self.bad >= 12:  # the service answers, but nothing usable (GitHub Models: 'OK')
                    raise QuotaExhausted(f'{self.name}: 12 unusable answers in a row: {str(e)[:160]}')
                print('  bad answer, retrying:', str(e)[:100])
                time.sleep(3)
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                print('  network:', str(e)[:100])
                time.sleep(10)
        return None


def run(svc, todo, out, deadline, limit, kind):
    _, _, _, saver, size = KINDS[kind]
    done = i = 0
    try:
        while i < len(todo) and time.time() < deadline and done < limit:
            chunk = todo[i:i + size]
            t0 = time.time()
            items = svc.call(chunk, kind)
            if items is None:
                items = []
                for e in chunk:  # one by one; what still fails is skipped this run
                    r = svc.call([e], kind)
                    if r is None:
                        print('  skipped:', e[0])
                    else:
                        items += r
            done += saver(out, chunk, items)
            i += size
            if done and done % 60 < size:
                print(f'{done} done ({svc.name}/{svc.models[0] if svc.models else "-"})', flush=True)
            time.sleep(max(0, svc.pause - (time.time() - t0)))
    except QuotaExhausted as e:
        print(f'{svc.name} stopped: {str(e)[:200]}')
        svc.models = []  # the service is done for this run, for every kind
    return done


def shard_order(rows, key, shard, shards):
    """Own shard first (so services do not overlap), then the rest in the same order."""
    if shards <= 1:
        return rows
    mine = [r for r in rows if zlib.crc32(key(r).encode()) % shards == shard]
    rest = [r for r in rows if zlib.crc32(key(r).encode()) % shards != shard]
    return mine + rest


def read_done(paths, key):
    done = set()
    for path in paths:
        if not os.path.exists(path):
            continue
        with gzip.open(path, 'rt', encoding='utf-8') as f:
            for line in f:
                try:
                    done.add(key(json.loads(line)))
                except (ValueError, KeyError):
                    pass  # a line cut off by an interrupted run
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


# ---------------------------------------------------------------- word families

def describe_root(r):
    root, members = r
    return f'- {root} (known members: {", ".join(members[:16])})'


def load_fam_todo(dict_path, done):
    db = sqlite3.connect(dict_path)
    try:
        freq = dict(db.execute('SELECT word, n FROM wfreq'))
    except sqlite3.OperationalError:
        freq = {}
    rows = []
    for root, members, negs in db.execute('SELECT root, members, negs FROM famg'):
        if root in done:
            continue
        ws = [m[0] for m in json.loads(members)] + [n[0] for n in json.loads(negs)]
        rows.append((root, ws, max(freq.get(w, 0) for w in ws)))
    db.close()
    rows.sort(key=lambda r: -r[2])  # families of words people use most first
    return [(r[0], r[1]) for r in rows]


def save_fam(out, chunk, items):
    by_root = {it['root'].strip().lower(): it for it in items or [] if isinstance(it, dict) and it.get('root')}
    pos_map = {'verb': 'v', 'noun': 'n', 'adjective': 'a', 'adverb': 'r'}
    n = 0
    with gzip.open(out, 'at', encoding='utf-8') as f:
        for root, _ in chunk:
            it = by_root.get(root.lower())
            if not it or not it.get('entries'):
                continue
            entries = []
            for e in it['entries'][:14]:
                if not e.get('word'):
                    continue
                affix = (e.get('affix') or '').strip()
                entries.append({
                    'w': e['word'].strip(), 'p': pos_map.get(e.get('pos'), 'n'), 't': (e.get('tr') or '').strip(),
                    'a': f"{affix}: {e.get('note_tr', '').strip()}" if affix else None,
                    'ae': f"{affix}: {e.get('note_en', '').strip()}" if affix else None,
                    'n': e.get('negative') is True,
                    'x': (e.get('example_en') or '').strip() or None,
                    'xt': (e.get('example_tr') or '').strip() or None,
                })
            fam = {'root': root, 'rootTr': (it.get('root_tr') or '').strip(), 'entries': entries}
            f.write(json.dumps({'root': root, 'family': fam}, ensure_ascii=False) + '\n')
            n += 1
    return n


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


# ---------------------------------------------------------------- second-model review

REVIEW_PROMPT = '''You are a strict second reviewer of an English learner's dictionary for Turkish speakers.
Another AI wrote each entry below. Reference data from open dictionaries (WordNet, Wiktionary, FreeDict,
Tatoeba sentences) is given with each entry; use it to check that no common sense is missing.

Check every entry:
1. The senses: the most common everyday meaning comes first; no common meaning is missing (including the plain,
   literal meaning when the words are often used that way, e.g. "walk down the street"); no rare, wrong or
   invented sense comes before common ones.
2. The Turkish is correct, natural and matches the English (headings, explanations, meanings).
3. Every example uses exactly that sense, is natural English, and its Turkish translation is correct.

If the entry is fully right: "ok": true, "problems": "", "fixed": "".
Otherwise: "ok": false, "problems": a short note in English, and "fixed": the whole corrected entry as a JSON
string in exactly the same format as the given entry (same keys), with all problems fixed.

Answer with JSON only: {"items": [{"key": "<key exactly as given>", "ok": true|false, "problems": "...", "fixed": "..."}]}

Entries:
'''

REVIEW_SCHEMA = {
    'type': 'object',
    'properties': {'items': {'type': 'array', 'items': {
        'type': 'object',
        'properties': {'key': {'type': 'string'}, 'ok': {'type': 'boolean'},
                       'problems': {'type': 'string'}, 'fixed': {'type': 'string'}},
        'required': ['key', 'ok', 'problems', 'fixed'],
        'additionalProperties': False,
    }}},
    'required': ['items'],
    'additionalProperties': False,
}


def service_of(path):
    """exd-groq.jsonl.gz -> groq; the first combined file exd.jsonl.gz was made with Gemini."""
    name = os.path.basename(path).split('.')[0]
    return name.split('-', 1)[1] if '-' in name else 'gemini'


def entry_key(kind, j):
    return f"{kind}:{j['w']}" if kind == 'wd' else f"{kind}:{j['p']}|{j['c']}"


def entry_hash(j):
    """Which version of an entry a review is about: a regenerated entry gets a review of its own."""
    body = {k: v for k, v in j.items() if k != 'c'}
    return hashlib.sha1(json.dumps(body, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:12]


def rejected_keys(paths):
    """Entries whose latest review rejected them without a usable correction: to be written again."""
    out = set()
    for path in paths:
        if not os.path.exists(path):
            continue
        with gzip.open(path, 'rt', encoding='utf-8') as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                k = r['k'].split('#')[0]
                if r.get('ok') or r.get('fix'):
                    out.discard(k)
                else:
                    out.add(k)
    return out


def references(db, kind, j):
    """What the open dictionaries say, so the reviewer can spot a missing common sense."""
    out = []
    if kind == 'wd':
        word = j['w']
        senses = db.execute('SELECT s.pos, s.gloss FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = ? '
                            'ORDER BY x.rank LIMIT 6', (word,)).fetchall()
        if senses:
            out.append('WordNet: ' + ' | '.join(f'({p}) {g[:120]}' for p, g in senses))
        key = f'w:{word}'
    else:
        p, c = j['p'], j['c']
        r = db.execute('SELECT en, tr FROM expr WHERE phrase = ? AND cat = ?', (p, c)).fetchone()
        if r and r[0]:
            out.append('Wiktionary/WordNet definition: ' + r[0][:400])
        if r and r[1]:
            out.append('Curated Turkish: ' + r[1][:120])
        word = p.split()[0]
        key = f'{p}|{c}'
    ft = db.execute('SELECT tr FROM ft WHERE word = ?', (word,)).fetchone()
    if ft:
        out.append(f'FreeDict "{word}": ' + '; '.join(json.loads(ft[0])[:5])[:300])
    ex = db.execute('SELECT en FROM exs WHERE key = ? LIMIT 3', (key,)).fetchall()
    if ex:
        out.append('Real usage (Tatoeba): ' + ' | '.join(e[0] for e in ex))
    return out


def describe_review(r):
    kind, key, _, entry, refs = r
    s = f'- key "{key}" ({ {"exd": "expression", "wd": "word", "gl": "short meaning"}[kind] }): ' \
        + json.dumps(entry, ensure_ascii=False)
    for ref in refs:
        s += f'\n    reference: {ref}'
    return s


def load_review_todo(dict_path, files, reviewed, me):
    """Generated entries not reviewed yet: other services' work first (a different model checks it),
    then this service's own. Entries already in the app come first."""
    db = sqlite3.connect(dict_path)
    other, own = [], []
    for path in files:
        base = os.path.basename(path)
        kind = 'exd' if base.startswith('exd') else 'wd' if base.startswith('wd-') else 'gl' if base.startswith('gl-') else None
        if kind is None or not os.path.exists(path):
            continue
        gen = service_of(path)
        with gzip.open(path, 'rt', encoding='utf-8') as f:
            for line in f:
                try:
                    j = json.loads(line)
                    key = f'{entry_key(kind, j)}#{entry_hash(j)}'
                except (ValueError, KeyError):
                    continue
                if key in reviewed:
                    continue
                reviewed.add(key)  # one review per version even when two services made it
                entry = {k: v for k, v in j.items() if k not in ('c',)}
                row = (kind, key, gen, entry, references(db, kind, j))
                (own if gen == me else other).append(row)
    db.close()
    order = {'exd': 0, 'gl': 1, 'wd': 2}
    other.sort(key=lambda r: order[r[0]])
    own.sort(key=lambda r: order[r[0]])
    return other + own


def save_review(out, chunk, items):
    by_k = {it['key'].strip(): it for it in items or [] if isinstance(it, dict) and it.get('key')}
    n = 0
    with gzip.open(out, 'at', encoding='utf-8') as f:
        for kind, key, gen, entry, _ in chunk:
            it = by_k.get(key)
            if not it or not isinstance(it.get('ok'), bool):
                continue
            fix = None
            if not it['ok']:
                try:
                    fix = json.loads(it.get('fixed') or '')
                except ValueError:
                    fix = None
                if isinstance(fix, dict):
                    fix = {**entry, **fix}
                    if kind in ('exd', 'wd'):
                        fix['s'] = clean_item({'senses': fix.get('s') or fix.get('senses') or []}, limit=6)
                        if not fix['s']:
                            fix = None
                    elif not (fix.get('tr') or '').strip():
                        fix = None
                else:
                    fix = None
            f.write(json.dumps({'k': key, 'gen': gen, 'ok': it['ok'], 'note': (it.get('problems') or '')[:300],
                                'fix': fix}, ensure_ascii=False) + '\n')
            n += 1
    return n


KINDS.update({
    'expr': (PROMPT, SCHEMA, describe, save, CHUNK),
    'fam': (FAM_PROMPT, FAM_SCHEMA, describe_root, save_fam, 4),
    'gloss': (GLOSS_PROMPT, GLOSS_SCHEMA, describe_gloss, save_gloss, 20),
    'word': (WORD_PROMPT, WORD_SCHEMA, describe_word, save_word, 5),
    'review': (REVIEW_PROMPT, REVIEW_SCHEMA, describe_review, save_review, 5),
    'syn': (SYN_PROMPT, SYN_SCHEMA, describe_syn, save_syn, 10),
})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dict_db')
    ap.add_argument('out', help='expression results of this service (exd-<service>.jsonl.gz)')
    ap.add_argument('--provider', default='gemini', help='gemini, mistral, groq, cerebras, github or claude')
    ap.add_argument('--model', default='')
    ap.add_argument('--minutes', type=float, default=300)
    ap.add_argument('--limit', type=int, default=10 ** 9)
    ap.add_argument('--families', default='', help='word-family results of this service; done after the expressions')
    ap.add_argument('--review', default='', help='second-model reviews by this service (rv-<service>.jsonl.gz)')
    ap.add_argument('--gloss', default='', help='short Turkish meanings of this service (gl-<service>.jsonl.gz)')
    ap.add_argument('--words', default='', help='word explanations of this service (wd-<service>.jsonl.gz)')
    ap.add_argument('--senses', default='', help='WordNet-sense results of this service (syn-<service>.jsonl.gz)')
    ap.add_argument('--shard', default='0/1', help='k/n: this service takes every n-th item first')
    ap.add_argument('--done', nargs='*', default=[], help='results of other services, to skip')
    a = ap.parse_args()
    shard, shards = map(int, a.shard.split('/'))
    deadline = time.time() + a.minutes * 60

    exd_files = [a.out] + [f for f in a.done if os.path.basename(f).startswith('exd')]
    rv_all = [a.review] + [f for f in a.done if os.path.basename(f).startswith('rv-')] if a.review else []
    rejected = rejected_keys(rv_all)  # rejected without a correction: write them again
    done = read_done(exd_files, lambda j: f"{j['p']}|{j['c']}") - {k[4:] for k in rejected if k.startswith('exd:')}
    todo = shard_order(load_todo(a.dict_db, done), lambda r: f'{r[0]}|{r[1]}', shard, shards)
    print(f'{len(done)} already done, {len(todo)} to go')
    if a.provider == 'claude':
        n = run_claude(todo, a.out, a.model or 'claude-opus-5-5', deadline, a.limit)
        print(f'added {n}')
        return
    svc = Service(a.provider, a.model)
    if not svc.key:
        print(f'{a.provider}: no API key, nothing to do')
        return
    # The three kinds share the run: expressions, word families and WordNet
    # senses each get a slice of the time, and time a kind does not use goes on
    # to the next one. A used-up quota stops them all.
    start, total = time.time(), deadline - time.time()
    # First a short Turkish meaning for every expression that has none: 30 per request, so it is quick.
    if a.gloss:
        gl_files = [a.gloss] + [f for f in a.done if os.path.basename(f).startswith('gl-')]
        gdone = read_done(gl_files, lambda j: f"{j['p']}|{j['c']}") - {k[3:] for k in rejected if k.startswith('gl:')}
        gtodo = shard_order(load_gloss_todo(a.dict_db, gdone | done), lambda r: f'{r[0]}|{r[1]}', shard, shards)
        print(f'short meanings: {len(gdone)} done, {len(gtodo)} to go')
        m = run(svc, gtodo, a.gloss, min(deadline, start + total * 0.2), a.limit, 'gloss')
        print(f'short meanings added {m}; remaining {len(gtodo) - m}')
    if not svc.models:
        return

    # Second-model review of what the services wrote; only reviewed entries ship (tools/build_dict.py).
    if a.review and svc.models and time.time() < deadline:
        rv_files = [a.review] + [f for f in a.done if os.path.basename(f).startswith('rv-')]
        reviewed = read_done(rv_files, lambda j: j['k'])
        gen_files = [f for f in a.done + [a.out, a.gloss, a.words]
                     if f and os.path.basename(f).startswith(('exd', 'wd-', 'gl-'))]
        n_done = len(reviewed)
        rtodo = load_review_todo(a.dict_db, list(dict.fromkeys(gen_files)), reviewed, a.provider)
        print(f'reviews: {n_done} done, {len(rtodo)} to go')
        m = run(svc, rtodo, a.review, min(deadline, start + total * 0.45), a.limit, 'review')
        print(f'reviews added {m}')
    # Frequent words with no Turkish at all ("usually", "each"): a few hundred, before the long queues.
    if a.words and svc.models and time.time() < deadline:
        wd_files = [a.words] + [f for f in a.done if os.path.basename(f).startswith('wd-')]
        wdone = read_done(wd_files, lambda j: j['w']) - {k[3:] for k in rejected if k.startswith('wd:')}
        mtodo = shard_order(load_word_todo(a.dict_db, wdone, only_missing=True), lambda r: r[0], shard, shards)
        print(f'words without Turkish: {len(mtodo)} to go')
        m = run(svc, mtodo, a.words, min(deadline, start + total * 0.5), a.limit, 'word')
        print(f'words without Turkish added {m}')

    n = run(svc, todo, a.out, min(deadline, start + total * 0.65), a.limit, 'expr')
    print(f'added {n}; remaining {len(todo) - n}')

    if a.words and svc.models and time.time() < deadline:
        wd_files = [a.words] + [f for f in a.done if os.path.basename(f).startswith('wd-')]
        wdone = read_done(wd_files, lambda j: j['w']) - {k[3:] for k in rejected if k.startswith('wd:')}
        wtodo = shard_order(load_word_todo(a.dict_db, wdone), lambda r: r[0], shard, shards)
        print(f'words: {len(wdone)} done, {len(wtodo)} to go')
        m = run(svc, wtodo, a.words, min(deadline, start + total * 0.8), a.limit, 'word')
        print(f'words added {m}; remaining {len(wtodo) - m}')

    if a.families and svc.models and time.time() < deadline:
        wfd_files = [a.families] + [f for f in a.done if os.path.basename(f).startswith('wfd')]
        fdone = read_done(wfd_files, lambda j: j['root'])
        ftodo = shard_order(load_fam_todo(a.dict_db, fdone), lambda r: r[0], shard, shards)
        print(f'word families: {len(fdone)} done, {len(ftodo)} to go')
        m = run(svc, ftodo, a.families, min(deadline, start + total * 0.9), a.limit, 'fam')
        print(f'word families added {m}; remaining {len(ftodo) - m}')

    if a.senses and svc.models and time.time() < deadline:
        syn_files = [a.senses] + [f for f in a.done if os.path.basename(f).startswith('syn')]
        sdone = read_done(syn_files, lambda j: int(j['id']))
        stodo = shard_order(load_syn_todo(a.dict_db, sdone), lambda r: str(r[0]), shard, shards)
        print(f'word senses: {len(sdone)} done, {len(stodo)} to go')
        m = run(svc, stodo, a.senses, deadline, a.limit, 'syn')
        print(f'word senses added {m}; remaining {len(stodo) - m}')


if __name__ == '__main__':
    sys.exit(main())

"""Writes our own English-Turkish dictionary entries with Claude.

The meanings are written fresh by the model from the English word (and, as a
hint, the free WordNet / Wiktionary English definitions). No Turkish text from
any other dictionary is sent, so the result is our own work.

usage: python3 tools/own_dict/generate.py ITEMS.json OUT_DIR [--model M] [--chunk 10]

Needs ANTHROPIC_API_KEY. Writes OUT_DIR/results.jsonl (one entry per line) and
OUT_DIR/usage.json (measured tokens and cost).
"""
import argparse
import json
import os
import sys
import time

import anthropic

# $ per million tokens (input, output), Claude API list prices, prompts under 100K tokens.
PRICES = {'claude-haiku-5-5': (0.10, 0.50), 'claude-sonnet-5-5': (2.0, 10.0), 'claude-opus-5-5': (4.0, 20.0)}

SYSTEM = '''You write a learner's English-Turkish dictionary for Turkish speakers who read English books.
Write every Turkish meaning yourself, in natural, current Turkish. Do not copy wording from any existing dictionary.

For each English headword give all of its important senses, the most common one first. Do not stop at the first
meaning: a word like "run" needs koşmak, but also çalıştırmak (a machine, a program), yönetmek/işletmek (a business),
akmak (water), sürmek (a film or play runs), aday olmak (run for office) and so on. Usually 1 to 8 senses: many for
common, many-sided words, one or two for rare or technical words. Leave out archaic, obsolete and vulgar senses.
Group by part of speech.

For every sense:
- "pos": noun, verb, adjective, adverb, preposition, conjunction, pronoun, determiner, interjection, prefix, suffix or phrase
- "tr": the Turkish meaning, 1 to 4 words; up to 3 close synonyms separated by commas ("terk etmek, bırakmak")
- "note": an optional very short Turkish hint on when it is used ("makine, program için", "resmî"), else ""
- "en": a short natural English example sentence (at most 12 words) using the headword in this sense
- "ex_tr": its natural Turkish translation

If the headword is an inflected form (e.g. "sleeping", "pressed", "teeth"), put its base form in "base" and give the
meanings of this form as readers meet it ("pressed": bastırılmış, ütülü; sıkıştırılmış ...); otherwise "base" is "".
For a multi-word expression (idiom, phrasal verb, proverb ...) give the meaning of the whole expression, with a
natural Turkish equivalent when Turkish has one (a deyim or atasözü), else a clear short explanation.
Answer only with the JSON object.'''

SENSE = {
    'type': 'object',
    'properties': {k: {'type': 'string'} for k in ('pos', 'tr', 'note', 'en', 'ex_tr')},
    'required': ['pos', 'tr', 'note', 'en', 'ex_tr'],
    'additionalProperties': False,
}
SCHEMA = {
    'type': 'object',
    'properties': {
        'items': {
            'type': 'array',
            'items': {
                'type': 'object',
                'properties': {
                    'w': {'type': 'string'},
                    'base': {'type': 'string'},
                    'senses': {'type': 'array', 'items': SENSE},
                },
                'required': ['w', 'base', 'senses'],
                'additionalProperties': False,
            },
        }
    },
    'required': ['items'],
    'additionalProperties': False,
}


def describe(it):
    if it['k'] == 'expr':
        hint = f" (expression; English hint: {it['en']})" if it.get('en') else ' (expression)'
        return f"- {it['w']}{hint}"
    hint = '; '.join(it.get('wn', [])[:6])
    return f"- {it['w']}" + (f" (WordNet hints: {hint})" if hint else '')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('items')
    ap.add_argument('out')
    ap.add_argument('--model', default='claude-haiku-5-5')
    ap.add_argument('--chunk', type=int, default=10)
    ap.add_argument('--effort', default='low')
    a = ap.parse_args()

    items = json.load(open(a.items, encoding='utf-8'))
    os.makedirs(a.out, exist_ok=True)
    client = anthropic.Anthropic()
    tot_in = tot_out = 0
    reqs = []
    t0 = time.time()
    with open(os.path.join(a.out, 'results.jsonl'), 'w', encoding='utf-8') as out:
        for i in range(0, len(items), a.chunk):
            part = items[i:i + a.chunk]
            prompt = 'Headwords:\n' + '\n'.join(describe(it) for it in part)
            for attempt in range(3):
                try:
                    r = client.messages.create(
                        model=a.model,
                        max_tokens=16000,
                        system=SYSTEM,
                        messages=[{'role': 'user', 'content': prompt}],
                        output_config={'effort': a.effort, 'format': {'type': 'json_schema', 'schema': SCHEMA}},
                    )
                    break
                except (anthropic.RateLimitError, anthropic.APIConnectionError, anthropic.InternalServerError) as e:
                    print('retry', i, e, file=sys.stderr)
                    time.sleep(10 * (attempt + 1))
            else:
                sys.exit('giving up')
            u = r.usage
            tot_in += u.input_tokens
            tot_out += u.output_tokens
            reqs.append({'first': part[0]['w'], 'n': len(part), 'in': u.input_tokens, 'out': u.output_tokens,
                         'stop': r.stop_reason})
            if r.stop_reason != 'end_turn':
                print('stop_reason', r.stop_reason, part[0]['w'], file=sys.stderr)
                continue
            text = ''.join(b.text for b in r.content if b.type == 'text')
            got = {x['w'].lower(): x for x in json.loads(text)['items']}
            for it in part:
                e = got.get(it['w'].lower())
                rec = {'w': it['w'], 'kind': it['k'], 'group': it['group'], 'freq': it.get('freq'),
                       'base': (e or {}).get('base', ''), 'senses': (e or {}).get('senses', [])}
                out.write(json.dumps(rec, ensure_ascii=False) + '\n')
            print(f"{i + len(part)}/{len(items)} in={u.input_tokens} out={u.output_tokens}", flush=True)

    pin, pout = PRICES.get(a.model, (0, 0))
    cost = tot_in / 1e6 * pin + tot_out / 1e6 * pout
    summary = {'model': a.model, 'effort': a.effort, 'items': len(items), 'requests': len(reqs),
               'input_tokens': tot_in, 'output_tokens': tot_out, 'cost_usd': round(cost, 4),
               'cost_usd_batch': round(cost / 2, 4), 'seconds': round(time.time() - t0), 'per_request': reqs}
    json.dump(summary, open(os.path.join(a.out, 'usage.json'), 'w'), indent=1)
    print(json.dumps({k: v for k, v in summary.items() if k != 'per_request'}))


if __name__ == '__main__':
    main()

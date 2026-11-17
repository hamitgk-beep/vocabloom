"""Full run of our own English-Turkish dictionary with Claude Haiku.

Same prompt and schema as generate.py, but several requests run at once and a
failed request is retried. Results are written one line per headword to
OUT_DIR/results.jsonl, and a request that still fails is listed in
OUT_DIR/failed.jsonl so it can be run again later.

usage: python3 tools/own_dict/generate_full.py ITEMS.json OUT_DIR [--model M] [--workers 6]
"""
import argparse
import json
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import anthropic

from generate import PRICES, SCHEMA, SYSTEM, describe

CHUNK = 10
lock = threading.Lock()


def call(client, model, part):
    prompt = 'Headwords:\n' + '\n'.join(describe(it) for it in part)
    last = None
    for attempt in range(6):
        try:
            return client.messages.create(
                model=model,
                max_tokens=16000,
                system=SYSTEM,
                messages=[{'role': 'user', 'content': prompt}],
                output_config={'effort': 'low', 'format': {'type': 'json_schema', 'schema': SCHEMA}},
            )
        except (anthropic.RateLimitError, anthropic.APIConnectionError, anthropic.InternalServerError) as e:
            last = e
            time.sleep(min(60, 5 * (2 ** attempt)))
    raise last


def job(client, model, part):
    r = call(client, model, part)
    u = r.usage
    if r.stop_reason != 'end_turn':
        return part, None, u, r.stop_reason
    text = ''.join(b.text for b in r.content if b.type == 'text')
    return part, json.loads(text)['items'], u, 'end_turn'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('items')
    ap.add_argument('out')
    ap.add_argument('--model', default='claude-haiku-5-5')
    ap.add_argument('--workers', type=int, default=6)
    a = ap.parse_args()

    items = json.load(open(a.items, encoding='utf-8'))
    os.makedirs(a.out, exist_ok=True)
    client = anthropic.Anthropic(max_retries=0)
    parts = [items[i:i + CHUNK] for i in range(0, len(items), CHUNK)]
    tot_in = tot_out = done = 0
    t0 = time.time()
    res = open(os.path.join(a.out, 'results.jsonl'), 'w', encoding='utf-8')
    failed = open(os.path.join(a.out, 'failed.jsonl'), 'w', encoding='utf-8')
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = [ex.submit(job, client, a.model, p) for p in parts]
        for f in as_completed(futs):
            try:
                part, got, u, stop = f.result()
            except Exception as e:  # keep going; failures are recorded
                with lock:
                    failed.write(json.dumps({'error': repr(e)[:300]}) + '\n')
                continue
            with lock:
                tot_in += u.input_tokens
                tot_out += u.output_tokens
                done += 1
                if got is None:
                    failed.write(json.dumps({'first': part[0]['w'], 'stop': stop}) + '\n')
                    continue
                by = {x['w'].lower(): x for x in got}
                for it in part:
                    e = by.get(it['w'].lower())
                    if e is None:
                        failed.write(json.dumps({'w': it['w'], 'why': 'missing'}, ensure_ascii=False) + '\n')
                        continue
                    rec = {'w': it['w'], 'kind': it['k'], 'group': it['group'], 'freq': it.get('freq'),
                           'base': e.get('base', ''), 'senses': e.get('senses', [])}
                    res.write(json.dumps(rec, ensure_ascii=False) + '\n')
                res.flush()
                failed.flush()
                if done % 50 == 0:
                    print(f"{done}/{len(parts)} requests, {round(time.time() - t0)}s, "
                          f"in={tot_in} out={tot_out}", flush=True)
    res.close()
    failed.close()

    pin, pout = PRICES.get(a.model, (0, 0))
    cost = tot_in / 1e6 * pin + tot_out / 1e6 * pout
    summary = {'model': a.model, 'effort': 'low', 'items': len(items), 'requests': len(parts),
               'input_tokens': tot_in, 'output_tokens': tot_out, 'cost_usd': round(cost, 4),
               'cost_usd_batch': round(cost / 2, 4), 'seconds': round(time.time() - t0)}
    json.dump(summary, open(os.path.join(a.out, 'usage.json'), 'w'), indent=1)
    print(json.dumps(summary))


if __name__ == '__main__':
    sys.exit(main())

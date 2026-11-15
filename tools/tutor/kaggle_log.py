#!/usr/bin/env python3
"""Prints the readable output of a Kaggle notebook log (a JSON list of
{stream_name, data}): training example, losses, sample answers, errors."""
import json, re, sys


def main(path):
    raw = open(path, encoding='utf-8', errors='replace').read()
    try:
        text = ''.join(x.get('data', '') for x in json.loads(raw))
    except Exception:
        text = raw
    # Progress bars are noise.
    lines = [l for l in re.split(r'[\r\n]+', text) if l.strip() and '%|' not in l and 'it/s]' not in l]
    out = '\n'.join(lines)
    print(out[:60000])


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print('=' * 30, p)
        main(p)

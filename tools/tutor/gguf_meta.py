#!/usr/bin/env python3
"""Prints the metadata of a GGUF file (chat template, special tokens) from its
first bytes, so a model can be checked without downloading all of it.

    curl -r 0-60000000 -o head.gguf URL && python3 gguf_meta.py head.gguf
"""
import struct, sys

TYPES = {0: 'B', 1: 'b', 2: 'H', 3: 'h', 4: 'I', 5: 'i', 6: 'f', 7: '?', 10: 'Q', 11: 'q', 12: 'd'}


def read(f, fmt):
    n = struct.calcsize('<' + fmt)
    return struct.unpack('<' + fmt, f.read(n))[0]


def string(f):
    return f.read(read(f, 'Q')).decode('utf-8', 'replace')


def value(f, t):
    if t in TYPES:
        return read(f, TYPES[t])
    if t == 8:
        return string(f)
    if t == 9:
        it, n = read(f, 'I'), read(f, 'Q')
        return [value(f, it) for _ in range(n)]
    raise ValueError('unknown type %d' % t)


def main(path):
    with open(path, 'rb') as f:
        assert f.read(4) == b'GGUF', 'not a GGUF file'
        version, _tensors, kvs = read(f, 'I'), read(f, 'Q'), read(f, 'Q')
        meta = {}
        for _ in range(kvs):
            k = string(f)
            meta[k] = value(f, read(f, 'I'))
    print('gguf version', version)
    tokens = meta.get('tokenizer.ggml.tokens') or []
    for k, v in meta.items():
        if isinstance(v, list):
            print('%s: list of %d' % (k, len(v)))
        elif k == 'tokenizer.chat_template':
            print('%s:\n%s\n--- end of template' % (k, v))
        else:
            name = ' (%s)' % tokens[v] if k.endswith('_token_id') and isinstance(v, int) and v < len(tokens) else ''
            print('%s: %r%s' % (k, v, name))
    for i in range(151640, min(151680, len(tokens))):
        print('token', i, repr(tokens[i]))


if __name__ == '__main__':
    main(sys.argv[1])

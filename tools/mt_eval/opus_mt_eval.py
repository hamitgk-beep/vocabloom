#!/usr/bin/env python3
"""Offline OPUS-MT (MarianMT) English -> Turkish evaluation, outside the app.

A prototype step for a free, offline sentence translation on Windows (where
Google ML Kit does not run). Nothing here is bundled with or downloaded by the
app. The model is read from a folder the developer downloads by hand:

  onnx-community/opus-mt-tc-big-en-tr (ONNX export of
  Helsinki-NLP/opus-mt-tc-big-en-tr, CC-BY 4.0), files:
    source.spm, target.spm, vocab.json, config.json,
    onnx/encoder_model_int8.onnx, onnx/decoder_model_int8.onnx

It runs the same steps a Dart port over the app's ONNX Runtime binding
(lib/tts/ort.dart: float32 / int64 tensors) would run: SentencePiece pieces ->
vocab ids + </s>, the encoder once, then greedy decoding with the decoder
(no key/value cache, so the Dart side needs only one decoder file), ids ->
pieces -> text.

  python3 -I tools/mt_eval/opus_mt_eval.py --model <dir> --dict assets/dict.db \
      --out results.jsonl [--tatoeba 200]

Reports per sentence: the Turkish, the time, and chrF against a reference when
there is one (the reported sentences, Tatoeba pairs from dict.db, read only).
"""
import argparse
import json
import random
import sqlite3
import statistics
import sys
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import sentencepiece as spm


class OpusMt:
    def __init__(self, d: Path, threads: int = 4):
        cfg = json.loads((d / 'config.json').read_text())
        self.start = cfg['decoder_start_token_id']
        self.eos = cfg['eos_token_id']
        self.pad = cfg['pad_token_id']
        self.vocab = json.loads((d / 'vocab.json').read_text())
        self.inv = {i: p for p, i in self.vocab.items()}
        self.unk = self.vocab.get('<unk>', 1)
        self.src = spm.SentencePieceProcessor(model_file=str(d / 'source.spm'))
        self.tgt = spm.SentencePieceProcessor(model_file=str(d / 'target.spm'))
        o = ort.SessionOptions()
        o.intra_op_num_threads = threads
        self.enc = ort.InferenceSession(str(d / 'onnx/encoder_model_int8.onnx'), o, providers=['CPUExecutionProvider'])
        self.dec = ort.InferenceSession(str(d / 'onnx/decoder_model_int8.onnx'), o, providers=['CPUExecutionProvider'])

    def ids(self, text: str):
        return [self.vocab.get(p, self.unk) for p in self.src.encode(text, out_type=str)] + [self.eos]

    def translate(self, text: str) -> str:
        src = np.array([self.ids(text)], dtype=np.int64)
        mask = np.ones_like(src)
        hidden = self.enc.run(['last_hidden_state'], {'input_ids': src, 'attention_mask': mask})[0]
        out = [self.start]
        for _ in range(min(512, 2 * src.shape[1] + 16)):
            logits = self.dec.run(['logits'], {
                'input_ids': np.array([out], dtype=np.int64),
                'encoder_attention_mask': mask,
                'encoder_hidden_states': hidden,
            })[0]
            step = logits[0, -1]
            step[self.pad] = -np.inf  # never generate the start / pad token
            nxt = int(step.argmax())
            if nxt == self.eos:
                break
            out.append(nxt)
        pieces = [self.inv.get(i, '') for i in out[1:]]
        return self.tgt.decode_pieces(pieces).strip()


def chrf(hyp: str, ref: str, n: int = 6, beta: float = 2.0) -> float:
    """Sentence chrF (Popovic 2015; sacreBLEU's defaults: character 1..6-grams
    without spaces, beta 2), 0-100. Written out to need no extra package."""
    from collections import Counter
    h, r = hyp.replace(' ', ''), ref.replace(' ', '')
    ps, rs = [], []
    for k in range(1, n + 1):
        hc = Counter(h[i:i + k] for i in range(len(h) - k + 1))
        rc = Counter(r[i:i + k] for i in range(len(r) - k + 1))
        if not hc or not rc:
            continue
        m = sum((hc & rc).values())
        ps.append(m / sum(hc.values()))
        rs.append(m / sum(rc.values()))
    if not ps:
        return 0.0
    p, q = sum(ps) / len(ps), sum(rs) / len(rs)
    if p + q == 0:
        return 0.0
    return 100 * (1 + beta ** 2) * p * q / (beta ** 2 * p + q)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True, type=Path)
    ap.add_argument('--corpus', type=Path, default=Path(__file__).with_name('corpus.tsv'))
    ap.add_argument('--dict', type=Path, help='assets/dict.db, opened read only, for Tatoeba references')
    ap.add_argument('--tatoeba', type=int, default=200)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--threads', type=int, default=4)
    a = ap.parse_args()

    rows = []
    for line in a.corpus.read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        kind, en, ref = (line.split('\t') + ['', ''])[:3]
        rows.append({'kind': kind, 'en': en, 'ref': ref or None})
    if a.dict and a.tatoeba:
        db = sqlite3.connect(f'file:{a.dict}?mode=ro', uri=True)
        pairs = db.execute("SELECT DISTINCT en, tr FROM exs WHERE length(en) - length(replace(en, ' ', '')) >= 5").fetchall()
        random.Random(7).shuffle(pairs)
        rows += [{'kind': 'tatoeba', 'en': en, 'ref': tr} for en, tr in pairs[:a.tatoeba]]

    t0 = time.perf_counter()
    mt = OpusMt(a.model, a.threads)
    load = time.perf_counter() - t0
    times, scores = [], {}
    with a.out.open('w') as f:
        for r in rows:
            s = time.perf_counter()
            r['tr'] = mt.translate(r['en'])
            r['ms'] = round((time.perf_counter() - s) * 1000)
            times.append(r['ms'])
            if r['ref']:
                r['chrf'] = round(chrf(r['tr'], r['ref']), 1)
                scores.setdefault(r['kind'], []).append(r['chrf'])
            f.write(json.dumps(r, ensure_ascii=False) + '\n')
    summary = {
        'sentences': len(rows),
        'load_s': round(load, 1),
        'ms_median': statistics.median(times),
        'ms_p90': sorted(times)[int(len(times) * 0.9) - 1],
        'chrf_mean': {k: round(statistics.mean(v), 1) for k, v in scores.items()},
        'chrf_n': {k: len(v) for k, v in scores.items()},
    }
    print(json.dumps(summary, ensure_ascii=False, indent=1))
    return 0


if __name__ == '__main__':
    sys.exit(main())

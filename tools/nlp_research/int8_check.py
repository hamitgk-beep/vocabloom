"""Task 5E, stage 5: does int8 quantization change the decisions? Scores the dumped rows with the int8 ONNX model in
ONNX Runtime and compares with the PyTorch scores of score_senses.py: the model's first choice per row (the gate) and
the idiom margin's side of the veto threshold.

With INT8_SAVE=1 the int8 scores are also written to SCORE_DIR/MODEL_KEY_int8/SET.json.

usage: python3 tools/nlp_research/int8_check.py MODEL_KEY ONNX_DIR DUMP_DIR SCORE_DIR WORK_DIR SET [SET ...]
"""
import json, os, sys, glob

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from score_senses import MODELS, gloss, marked  # noqa
from eval_systems import scores_for, model_top, idiom_feats  # noqa

key, onnx_dir, dump, score_dir, work, sets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6:]
kind, hf = MODELS[key]
snap = sorted(glob.glob(f"/root/work/hf/models--{hf.replace('/', '--')}/snapshots/*"))[-1]
tp = os.path.join(snap, 'tokenizer.json')
if not os.path.exists(tp):
    tp = f'{onnx_dir}/{key}/tok/tokenizer.json'
tok = Tokenizer.from_file(tp)
tok.no_padding()
tok.enable_truncation(128)
s = ort.InferenceSession(f'{onnx_dir}/{key}/model_int8.onnx', providers=['CPUExecutionProvider'])
names = [i.name for i in s.get_inputs()]


def feed(e):
    d = {'input_ids': np.array([e.ids], dtype=np.int64), 'attention_mask': np.array([e.attention_mask], dtype=np.int64)}
    if 'token_type_ids' in names:
        d['token_type_ids'] = np.array([e.type_ids], dtype=np.int64)
    return d


cache = {}


def emb(t):
    if t not in cache:
        h = s.run(None, feed(tok.encode(t)))[0][0]
        v = h.mean(0)
        cache[t] = v / np.linalg.norm(v)
    return cache[t]


veto = json.load(open(f'{work}/idiom_tuned.json'))['rules'].get(key, {}).get('veto_lo') if os.path.exists(f'{work}/idiom_tuned.json') else None
for n in sets:
    rows = [json.loads(l) for l in open(f'{dump}/{n}.engine.jsonl', encoding='utf-8')]
    ref = scores_for(score_dir, key, n)
    same_top = total = same_side = sides = 0
    mine = []
    for r in rows:
        if not r.get('cands'):
            mine.append([])
            continue
        sc = []
        for c in r['cands']:
            g = gloss(c, key == 'mminilm')
            if g is None:
                sc.append(None)
                continue
            ctx, w = marked(r)
            if kind == 'bi':
                sc.append(float(emb(r['sentence']) @ emb(g)))
            else:
                lg = s.run(None, feed(tok.encode(ctx, g)))[0][0]
                sc.append(float(lg[0]) if len(lg) == 1 else float(lg[1] - lg[0]))
        mine.append(sc)
        a, b = model_top(r, ref[r['k']]), model_top(r, sc)
        if a is not None or b is not None:
            total += 1
            same_top += (a and b and a['id'] == b['id']) or False
        if 'label' in r and veto is not None:
            fa, fb = idiom_feats(r, ref[r['k']]), idiom_feats(r, sc)
            if fa is not None and fb is not None:
                sides += 1
                same_side += (fa < veto) == (fb < veto)
    if os.environ.get('INT8_SAVE'):
        os.makedirs(f'{score_dir}/{key}_int8', exist_ok=True)
        json.dump({'model': hf + ' (int8 ONNX)', 'scores': mine}, open(f'{score_dir}/{key}_int8/{n}.json', 'w'))
    print(f'{key} int8 on {n}: same first choice {same_top}/{total} = {100 * same_top / max(1, total):.1f}%'
          + (f'; same veto decision {same_side}/{sides} = {100 * same_side / max(1, sides):.1f}%' if sides else ''), flush=True)

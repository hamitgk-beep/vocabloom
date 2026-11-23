"""Task 5N: write a trained BERT cross-encoder (HF BertForSequenceClassification) as the small binary the pure-Dart
runner (lib/nlp/cross_encoder.dart) reads, plus reference logits to check the Dart forward pass against.

  python export_idiom_cls.py MODEL_DIR OUT.bin [REF.jsonl]

Format (little endian): b'SXC1', u32 json-header length, JSON header {config, tensors:[{name, shape, q}]}, then each
tensor in order: q=0 float32 data; q=1 int8 per-row (rows = shape[0]) as f32 scales[rows] then int8 data.
Big matrices (word embeddings, Linear weights) are int8 per row; the rest float32. The vocabulary is stored too.
"""
import json, struct, sys
import numpy as np, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
md, out = sys.argv[1], sys.argv[2]
m = AutoModelForSequenceClassification.from_pretrained(md).eval(); tok = AutoTokenizer.from_pretrained(md)
sd = {k: v.detach().float().numpy() for k, v in m.state_dict().items() if not k.endswith('position_ids')}
c = m.config
hdr = {'config': {'hidden': c.hidden_size, 'layers': c.num_hidden_layers, 'heads': c.num_attention_heads,
                  'inter': c.intermediate_size, 'eps': c.layer_norm_eps, 'vocab': c.vocab_size},
       'vocab': [t for t, _ in sorted(tok.get_vocab().items(), key=lambda x: x[1])], 'tensors': []}
blobs = []
for k, v in sd.items():
    q = 1 if v.ndim == 2 and v.shape[0] * v.shape[1] >= 65536 else 0
    hdr['tensors'].append({'name': k, 'shape': list(v.shape), 'q': q})
    if q:
        s = np.abs(v).max(axis=1) / 127.0; s[s == 0] = 1
        blobs.append(s.astype('<f4').tobytes() + np.clip(np.round(v / s[:, None]), -127, 127).astype(np.int8).tobytes())
    else:
        blobs.append(v.astype('<f4').tobytes())
h = json.dumps(hdr).encode()
with open(out, 'wb') as f:
    f.write(b'SXC1'); f.write(struct.pack('<I', len(h))); f.write(h)
    for b in blobs: f.write(b)
print('wrote', out, sum(len(b) for b in blobs) + len(h), 'bytes')
if len(sys.argv) > 3:
    # reference: the int8-dequantized model's probabilities, so the Dart check isolates the forward pass
    for t, k in zip(hdr['tensors'], sd):
        if t['q']:
            v = sd[k]; s = np.abs(v).max(axis=1) / 127.0; s[s == 0] = 1
            m.state_dict()[k].copy_(torch.tensor(np.clip(np.round(v / s[:, None]), -127, 127) * s[:, None]))
    pairs = [l.rstrip('\n').split('\t') for l in open(sys.argv[3] + '.in')]
    with open(sys.argv[3], 'w') as f, torch.no_grad():
        for a, b in pairs:
            e = tok(a, b, truncation=True, max_length=96, return_tensors='pt')
            p = torch.softmax(m(**e).logits, -1)[0, 1].item()
            f.write(json.dumps({'a': a, 'b': b, 'ids': e['input_ids'][0].tolist(), 'p': p}) + '\n')

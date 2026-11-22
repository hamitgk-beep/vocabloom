"""Task 5E, stage 3: scores every candidate meaning the engine considered, with one model, on dumped rows.

usage: python3 tools/nlp_research/score_senses.py MODEL_KEY DUMP_DIR OUT_DIR SET [SET ...]

Writes OUT_DIR/MODEL_KEY/SET.json: for each row, a list of scores (or null) in the order of row['cands'], plus the
model's wall time. Nothing leaves the machine: the models are loaded from the local Hugging Face cache.
Sense rows (WSD) and MAGPIE rows are both handled; for MAGPIE the candidates are the idiom's senses and the
word-by-word readings.
"""
import json, os, sys, time

import torch

torch.set_num_threads(4)
MODELS = {
    # key: (kind, Hugging Face id)
    'minilm': ('bi', 'sentence-transformers/all-MiniLM-L6-v2'),
    'bge_small': ('bi', 'BAAI/bge-small-en-v1.5'),
    'mpnet': ('bi', 'sentence-transformers/all-mpnet-base-v2'),
    'mminilm': ('bi', 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2'),
    'ce_marco': ('ce', 'cross-encoder/ms-marco-MiniLM-L6-v2'),
    'ce_bge': ('ce', 'BAAI/bge-reranker-base'),
    'ce_stsb': ('ce', 'cross-encoder/stsb-roberta-base'),
    'nli_xsmall': ('nli', 'cross-encoder/nli-deberta-v3-xsmall'),
    'glossbert': ('glossbert', 'kanishka/GlossBERT'),
}


def marked(row):
    s = row['sentence']
    if 'start' in row:
        a, b = row['start'], row['end']
    else:
        a, b = row['span']
    return s[:a] + '"' + s[a:b] + '"' + s[b:], s[a:b]


def gloss(c, multilingual):
    lemma = c['lemma']
    if c.get('en'):
        g = f"{lemma}: {c['en']}"
        if c.get('ex'):
            g += f" (e.g. {c['ex'][0]})"
        return g
    if c.get('ex'):
        return f"{lemma}: e.g. {' / '.join(c['ex'])}"
    if multilingual and c.get('tr'):
        return f"{lemma}: {', '.join(c['tr'][:3])}"
    return None


def main():
    key, dump, out, sets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    kind, hf = MODELS[key]
    os.makedirs(f'{out}/{key}', exist_ok=True)
    t0 = time.time()
    if kind == 'bi':
        from sentence_transformers import SentenceTransformer
        m = SentenceTransformer(hf, device='cpu', cache_folder='/root/work/hf', local_files_only=True)
    elif kind in ('ce', 'nli'):
        from sentence_transformers import CrossEncoder
        m = CrossEncoder(hf, device='cpu', cache_folder='/root/work/hf', local_files_only=True)
    else:
        from transformers import AutoTokenizer, BertForSequenceClassification
        from huggingface_hub import snapshot_download
        import glob
        p = sorted(glob.glob(f"/root/work/hf/models--{hf.replace('/', '--')}/snapshots/*"))[-1]
        tok = AutoTokenizer.from_pretrained(p)
        m = BertForSequenceClassification.from_pretrained(p).eval()
    load_s = time.time() - t0
    for name in sets:
        rows = [json.loads(l) for l in open(f'{dump}/{name}.engine.jsonl', encoding='utf-8')]
        t1 = time.time()
        pairs, where = [], []
        for ri, r in enumerate(rows):
            for ci, c in enumerate(r.get('cands') or []):
                g = gloss(c, key == 'mminilm')
                if g is None:
                    continue
                ctx, w = marked(r)
                pairs.append((ctx if kind != 'bi' else r['sentence'], g, w))
                where.append((ri, ci))
        scores = [[None] * len(r.get('cands') or []) for r in rows]
        if kind == 'bi':
            prefix = 'Represent this sentence for searching relevant passages: ' if key == 'bge_small' else ''
            sents = sorted({p[0] for p in pairs})
            gl = sorted({p[1] for p in pairs})
            es = dict(zip(sents, m.encode([prefix + s for s in sents], batch_size=32, normalize_embeddings=True, convert_to_tensor=True)))
            eg = dict(zip(gl, m.encode(gl, batch_size=32, normalize_embeddings=True, convert_to_tensor=True)))
            vals = [float(es[s] @ eg[g]) for s, g, _ in pairs]
        elif kind == 'ce':
            vals = [float(x) for x in m.predict([(s, g) for s, g, _ in pairs], batch_size=32)]
        elif kind == 'nli':
            # premise: the sentence; hypothesis: the meaning. Labels: contradiction, entailment, neutral.
            logits = m.predict([(s, f'In this sentence, "{w}" means {g.split(": ", 1)[1]}') for s, g, w in pairs], batch_size=32)
            lab = {v.lower(): int(k) for k, v in m.model.config.id2label.items()}
            vals = [float(x[lab['entailment']] - x[lab['contradiction']]) for x in logits]
        else:
            vals = []
            with torch.no_grad():
                for i in range(0, len(pairs), 32):
                    b = pairs[i:i + 32]
                    enc = tok([s for s, _, _ in b], [g.replace(': ', ' : ', 1) for _, g, _ in b], padding=True, truncation=True,
                              max_length=160, return_tensors='pt')
                    lg = m(**enc).logits
                    vals += (lg[:, 1] - lg[:, 0]).tolist()
        for (ri, ci), v in zip(where, vals):
            scores[ri][ci] = v
        secs = time.time() - t1
        json.dump({'model': hf, 'kind': kind, 'load_s': load_s, 'secs': secs, 'pairs': len(pairs), 'rows': len(rows), 'scores': scores},
                  open(f'{out}/{key}/{name}.json', 'w'))
        print(key, name, f'{len(pairs)} pairs, {secs:.1f}s', flush=True)


if __name__ == '__main__':
    main()

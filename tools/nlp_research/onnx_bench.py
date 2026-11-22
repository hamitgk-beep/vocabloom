"""Task 5E, stage 5: ONNX export, int8 quantization and CPU benchmarks with ONNX Runtime (Python side).

usage: python3 tools/nlp_research/onnx_bench.py OUT_DIR PAIRS_TSV

For each model: export to ONNX when the Hugging Face repository has no ONNX file (torch.onnx), quantize the
weights to int8 (onnxruntime.quantization.quantize_dynamic), then for fp32 and int8: file size, session load time,
time per pair with 1 and 2 threads, peak memory of a fresh process, and agreement of the int8 scores with fp32 on
PAIRS_TSV (sentence <TAB> meaning). spaCy is tried too: its thinc models have no ONNX exporter (reported).
"""
import json, os, subprocess, sys, time

out, pairs_path = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
import glob


def snapshot_download(hf, **_):
    """The local Hugging Face cache folder of [hf] (the models were downloaded before; no network here)."""
    return sorted(glob.glob(f"/root/work/hf/models--{hf.replace('/', '--')}/snapshots/*"))[-1]

MODELS = {
    'minilm': ('sentence-transformers/all-MiniLM-L6-v2', 'bi'),
    'bge_small': ('BAAI/bge-small-en-v1.5', 'bi'),
    'ce_marco': ('cross-encoder/ms-marco-MiniLM-L6-v2', 'cross'),
    'nli_xsmall': ('cross-encoder/nli-deberta-v3-xsmall', 'cross'),
    'glossbert': ('kanishka/GlossBERT', 'cross'),
}
pairs = [l.rstrip('\n').split('\t') for l in open(pairs_path, encoding='utf-8') if '\t' in l]

BENCH = r'''
import json, sys, time, resource, numpy as np, onnxruntime as ort
from tokenizers import Tokenizer
path, tokp, kind, threads, pairs_path = sys.argv[1:6]
rss0 = round(int([l for l in open('/proc/self/status') if l.startswith('VmRSS')][0].split()[1]) / 1024)
t0 = time.time()
so = ort.SessionOptions(); so.intra_op_num_threads = int(threads); so.inter_op_num_threads = 1
s = ort.InferenceSession(path, so, providers=['CPUExecutionProvider'])
load = time.time() - t0
tok = Tokenizer.from_file(tokp)
tok.enable_truncation(128)
names = [i.name for i in s.get_inputs()]
pairs = [l.rstrip('\n').split('\t') for l in open(pairs_path, encoding='utf-8') if '\t' in l]
def feed(enc):
    d = {'input_ids': np.array([enc.ids], dtype=np.int64), 'attention_mask': np.array([enc.attention_mask], dtype=np.int64)}
    if 'token_type_ids' in names: d['token_type_ids'] = np.array([enc.type_ids], dtype=np.int64)
    return d
scores, times = [], []
for a, b in pairs:
    t = time.time()
    if kind == 'bi':
        vs = []
        for x in (a, b):
            e = tok.encode(x); h = s.run(None, feed(e))[0][0]
            v = h.mean(0); vs.append(v / np.linalg.norm(v))
        scores.append(float(vs[0] @ vs[1]))
    else:
        e = tok.encode(a, b); lg = s.run(None, feed(e))[0][0]
        scores.append(float(lg[0]) if len(lg) == 1 else float(lg[-1] - lg[0]) if len(lg) == 2 else float(lg[1] - lg[0]))
    times.append(time.time() - t)
times.sort()
print(json.dumps({'load_ms': round(1000 * load), 'median_ms': round(1000 * times[len(times) // 2], 2),
                  'p95_ms': round(1000 * times[int(len(times) * 0.95)], 2),
                  'peak_rss_mb': round(int([l for l in open('/proc/self/status') if l.startswith('VmHWM')][0].split()[1]) / 1024),
                  'rss_before_session_mb': rss0, 'scores': scores}))
'''


def export(hf, kind, dst):
    import torch
    from transformers import AutoModel, AutoModelForSequenceClassification, AutoTokenizer
    p = snapshot_download(hf, cache_dir='/root/work/hf', local_files_only=True)
    tok = AutoTokenizer.from_pretrained(p)
    m = (AutoModel if kind == 'bi' else AutoModelForSequenceClassification).from_pretrained(p).eval()
    enc = tok('a sentence', 'a meaning', return_tensors='pt')
    names = [k for k in ('input_ids', 'attention_mask', 'token_type_ids') if k in enc]
    dyn = {k: {0: 'b', 1: 't'} for k in names}
    out_name = 'last_hidden_state' if kind == 'bi' else 'logits'
    dyn[out_name] = {0: 'b'} if kind != 'bi' else {0: 'b', 1: 't'}
    torch.onnx.export(m, tuple(enc[k] for k in names), dst, input_names=names, output_names=[out_name], dynamic_axes=dyn,
                      opset_version=17, dynamo=False)
    return p


def main():
    from onnxruntime.quantization import quantize_dynamic, QuantType
    res = {}
    for key, (hf, kind) in MODELS.items():
        d = f'{out}/{key}'
        os.makedirs(d, exist_ok=True)
        p = snapshot_download(hf, cache_dir='/root/work/hf', local_files_only=True)
        fp32 = f'{d}/model.onnx'
        how = 'Hugging Face onnx/model.onnx'
        if not os.path.exists(fp32):
            src = os.path.join(p, 'onnx', 'model.onnx')
            if os.path.exists(src):
                os.symlink(src, fp32)
            else:
                t = time.time()
                export(hf, kind, fp32)
                how = f'exported here with torch.onnx (opset 17) in {time.time() - t:.0f}s'
        q8 = f'{d}/model_int8.onnx'
        if not os.path.exists(q8):
            quantize_dynamic(fp32, q8, weight_type=QuantType.QInt8)
        tokp = os.path.join(p, 'tokenizer.json')
        if not os.path.exists(tokp):
            from transformers import AutoTokenizer
            AutoTokenizer.from_pretrained(p).save_pretrained(f'{d}/tok')
            tokp = f'{d}/tok/tokenizer.json'
        r = {'hf': hf, 'kind': kind, 'onnx_source': how}
        for name, path in (('fp32', fp32), ('int8', q8)):
            for th in (1, 2):
                o = subprocess.run([sys.executable, '-c', BENCH, path, tokp, kind, str(th), pairs_path], capture_output=True, text=True)
                if o.returncode != 0:
                    r[f'{name}_t{th}'] = {'error': o.stderr[-400:]}
                    continue
                j = json.loads(o.stdout.strip().splitlines()[-1])
                r[f'{name}_t{th}'] = {k: v for k, v in j.items() if k != 'scores'}
                r[f'{name}_scores'] = j['scores']
            r[f'{name}_mb'] = round(os.path.getsize(os.path.realpath(path)) / 1e6, 1)
        if 'fp32_scores' in r and 'int8_scores' in r:
            import numpy as np
            a, b = np.array(r.pop('fp32_scores')), np.array(r.pop('int8_scores'))
            r['int8_vs_fp32_pearson'] = round(float(np.corrcoef(a, b)[0, 1]), 4)
            r['int8_vs_fp32_max_abs_diff'] = round(float(np.abs(a - b).max()), 4)
        res[key] = r
        print(key, json.dumps(r), flush=True)
    # spaCy: no exporter.
    try:
        import spacy, thinc  # noqa
        res['spacy'] = {'onnx': 'no exporter: spaCy/thinc have no ONNX export (checked thinc ' + thinc.__version__ + ', spaCy ' + spacy.__version__ +
                        '); the sm/md pipelines are thinc (HashEmbed + CNN) plus rule and lookup lemmatizers; only the trf model\'s '
                        'RoBERTa part could be exported with torch.onnx, without spaCy\'s tagger / parser heads.'}
    except Exception as e:  # pragma: no cover
        res['spacy'] = {'onnx': str(e)}
    json.dump(res, open(f'{out}/onnx_bench.json', 'w'), indent=1)


if __name__ == '__main__':
    main()

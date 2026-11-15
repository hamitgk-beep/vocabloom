"""Export EMA Lightning (canberk7, Apache-2.0 code and weights) to the three ONNX graphs the app runs
(lib/tts/ema.dart), for one sentence at a time; check them against PyTorch and time them with
onnxruntime. Writes OUT/{text,sound,decoder}.onnx and OUT/config.json.
Needs: pip install torch ema-lightning onnx onnxruntime huggingface_hub"""
import os, sys, json, time
import numpy as np, torch, onnxruntime as ort
from huggingface_hub import hf_hub_download
from ema_lightning.model import load_acoustic
from ema_lightning.decoder import load_decoder

OUT = sys.argv[1] if len(sys.argv) > 1 else 'ema-onnx'; os.makedirs(OUT, exist_ok=True)
R = 'canberkkkkkk/ema-lightning'
am = load_acoustic(hf_hub_download(R, 'ema.pt'), 'cpu'); dec = load_decoder(hf_hub_download(R, 'decoder.pt'), 'cpu')

torch.expm1 = lambda x: torch.exp(x) - 1  # no ONNX op for expm1

class Text(torch.nn.Module):
    def forward(self, ids):
        return am.text_stage(ids, ids != 0)
class Sound(torch.nn.Module):
    def forward(self, h, dur, cw, wstart, fw, fp, noise):
        L, T = cw.shape[1], fw.shape[1]
        return am.sound_stage(h, dur, torch.ones(1, L, dtype=torch.bool), cw, wstart, fw, fp,
                              torch.ones(1, T, dtype=torch.bool), noise)
class Dec(torch.nn.Module):
    def forward(self, z):
        return dec(z.transpose(1, 2), None)

L, T, S, C = 20, 60, len(am.times), am.latent_dim
ids = torch.randint(2, len(am.vocab), (1, L))
h, dur = am.text_stage(ids, ids != 0)
cw = torch.tensor([[i // 5 for i in range(L)]]); ws = torch.tensor([[(i // 5) * 5 for i in range(L)]])
fw = torch.tensor([[i * 4 // T for i in range(T)]]); fp = torch.rand(1, T)
noise = torch.randn(1, S, T, C)
z = Sound()(h, dur, cw, ws, fw, fp, noise)
kw = dict(opset_version=17, do_constant_folding=True, dynamo=False)
torch.onnx.export(Text(), (ids,), f'{OUT}/text.onnx', input_names=['ids'], output_names=['h', 'dur'],
                  dynamic_axes={'ids': {1: 'L'}, 'h': {1: 'L'}, 'dur': {1: 'L'}}, **kw)
torch.onnx.export(Sound(), (h, dur, cw, ws, fw, fp, noise), f'{OUT}/sound.onnx',
                  input_names=['h', 'dur', 'cw', 'wstart', 'fw', 'fp', 'noise'], output_names=['z'],
                  dynamic_axes={'h': {1: 'L'}, 'dur': {1: 'L'}, 'cw': {1: 'L'}, 'wstart': {1: 'L'},
                                'fw': {1: 'T'}, 'fp': {1: 'T'}, 'noise': {2: 'T'}, 'z': {1: 'T'}}, **kw)
torch.onnx.export(Dec(), (z,), f'{OUT}/decoder.onnx', input_names=['z'], output_names=['audio'],
                  dynamic_axes={'z': {1: 'T'}, 'audio': {1: 'N'}}, **kw)
json.dump({'vocab': list(am.vocab), 'times': am.times, 'latent_dim': C, 'hop': dec.hop, 'sample_rate': 48000,
           'max_word_frames': 250, 'source': 'EMA Lightning (canberkkkkkk/ema-lightning), Apache-2.0'},
          open(f'{OUT}/config.json', 'w'), ensure_ascii=False)

# Check with other shapes than the export ones.
L2, T2 = 33, 140
ids2 = torch.randint(2, len(am.vocab), (1, L2)); cw2 = torch.tensor([[i // 6 for i in range(L2)]])
ws2 = torch.tensor([[(i // 6) * 6 for i in range(L2)]]); fw2 = torch.tensor([[i * 6 // T2 for i in range(T2)]])
fp2 = torch.rand(1, T2); n2 = torch.randn(1, S, T2, C)
with torch.no_grad():
    h2, d2 = am.text_stage(ids2, ids2 != 0); z2 = Sound()(h2, d2, cw2, ws2, fw2, fp2, n2); a2 = Dec()(z2)
for th in (1, 4):
    o = ort.SessionOptions(); o.intra_op_num_threads = th; o.inter_op_num_threads = 1
    st, ss, sd = (ort.InferenceSession(f'{OUT}/{n}.onnx', o, providers=['CPUExecutionProvider']) for n in ('text', 'sound', 'decoder'))
    t0 = time.time(); oh, od = st.run(None, {'ids': ids2.numpy()}); t1 = time.time()
    oz, = ss.run(None, {'h': oh, 'dur': od, 'cw': cw2.numpy(), 'wstart': ws2.numpy(), 'fw': fw2.numpy(), 'fp': fp2.numpy(), 'noise': n2.numpy()}); t2 = time.time()
    oa, = sd.run(None, {'z': oz}); t3 = time.time()
    secs = T2 / 25
    print(f'ort {th}t: text {1000*(t1-t0):.0f}ms sound {1000*(t2-t1):.0f}ms decoder {1000*(t3-t2):.0f}ms for {secs:.1f}s audio, rtf {(t3-t0)/secs:.3f}; '
          f'diff h {np.abs(oh-h2.numpy()).max():.2e} z {np.abs(oz-z2.numpy()).max():.2e} audio {np.abs(oa-a2.numpy()).max():.2e}', flush=True)
for n in ('text', 'sound', 'decoder'):
    print(n, os.path.getsize(f'{OUT}/{n}.onnx') // 1024, 'KB')

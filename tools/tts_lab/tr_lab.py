"""Temporary: compare Turkish voices on an ARM CPU (speed, Whisper word error rate, UTMOS)."""
import os, re, sys, time, glob, json, traceback
import numpy as np, soundfile as sf, torch

OUT = os.environ.get('OUT', 'out'); os.makedirs(OUT, exist_ok=True)
S = ["Öğrenmek için her gün biraz okumalısın.",
     "Kapının önünde küçük bir kedi oturuyordu.",
     "Yarın sabah erkenden yola çıkacağız.",
     "Bu kitabı geçen yaz büyükannemin evinde okudum.",
     "Hava kararınca çocuklar eve döndü.",
     "Öğretmen sorunun cevabını tahtaya yazdı.",
     "Pencereden içeri serin bir rüzgâr esiyordu.",
     "Kardeşim her akşam piyano çalışıyor.",
     "Trenin kalkmasına sadece birkaç dakika kalmıştı.",
     "Sessizce kapıyı açtı ve odaya girdi.",
     "Bu kelimenin anlamını sözlükte buldum.",
     "Deniz kenarında uzun bir yürüyüş yaptık.",
     "Annesi ona sıcak bir çorba hazırladı.",
     "Şehrin ışıkları uzaktan parlıyordu.",
     "Gülümsedi ama hiçbir şey söylemedi.",
     "Kütüphanede saatlerce ders çalıştılar."]
W = ["bisiklet", "rağmen", "çekmece", "şemsiye", "öğretmen", "ağaç", "kelebek", "pencere", "gözlük", "yağmur",
     "kitap", "uçurtma", "değil", "fakat", "çünkü", "büyük", "kahvaltı", "ılık", "dün", "yavaşça"]

from faster_whisper import WhisperModel
asr = WhisperModel('small', device='cpu', compute_type='int8', cpu_threads=4)
def rec(x, sr):
    if sr != 16000:
        import scipy.signal as ss; x = ss.resample_poly(x, 16000, sr)
    segs, _ = asr.transcribe(x.astype(np.float32), language='tr', beam_size=5, vad_filter=False)
    return ' '.join(s.text for s in segs)
def norm(s):
    s = s.replace('İ', 'i').replace('I', 'ı').lower().replace('â', 'a')
    return re.sub(r"[^a-zçğıöşü ]", ' ', s).split()
def wer(ref, hyp):
    r, h = norm(ref), norm(hyp); d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        p, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (r[i - 1] != h[j - 1]))
    return d[len(h)], len(r)
try:
    mos = torch.hub.load("tarepan/SpeechMOS:v1.2.0", "utmos22_strong", trust_repo=True)
except Exception as e:
    print('no UTMOS', e); mos = None
def utmos(x, sr):
    if mos is None: return float('nan')
    with torch.no_grad(): return float(mos(torch.from_numpy(x.astype(np.float32))[None], sr))

def evaluate(name, gen, threads):
    torch.set_num_threads(threads)
    gen('Merhaba.')  # warm
    E = N = 0; T = A = 0.0; bad = 0; ms = []; shown = []
    for i, s in enumerate(S):
        t = time.time(); x, sr = gen(s); T += time.time() - t; A += len(x) / sr
        h = rec(x, sr); e, n = wer(s, h); E += e; N += n; bad += e >= 2
        if e: shown.append(f'{s} -> {h.strip()}')
        ms.append(utmos(x, sr))
        if i < 4 and threads == 4: sf.write(f'{OUT}/{name}_{i}.wav', x, sr)
    ok = 0; wt = []
    lead, lsr = gen('Kelime şu:')
    for w in W:
        t = time.time(); x, sr = gen(w.capitalize() + '.'); wt.append(time.time() - t)
        if sr != lsr: x = np.interp(np.arange(0, len(x), sr / lsr), np.arange(len(x)), x)
        h = rec(np.concatenate([lead, np.zeros(int(0.3 * lsr)), x, np.zeros(int(0.3 * lsr))]), lsr)
        ws = norm(h); good = bool(ws) and ws[-1] == norm(w)[0]; ok += good
        if not good: shown.append(f'word {w} -> {h.strip()}')
    wt.sort()
    print(f'{name} @{threads}t: WER {100*E/N:.1f}% ({E}/{N}) bad {bad}/{len(S)} | words {ok}/{len(W)} p90 {1000*wt[int(len(wt)*.9)]:.0f}ms | rtf {T/A:.3f} | utmos {np.nanmean(ms):.2f}', flush=True)
    for l in shown[:8]: print('   ', l)

engines = {}
piper = {}
# Piper baselines (sherpa-onnx 1.13.8)
import sherpa_onnx as so
for v in sys.argv[1:] or ['fahrettin', 'fettah', 'dfki']:
    d = f'models/vits-piper-tr_TR-{v}-medium'
    if not os.path.isdir(d): continue
    m = glob.glob(d + '/*.onnx')[0]
    def mk(th, d=d, m=m):
        t = so.OfflineTts(so.OfflineTtsConfig(model=so.OfflineTtsModelConfig(vits=so.OfflineTtsVitsModelConfig(model=m, tokens=d + '/tokens.txt', data_dir=d + '/espeak-ng-data'), num_threads=th)))
        def g(s):
            a = t.generate(s, sid=0, speed=1.0); return np.array(a.samples, dtype=np.float32), a.sample_rate
        return g
    piper['piper-' + v] = mk
try:
    # EMA Lightning run stage by stage (the path an app would export), batch 1, no worker threads.
    from huggingface_hub import hf_hub_download
    from ema_lightning.model import load_acoustic
    from ema_lightning.decoder import load_decoder
    from ema_lightning.frontend import Frontend
    from itertools import pairwise
    R = 'canberkkkkkk/ema-lightning'
    am = load_acoustic(hf_hub_download(R, 'ema.pt'), 'cpu'); dec = load_decoder(hf_hub_download(R, 'decoder.pt'), 'cpu')
    fe = Frontend(am.vocab)
    print('ema vocab', len(am.vocab), 'times', am.times, 'hop', dec.hop, flush=True)
    @torch.no_grad()
    def ema_say(text, seed=1, speed=1.0):
        t = fe(text)
        ids = torch.tensor([[am.stoi.get(c, 1) for c in t]])
        starts = [i for i, ch in enumerate(t) if ch != ' ' and (i == 0 or t[i - 1] == ' ')] or [0]
        bounds = [0] + starts[1:] + [len(t)]; cw, ws = [], []
        for w, (a, b) in enumerate(pairwise(bounds)): cw += [w] * (b - a); ws += [a] * (b - a)
        cw = torch.tensor([cw]); ws = torch.tensor([ws]); mask = ids != 0
        h, dur = am.text_stage(ids, mask); dur = dur / speed
        n = torch.zeros_like(dur).scatter_add_(1, cw, dur).round().clamp(1, 250).long()[0, :int(cw[0, -1]) + 1]
        fw = torch.repeat_interleave(torch.arange(n.numel()), n)
        fp = ((torch.arange(fw.numel()) - (n.cumsum(0) - n)[fw]).double() / n[fw].double()).float()
        g = torch.Generator().manual_seed(seed)
        noise = torch.randn((1, len(am.times), fw.numel(), am.latent_dim), generator=g)
        z = am.sound_stage(h, dur, mask, cw, ws, fw[None], fp[None], torch.ones(1, fw.numel(), dtype=torch.bool), noise)
        a = dec(z.transpose(1, 2), None)[0].numpy()
        return a, 48000
    engines['ema'] = lambda th: ema_say
except Exception:
    traceback.print_exc()
try:
    from huggingface_hub import snapshot_download
    p = snapshot_download('ozgurguler/ahenk-cep-tr'); sys.path.insert(0, p)
    print('ahenk files', os.listdir(p), os.listdir(os.path.join(p, 'onnx')) if os.path.isdir(os.path.join(p, 'onnx')) else '')
    import ahenk_cep, inspect
    print(inspect.signature(ahenk_cep.AhenkCep))
    ac = ahenk_cep.AhenkCep(os.path.join(p, 'student.pt'), os.path.join(p, 'decoder.pt'))
    for steps in (16, 8):
        def ac_g(th, steps=steps):
            def g(s):
                a, sr = ac.say(s, steps=steps, seed=1); a = np.asarray(a, dtype=np.float32).reshape(-1)
                return a, sr
            return g
        engines[f'ahenk{steps}'] = ac_g
except Exception:
    traceback.print_exc()

engines.update(piper)
for name, mk in engines.items():
    for th in (1, 4):
        try: evaluate(name, mk(th), th)
        except Exception: traceback.print_exc()

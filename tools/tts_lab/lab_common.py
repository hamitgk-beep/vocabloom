import sherpa_onnx as so, soundfile as sf, numpy as np, re, sys, time, json
import os
M=os.environ.get('MODELS','/root/models')
S=[
"Although it was raining heavily all morning, she decided to walk to the old library on the hill.",
"Harry looked at Hermione and smiled, but he didn't say a word.",
"The train left the station at seven o'clock, and nobody noticed the little boy in the last carriage.",
"\"Where have you been?\" his mother asked, holding the door open.",
"It was the best of times, it was the worst of times.",
"He opened the letter slowly, afraid of what it might say.",
"They grow tomatoes, beans and potatoes in the garden behind the house.",
"Through the window, she could see the lights of the city shining in the distance.",
"If you want to learn a language, you have to read every day.",
"The old man thought about his daughter, who lived far away in another country.",
"Suddenly, the dog started barking, and everyone in the room jumped.",
"Would you like some tea, or would you rather have a glass of water?",
]
NUM={'1':'one','2':'two','3':'three','4':'four','5':'five','6':'six','7':'seven','8':'eight','9':'nine','10':'ten'}
def norm(t): return [NUM.get(w,w) for w in re.sub(r"[^a-z0-9' ]"," ",t.lower().replace("o'clock","oclock").replace("o'clock","oclock")).split()]
def wer(ref,hyp):
  r,h=norm(ref),norm(hyp); d=list(range(len(h)+1))
  for i in range(1,len(r)+1):
    p=d[:]; d[0]=i
    for j in range(1,len(h)+1): d[j]=min(p[j]+1,d[j-1]+1,p[j-1]+(r[i-1]!=h[j-1]))
  return d[-1],len(r)
W=M+'/sherpa-onnx-whisper-base'
asr=so.OfflineRecognizer.from_whisper(encoder=W+'/base-encoder.int8.onnx',decoder=W+'/base-decoder.int8.onnx',tokens=W+'/base-tokens.txt',language='en',num_threads=4)
def rec(a,sr):
  if False:
    import scipy.signal as ss; a=ss.resample_poly(a,16000,sr).astype(np.float32); sr=16000
  st=asr.create_stream(); st.accept_waveform(sr,a); asr.decode_stream(st); return st.result.text
def supertonic(threads=1, q=None):
  # q: dict part->'int8'|'fp32'
  d=M+'/sherpa-onnx-supertonic-tts-int8-2026-03-06'; f=M+'/supertonic-fp32'
  q=q or {}
  pth=lambda n: (f'{f}/{n}.onnx' if q.get(n)=='fp32' else f'{d}/{n}.int8.onnx')
  c=so.OfflineTtsConfig(model=so.OfflineTtsModelConfig(supertonic=so.OfflineTtsSupertonicModelConfig(pth('duration_predictor'),pth('text_encoder'),pth('vector_estimator'),pth('vocoder'),d+'/tts.json',d+'/unicode_indexer.bin',d+'/voice.bin'),num_threads=threads))
  return so.OfflineTts(c)
def kokoro(threads=1, q='int8'):
  d=M+'/kokoro-int8-multi-lang-v1_0'
  import glob; m=glob.glob(d+'/model*.onnx')[0]
  c=so.OfflineTtsConfig(model=so.OfflineTtsModelConfig(kokoro=so.OfflineTtsKokoroModelConfig(model=m,voices=d+'/voices.bin',tokens=d+'/tokens.txt',data_dir=d+'/espeak-ng-data',lexicon=d+'/lexicon-us-en.txt'),num_threads=threads))
  return so.OfflineTts(c)
def run(name,tts,gen,out=None,show=False,reps=1):
  E=N=0; T=A=0; bad=0
  for i,s in enumerate(S*reps):
    t=time.time(); a=gen(tts,s); T+=time.time()-t
    x=np.array(a.samples,dtype=np.float32); A+=len(x)/a.sample_rate
    h=rec(x,a.sample_rate); e,n=wer(s,h); E+=e; N+=n; bad+=e>=2
    if out: sf.write(f'{out}_{i}.wav',x,a.sample_rate)
    if show and e: print('   ',e,'|',s,'\n     ->',h)
  print(f'{name}: WER {100*E/N:.1f}% ({E}/{N}), sentences with 2+ errors {bad}/{len(S)*reps}, rtf {T/A:.2f}',flush=True)

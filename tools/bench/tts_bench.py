import sherpa_onnx as so, time, sys, os, soundfile as sf
M=sys.argv[1]; threads=int(sys.argv[2]); which=sys.argv[3:] 
W="and"; S="Although it was raining heavily, she decided to walk to the old library because she wanted to finish the book."
def kokoro(d,model):
  return so.OfflineTtsModelConfig(kokoro=so.OfflineTtsKokoroModelConfig(model=f'{d}/{model}',voices=f'{d}/voices.bin',tokens=f'{d}/tokens.txt',data_dir=f'{d}/espeak-ng-data',lexicon=f'{d}/lexicon-us-en.txt'),num_threads=threads)
cfgs={
 'kokoro-int8': lambda: kokoro(f'{M}/kokoro-int8-multi-lang-v1_0','model.int8.onnx'),
 'kokoro-fp32': lambda: kokoro(f'{M}/kokoro-multi-lang-v1_0','model.onnx'),
 'supertonic': lambda: so.OfflineTtsModelConfig(supertonic=so.OfflineTtsSupertonicModelConfig(**{k:f'{M}/sherpa-onnx-supertonic-tts-int8-2026-03-06/{v}' for k,v in dict(duration_predictor='duration_predictor.int8.onnx',text_encoder='text_encoder.int8.onnx',vector_estimator='vector_estimator.int8.onnx',vocoder='vocoder.int8.onnx',tts_json='tts.json',unicode_indexer='unicode_indexer.bin',voice_style='voice.bin').items()}),num_threads=threads),
 'kitten': lambda: so.OfflineTtsModelConfig(kitten=so.OfflineTtsKittenModelConfig(model=f'{M}/kitten-nano-en-v0_2-fp16/model.fp16.onnx',voices=f'{M}/kitten-nano-en-v0_2-fp16/voices.bin',tokens=f'{M}/kitten-nano-en-v0_2-fp16/tokens.txt',data_dir=f'{M}/kitten-nano-en-v0_2-fp16/espeak-ng-data'),num_threads=threads),
 'piper-tr': lambda: so.OfflineTtsModelConfig(vits=so.OfflineTtsVitsModelConfig(model=f'{M}/vits-piper-tr_TR-fahrettin-medium/tr_TR-fahrettin-medium.onnx',tokens=f'{M}/vits-piper-tr_TR-fahrettin-medium/tokens.txt',data_dir=f'{M}/vits-piper-tr_TR-fahrettin-medium/espeak-ng-data'),num_threads=threads),
}
for name in which:
  t=time.time(); tts=so.OfflineTts(so.OfflineTtsConfig(model=cfgs[name]())); load=time.time()-t
  r=[]
  for txt in [W,W,S]:
    t=time.time(); a=tts.generate(txt,sid=0,speed=1.0); el=time.time()-t; dur=len(a.samples)/max(1,a.sample_rate); r.append((el,dur))
  sf.write(f'/tmp/{name}.wav',a.samples,a.sample_rate)
  print(f'{name:12s} thr={threads} load={load:.1f}s word1={r[0][0]:.2f}s word2={r[1][0]:.2f}s sent={r[2][0]:.2f}s/{r[2][1]:.1f}s RTF={r[2][0]/max(r[2][1],.01):.2f}', flush=True)

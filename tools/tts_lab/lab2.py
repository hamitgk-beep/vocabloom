import os, glob
from lab_common import *
th=int(os.environ.get('TH','1'))
def kok(d):
  m=sorted(glob.glob(d+'/model*.onnx'))[0]
  lex=','.join(x for x in [d+'/lexicon-us-en.txt'] if os.path.exists(x))
  c=so.OfflineTtsConfig(model=so.OfflineTtsModelConfig(kokoro=so.OfflineTtsKokoroModelConfig(model=m,voices=d+'/voices.bin',tokens=d+'/tokens.txt',data_dir=d+'/espeak-ng-data',lexicon=lex),num_threads=th))
  return so.OfflineTts(c)
def kit(d):
  m=sorted(glob.glob(d+'/model*.onnx'))[0]
  c=so.OfflineTtsConfig(model=so.OfflineTtsModelConfig(kitten=so.OfflineTtsKittenModelConfig(model=m,voices=d+'/voices.bin',tokens=d+'/tokens.txt',data_dir=d+'/espeak-ng-data'),num_threads=th))
  return so.OfflineTts(c)
for name,make in [('kokoro multi v1.0 fp32',lambda:kok(M+'/kokoro-multi-lang-v1_0')),('kokoro multi v1.0 int8',lambda:kok(M+'/kokoro-int8-multi-lang-v1_0')),('kokoro en v0.19',lambda:kok(M+'/kokoro-en-v0_19')),
  ('kitten nano v0.2',lambda:kit(M+'/kitten-nano-en-v0_2-fp16')),('kitten mini v0.1',lambda:kit(M+'/kitten-mini-en-v0_1-fp16'))]:
  try: t=make()
  except Exception as e: print(name,'load failed',e,flush=True); continue
  for sid in [0,5]:
    run(f'{name} sid={sid}',t,lambda t,s,sid=sid:t.generate(s,sid=sid,speed=1.0),show=True)
  del t

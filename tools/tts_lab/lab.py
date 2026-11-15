import os, sys
from lab_common import *
th=int(os.environ.get('TH','1'))
R=3
variants=[('int8 (current)',{}),('fp32 all',{k:'fp32' for k in ['duration_predictor','text_encoder','vector_estimator','vocoder']}),
 ('fp32 vector_estimator',{'vector_estimator':'fp32'}),('fp32 duration+text',{'duration_predictor':'fp32','text_encoder':'fp32'})]
for name,q in variants:
  try: st=supertonic(th,q)
  except Exception as e: print(name,'load failed',e); continue
  for steps in [5,8]:
    for sid in [0,5]:
      def g(t,s,steps=steps,sid=sid):
        c=so.GenerationConfig(); c.sid=sid; c.num_steps=steps; c.speed=1.0; return t.generate(s,c)
      run(f'supertonic {name} steps={steps} sid={sid}',st,g,show=True,reps=R)
  del st
k=kokoro(th)
run('kokoro int8 sid=0',k,lambda t,s:t.generate(s,sid=0,speed=1.0),show=True,reps=1)

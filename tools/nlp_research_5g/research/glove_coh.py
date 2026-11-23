import os
import json, sys, re, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cohesion import STOP, lemma, idiom_bag
vocab={}; vecs=[]
with open(os.environ['GLOVE_TXT'],encoding='utf-8') as f:
    for i,l in enumerate(f):
        if i>=200000: break
        p=l.rstrip().split(' '); vocab[p[0]]=len(vecs); vecs.append(np.asarray(p[1:],dtype=np.float32))
V=np.stack(vecs); V/=np.linalg.norm(V,axis=1,keepdims=True)
def vs(ws): 
    ids=[vocab[w] for w in ws if w in vocab]
    return V[ids] if ids else None
def toks(t): return [w.lower() for w in re.findall(r"[A-Za-z]+",t) if w.lower() not in STOP and len(w)>2]
def feats(r):
    comp=[w for w in toks(r['phrase']) if w not in ('someone','something','one')]
    ctx=[w for w in toks(r['sentence']) if w not in comp and lemma(w) not in {lemma(c) for c in comp}]
    I=[w for w in idiom_bag(r['phrase'],r['cat']) if w not in comp]
    C,L,D=vs(ctx),vs(comp),vs(I)
    if C is None or L is None: return None
    sl=(C@L.T).max(1); out={'simL':float(np.sort(sl)[-3:].mean()), 'simLmean':float(sl.mean())}
    if D is not None:
        sd=(C@D.T).max(1); out['simI']=float(np.sort(sd)[-3:].mean()); out['simImean']=float(sd.mean())
    else: out['simI']=out['simImean']=0.0
    out['d']=out['simL']-out['simI']; out['dm']=out['simLmean']-out['simImean']
    return out
if __name__=='__main__':
    for name in sys.argv[1:]:
        rows=[json.loads(l) for l in open(os.environ['OUT5G']+f'/{name}.jsonl')]
        f=[]
        for r in rows:
            if r['found']:
                x=feats(r)
                if x: r['g']=x; f.append(r)
        def auc(key):
            pos=np.array([key(r) for r in f if r['gold']=='literal']); neg=np.array([key(r) for r in f if r['gold']=='idiom'])
            return round(float(((pos[:,None]>neg[None,:]).mean()+0.5*(pos[:,None]==neg[None,:]).mean())),3)
        print(name, len(f), {k:auc(lambda r,k=k:r['g'][k]) for k in ['simL','simLmean','simI','d','dm']})
        json.dump([[r['sentence'],r['g']] for r in f], open(os.environ['OUT5G']+f'/glove_{name}.json','w'))

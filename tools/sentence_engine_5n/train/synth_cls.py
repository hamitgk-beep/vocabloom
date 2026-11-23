"""Train the idiom/literal cross-encoder ONLY on our own synthetic sentences (synth_*.jsonl); held-out synthetic phrases
for a sanity dev score. MAGPIE is used only for evaluation afterwards (cls_eval.py)."""
import json, random, sys, time, glob, re, collections
import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
torch.set_num_threads(int(sys.argv[3]) if len(sys.argv)>3 else 4)
name=sys.argv[1]; out=sys.argv[2]; epochs=int(sys.argv[4]) if len(sys.argv)>4 else 4
rows=[json.loads(l) for f in sorted(glob.glob('synth_*.jsonl')) for l in open(f)]
def mark(s): return re.sub(r'\[\s*([^\]]+?)\s*\]', r'[ \1 ]', s)
def window(s, k):
    w=s.split(); f=next(i for i,x in enumerate(w) if '[' in x); l=max(i for i,x in enumerate(w) if ']' in x)
    return ' '.join(w[max(0,f-k):l+k+1])
WIN=int(sys.argv[6]) if len(sys.argv)>6 else 0
X=[(r['phrase'], mark(r['sentence']), 1 if r['label']=='i' else 0) for r in rows if r['label'] in ('i','l')]
ph=sorted({x[0] for x in X}); rng=random.Random(7); rng.shuffle(ph); dev=set(ph[:100])
tr=[x for x in X if x[0] not in dev]; de=[x for x in X if x[0] in dev]; rng.shuffle(tr)
print('train',len(tr),'dev',len(de),'pos share %.2f'%(sum(x[2] for x in tr)/len(tr)),flush=True)
tok=AutoTokenizer.from_pretrained(name); m=AutoModelForSequenceClassification.from_pretrained(name,num_labels=2)
opt=torch.optim.AdamW(m.parameters(),lr=float(sys.argv[5]) if len(sys.argv)>5 else 5e-5)
w=torch.tensor([sum(x[2] for x in tr)/len(tr), 1-sum(x[2] for x in tr)/len(tr)])*2  # class balance
lossf=torch.nn.CrossEntropyLoss(weight=w)
def ev(D):
    m.eval(); P=[]
    with torch.no_grad():
        for i in range(0,len(D),64):
            b=D[i:i+64]; e=tok([x[0] for x in b],[window(x[1],WIN) if WIN else x[1] for x in b],padding=True,truncation=True,max_length=96,return_tensors='pt')
            P+=torch.softmax(m(**e).logits,-1)[:,1].tolist()
    m.train(); y=[x[2] for x in D]
    L=[p for p,t in zip(P,y) if not t]; I=[p for p,t in zip(P,y) if t]
    return 'acc %.3f lit-rec %.3f idi-rec %.3f'%(sum((p>.5)==bool(t) for p,t in zip(P,y))/len(y), sum(p<=.5 for p in L)/len(L), sum(p>.5 for p in I)/len(I))
m.train(); t0=time.time()
for ep in range(epochs):
    rng.shuffle(tr)
    for i in range(0,len(tr),16):
        b=tr[i:i+16]
        e=tok([x[0] for x in b],[window(x[1], rng.randint(WIN-2,WIN+2)) if WIN else x[1] for x in b],padding=True,truncation=True,max_length=96,return_tensors='pt')
        loss=lossf(m(**e).logits, torch.tensor([x[2] for x in b])); loss.backward(); opt.step(); opt.zero_grad()
    print('epoch',ep,'t=%.0fs'%(time.time()-t0),'dev',ev(de),flush=True)
m.save_pretrained(out); tok.save_pretrained(out)

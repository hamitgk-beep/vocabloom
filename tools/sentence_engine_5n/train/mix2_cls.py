"""Idiom/literal cross-encoder on our synthetic sentences + Claude-labelled public-domain book candidates
(15% of the PD expressions held out as an in-domain check). Windowed input (±WIN words, jittered in training)."""
import json, random, sys, time, glob, re, collections, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
torch.set_num_threads(int(sys.argv[3])); name=sys.argv[1]; out=sys.argv[2]; epochs=int(sys.argv[4]); WIN=6
def mark(s): return re.sub(r'\[\s*([^\]]+?)\s*\]', r'[ \1 ]', s)
def window(s,k):
    w=s.split(); f=next(i for i,x in enumerate(w) if '[' in x); l=max(i for i,x in enumerate(w) if ']' in x)
    return ' '.join(w[max(0,f-k):l+k+1])
syn=[(r['phrase'],mark(r['sentence']),int(r['label']=='i')) for f in sorted(glob.glob('synth_*.jsonl')) for l in open(f) for r in [json.loads(l)] if r['label'] in 'il']
items={x['key']:x for f in ['pg_items.json','pg2_items.json'] for x in json.load(open(f))}
pg=[]
for f in sorted(glob.glob('pg_label_*.jsonl'))+sorted(glob.glob('pg2_label_*.jsonl')):
    for l in open(f):
        r=json.loads(l)
        if r['label'] in 'il': x=items[r['key']]; pg.append((x['phrase'],mark(x['sentence']),int(r['label']=='i'),x['cur'],r['key']))
rng=random.Random(13); hold=set(json.load(open('pg_holdout_phrases.json')))
tr=syn+[x[:3] for x in pg if x[0] not in hold]; de=[x for x in pg if x[0] in hold]
print('train',len(tr),'pg-holdout',len(de),flush=True)
tok=AutoTokenizer.from_pretrained(name); m=AutoModelForSequenceClassification.from_pretrained(name,num_labels=2)
opt=torch.optim.AdamW(m.parameters(),lr=5e-5)
pos=sum(x[2] for x in tr)/len(tr); lossf=torch.nn.CrossEntropyLoss(weight=torch.tensor([pos,1-pos])*2)
def ev():
    m.eval(); P=[]
    with torch.no_grad():
        for i in range(0,len(de),64):
            b=de[i:i+64]; e=tok([x[0] for x in b],[window(x[1],WIN) for x in b],padding=True,truncation=True,max_length=96,return_tensors='pt')
            P+=torch.softmax(m(**e).logits,-1)[:,1].tolist()
    m.train(); y=[x[2] for x in de]; L=[p for p,t in zip(P,y) if not t]; I=[p for p,t in zip(P,y) if t]
    cur=[x[3] in ('sure','likely') for x in de]; cL=[c for c,t in zip(cur,y) if not t]; cI=[c for c,t in zip(cur,y) if t]
    return 'model acc %.3f lit %.3f idi %.3f | current acc %.3f lit %.3f idi %.3f'%(sum((p>.5)==bool(t) for p,t in zip(P,y))/len(y),sum(p<=.5 for p in L)/len(L),sum(p>.5 for p in I)/len(I),
        sum(c==bool(t) for c,t in zip(cur,y))/len(y),sum(not c for c in cL)/len(cL),sum(cI)/len(cI))
t0=time.time()
for ep in range(epochs):
    rng.shuffle(tr)
    for i in range(0,len(tr),16):
        b=tr[i:i+16]; e=tok([x[0] for x in b],[window(x[1],rng.randint(WIN-2,WIN+2)) for x in b],padding=True,truncation=True,max_length=96,return_tensors='pt')
        lossf(m(**e).logits,torch.tensor([x[2] for x in b])).backward(); opt.step(); opt.zero_grad()
    print('epoch',ep,'t=%.0fs'%(time.time()-t0),ev(),flush=True); m.save_pretrained(out+'_ep%d'%ep); tok.save_pretrained(out+'_ep%d'%ep)

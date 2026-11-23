"""Word-sense choice on Claude-labelled public-domain words. Split by sentence (75/25). Reports, on the test part
(words whose correct meaning is among the choices): current SenseEngine, first choice, model, model + order prior.
With 'train', fine-tunes the given model on the train part first (pairs: right definition 1, others 0)."""
import json, glob, random, sys, math, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
torch.set_num_threads(int(sys.argv[3]) if len(sys.argv)>3 else 2)
md=sys.argv[1]; mode=sys.argv[2]
W={w['key']:w for w in json.load(open('pg_words.json'))}
L={}
for f in glob.glob('pgw_label_*.jsonl'):
    for l in open(f): r=json.loads(l); L[r['key']]=r['pick']
import zlib; rng=random.Random(8); test={W[k]['id'] for k in L if zlib.crc32(W[k]['id'].encode())%4==0}
def window(s,k=6):
    w=s.split(); f=next(i for i,x in enumerate(w) if '[' in x); l=max(i for i,x in enumerate(w) if ']' in x)
    return ' '.join(w[max(0,f-k):l+k+1])
def marked(w): s=w['sentence']; return window(s[:w['start']]+'[ '+s[w['start']:w['end']]+' ]'+s[w['end']:])
def pairs(w): m=marked(w); return [(f"{c['lemma']}: {c['en']}", m) for c in w['choices'][:6]]
tok=AutoTokenizer.from_pretrained(md); m=AutoModelForSequenceClassification.from_pretrained(md)
tr=[(W[k],p) for k,p in L.items() if W[k]['id'] not in test and 0<=p<6]
te=[(W[k],p) for k,p in L.items() if W[k]['id'] in test]
print('labelled',len(L),'none-fits %.2f'%(sum(p<0 for p in L.values())/len(L)),'train',len(tr),'test',len(te))
if mode=='train':
    X=[(a,b,int(i==p)) for w,p in tr for i,(a,b) in enumerate(pairs(w))]
    opt=torch.optim.AdamW(m.parameters(),lr=3e-5); m.train()
    for ep in range(3):
        rng.shuffle(X)
        for i in range(0,len(X),16):
            b=X[i:i+16]; e=tok([x[0] for x in b],[x[1] for x in b],padding=True,truncation=True,max_length=80,return_tensors='pt')
            m(**e,labels=torch.tensor([x[2] for x in b])).loss.backward(); opt.step(); opt.zero_grad()
        print('epoch',ep,flush=True)
    m.save_pretrained(sys.argv[4]); tok.save_pretrained(sys.argv[4])
m.eval()
te6=[(w,p) for w,p in te if 0<=p<6]
cur=sum(w['choices'][p]['tr']==w['cur'] or set(w['cur'].split(', '))<=set(w['choices'][p]['tr'].split(', ')) for w,p in te6)
first=sum(p==0 for w,p in te6)
res={}
with torch.no_grad():
    for lam in [0,0.05,0.1,0.2]: res[lam]=0
    for w,p in te6:
        ps=pairs(w); e=tok([a for a,b in ps],[b for a,b in ps],padding=True,truncation=True,max_length=80,return_tensors='pt')
        pr=torch.softmax(m(**e).logits,-1)[:,1].tolist()
        for lam in res:
            sc=[q - lam*i for i,q in enumerate(pr)]; res[lam]+= max(range(len(sc)),key=lambda i:sc[i])==p
n=len(te6)
print(f'test words with the right meaning among the first 6: {n} (of {len(te)}; none fits {sum(p<0 for w,p in te)}, beyond 6: {sum(p>=6 for w,p in te)})')
print(f'  current SenseEngine {cur/n:.3f}  first choice {first/n:.3f}  '+'  '.join(f'model+prior{l} {v/n:.3f}' for l,v in res.items()))

import json, random, sys, time, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
torch.set_num_threads(int(sys.argv[3])); name=sys.argv[1]; out=sys.argv[2]; epochs=int(sys.argv[4])
tr=[p for g in json.load(open('wn_train.json')) for p in g]; dev=json.load(open('wn_dev.json'))
rng=random.Random(3)
tok=AutoTokenizer.from_pretrained(name); m=AutoModelForSequenceClassification.from_pretrained(name,num_labels=2)
opt=torch.optim.AdamW(m.parameters(),lr=5e-5)
def P(pairs):
    m.eval(); r=[]
    with torch.no_grad():
        for i in range(0,len(pairs),64):
            b=pairs[i:i+64]; e=tok([x[0] for x in b],[x[1] for x in b],padding=True,truncation=True,max_length=80,return_tensors='pt')
            r+=torch.softmax(m(**e).logits,-1)[:,1].tolist()
    m.train(); return r
def ev():
    flat=[p for g in dev for p in g]; pr=P(flat); k=0; ok=0; first=0
    for g in dev:
        s=pr[k:k+len(g)]; k+=len(g)
        ok+= g[max(range(len(g)),key=lambda i:s[i])][2]==1
        first+= min(g,key=lambda x:x[3])[2]==1
    return 'group acc %.3f (first-sense baseline %.3f)'%(ok/len(dev), first/len(dev))
print('dev', ev() if False else '', len(tr), flush=True)
t0=time.time()
for ep in range(epochs):
    rng.shuffle(tr)
    for i in range(0,len(tr),32):
        b=tr[i:i+32]; e=tok([x[0] for x in b],[x[1] for x in b],padding=True,truncation=True,max_length=80,return_tensors='pt')
        m(**e,labels=torch.tensor([x[2] for x in b])).loss.backward(); opt.step(); opt.zero_grad()
        if i%32000==0: print(ep,i,'t=%.0f'%(time.time()-t0),flush=True)
    print('epoch',ep,ev(),flush=True); m.save_pretrained(out); tok.save_pretrained(out)

import json, sys, torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
torch.set_num_threads(4)
md=sys.argv[1]; tok=AutoTokenizer.from_pretrained(md); m=AutoModelForSequenceClassification.from_pretrained(md).eval()
out=open(sys.argv[2],'w'); WIN=int(sys.argv[3]) if len(sys.argv)>3 else 0
def window(s, k):
    w=s.split(); f=next(i for i,x in enumerate(w) if '[' in x); l=max(i for i,x in enumerate(w) if ']' in x)
    return ' '.join(w[max(0,f-k):l+k+1])
X=[]
for l in open('/home/user/ext/magpie-corpus/MAGPIE_filtered_split_typebased.jsonl'):
    r=json.loads(l)
    if r['label'] not in 'il' or r['confidence']<0.75 or r['split']=='training': continue
    s=r['context'][2]; a=r['offsets'][0][0]; b=r['offsets'][-1][1]
    X.append(('m%d'%r['id'],r['split'],r['idiom'], s[:a]+'[ '+s[a:b]+' ]'+s[b:], r['label']))
with torch.no_grad():
    for i in range(0,len(X),64):
        b=X[i:i+64]; e=tok([x[2] for x in b],[window(x[3],WIN) if WIN else x[3] for x in b],padding=True,truncation=True,max_length=96,return_tensors='pt')
        for x,p in zip(b,torch.softmax(m(**e).logits,-1)[:,1].tolist()):
            out.write(json.dumps({'id':x[0],'split':x[1],'idiom':x[2],'label':x[4],'p':p})+'\n')

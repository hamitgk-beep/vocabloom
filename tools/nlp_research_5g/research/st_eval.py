import os
# Research only (Task 5G, approach 5): sentence models score the sentence against the idiom's definitions and
# against the word-by-word glosses. Local only; nothing leaves the machine except the model download.
import json, sys, re, sqlite3, collections, numpy as np
from sentence_transformers import SentenceTransformer, CrossEncoder
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cohesion import STOP, lemma, exd, expr_en, senses, db
gl={i:g for i,g in db.execute('select id,gloss from syn')}
def idiom_defs(p,c):
    out=[]
    js=exd.get((p,c))
    if js:
        for s in json.loads(js):
            t=(str(s.get('title_en',''))+'. '+str(s.get('explain_en',''))).strip('. ')
            if t: out.append(t)
    e=expr_en.get((p,c),'').strip()
    if not out and e: out.append(e)
    return out
def lit_defs(p):
    out=[]
    for w in re.findall(r"[A-Za-z]+",p):
        w=w.lower()
        if w in STOP or w in ('someone','something','one'): continue
        for r,s in sorted(senses.get(lemma(w),[]))[:3]: out.append(f'{w}: {gl[s]}')
    return out
rows=[]
for name in ['dev','tune']:
    for l in open(os.environ['OUT5G']+f'/{name}.jsonl'):
        r=json.loads(l)
        if r['found']:
            r['I']=idiom_defs(r['phrase'],r['cat']); r['L']=lit_defs(r['phrase'])
            if r['I'] and r['L']: rows.append(r)
print('rows',len(rows))
out={}
bi=SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2', device='cpu')
ce=CrossEncoder('cross-encoder/ms-marco-MiniLM-L6-v2', device='cpu')
for r in rows:
    S=bi.encode([r['sentence']]+r['I']+r['L'], normalize_embeddings=True)
    s=S[1:]@S[0]; nI=len(r['I'])
    b=float(s[:nI].max()-s[nI:].max())
    cs=ce.predict([(r['sentence'],t) for t in r['I']+r['L']])
    c=float(cs[:nI].max()-cs[nI:].max())
    out[r['sentence']]={'bi':b,'ce':c}
json.dump(out,open(os.environ['OUT5G']+'/st_scores.json','w'))
for name in ['dev','tune']:
    f=[r for r in rows if r['set']==name]
    for k in ['bi','ce']:
        pos=np.array([out[r['sentence']][k] for r in f if r['gold']=='idiom']); neg=np.array([out[r['sentence']][k] for r in f if r['gold']=='literal'])
        print(name,k,'AUC',round(float((pos[:,None]>neg[None,:]).mean()),3), len(pos), len(neg))

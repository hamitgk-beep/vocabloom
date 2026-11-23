import json,sys
sys.path.insert(0,'/home/user/vocabloom/tools/nlp_research_5l')
from metrics_5l import dec
P={json.loads(l)['id']:json.loads(l)['p'] for l in open(sys.argv[1])}; t=float(sys.argv[2]) if len(sys.argv)>2 else 0.5
gold=[json.loads(l) for l in open('magpie_test.gold.jsonl')]
tr={json.loads(l)['id']:json.loads(l) for l in open('magpie_test_trace.jsonl')}
A=[];B=[]
for g in gold:
    x=tr.get(g['id'])
    if x is None or g['id'] not in P: continue
    a,b=g['offsets'][0][0], g['offsets'][-1][1]
    c=[c for c in x['cands'] if c['chars'][0][0]>=a-1 and c['chars'][-1][1]<=b+1 and len(c['tokens'])>=2]
    if not c: continue
    y=g['label']=='i'; A.append((any(dec(k['sys']['cur'])=='EXPR' for k in c),y)); B.append((P[g['id']]>t,y))
def rep(n,X):
    L=[p for p,y in X if not y]; I=[p for p,y in X if y]
    wrong_shown=sum(L)  # literal shown as expression
    print(f'{n}: n={len(X)} acc {sum(p==y for p,y in X)/len(X):.3f} literal recall {sum(not p for p in L)/len(L):.3f} idiom recall {sum(I)/len(I):.3f}  wrong expression shown {wrong_shown}/{len(L)} literal, idioms missed {len(I)-sum(I)}/{len(I)}')
rep('current engine',A); rep('new model',B)

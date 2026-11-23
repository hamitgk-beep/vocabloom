import json,sys,random
R=[json.loads(l) for l in open(sys.argv[1])]
for sp in ['development','test']:
    D=[r for r in R if r['split']==sp]; P=[r['p'] for r in D if r['label']=='i']; N=[r['p'] for r in D if r['label']=='l']
    random.seed(1); auc=sum((random.choice(P)>random.choice(N)) for _ in range(200000))/200000
    print(sp,len(D),'AUC~%.3f'%auc, ' '.join('t%.2f: acc %.3f lit %.3f idi %.3f'%(t,sum((r['p']>t)==(r['label']=='i') for r in D)/len(D), sum(p<=t for p in N)/len(N), sum(p>t for p in P)/len(P)) for t in [0.1,0.3,0.5]))

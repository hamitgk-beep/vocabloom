import os
import json, sys, numpy as np, re
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import GroupKFold
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
PREPS={'in','on','at','by','for','from','to','with','under','over','off','out','up','down','into','onto','behind','beyond','above','below','across','through','against','around','round','about','after','before','between','among','without','within','along','past','like','of','as','upon'}
CATS=['idioms','prepositional_phrases','binomials','chunks','collocations']
def X(r):
    c=r['cues']; prep=r['cat']=='prepositional_phrases' or r['phrase'].split()[0] in PREPS
    sL=r['sL'] if r['sL'] is not None else 0
    reason=r['reason']
    v=[r['sI'], sL, r['sI']-sL, r['freeI'] or 0, r['litCands'], r['litCandsTr'], int(r['conf']=='sure'), int(r['conf']=='likely'),
       int(r['literal']), int('idiom or words' in reason), int('unverified' in reason), int('close' in reason),
       len(r['sentence'].split()), len(r['phrase'].split()), int(prep),
       int(c['determiner']), int(c['number']), int(c['nounGoesOn']), int(c['mention']), int(prep and (c['determiner'] or c['number'])),
       int(r['sentence'][:1].islower()), int('?' in r['sentence'])]
    v+= [int(r['cat']==k) for k in CATS]
    return v
def load(p): return [json.loads(l) for l in open(p) if json.loads(l)['found']]
if __name__=='__main__':
    dev=load(os.environ['OUT5G']+'/dev.jsonl')
    Xd=np.array([X(r) for r in dev],float); y=np.array([r['gold']=='literal' for r in dev]); g=[r['phrase'] for r in dev]
    for name,mk in [('LR',lambda: LogisticRegression(C=0.5,max_iter=2000,class_weight=None)),('GB',lambda: GradientBoostingClassifier(n_estimators=150,max_depth=2))]:
        p=np.zeros(len(dev))
        for tr,te in GroupKFold(5).split(Xd,y,g):
            mu,sd=Xd[tr].mean(0),Xd[tr].std(0)+1e-9
            m=mk().fit((Xd[tr]-mu)/sd,y[tr]); p[te]=m.predict_proba((Xd[te]-mu)/sd)[:,1]
        asI=np.array([r['asIdiom'] for r in dev])
        print(name)
        for t in [0.3,0.4,0.5,0.6,0.7]:
            veto=p>=t
            fp_rm=int(((veto)&asI&y).sum()); tp_lost=int((veto&asI&~y).sum())
            print(f'  t={t}: FP removed {fp_rm}/{int((asI&y).sum())}, TP lost {tp_lost}/{int((asI&~y).sum())}')

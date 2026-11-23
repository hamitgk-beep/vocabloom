import os
import json, sqlite3, re, sys, collections
db=sqlite3.connect('file:'+os.environ.get('DICT_DB','assets/dict.db')+'?mode=ro',uri=True)
STOP=set("""the a an and or but of to in on at for with by is are was were be been being it this that he she they we you i his her their as from not so if than then there have has had do does did my your its our me him them one some any all what which who when where how into out up down off over very can could would should will shall may might must just also only no nor too s t about after again against am because before below between both during each few further here more most other own same such through under until while why whom whose yours itself himself herself themselves us get got make made go went like""".split())
exc={}
for f,l,p in db.execute('select form,lemma,pos from exc'): exc.setdefault(f,l)
lem_ok={l for (l,) in db.execute('select distinct lemma from sense')}
def lemma(w):
    w=w.lower()
    if w in exc: return exc[w]
    if w in lem_ok: return w
    for suf,rep in (('ies','y'),('es',''),('s',''),('ing',''),('ing','e'),('ed',''),('ed','e'),('er',''),('ly','')):
        if w.endswith(suf) and w[:-len(suf)]+rep in lem_ok: return w[:-len(suf)]+rep
    return w
def words(t): return [lemma(w) for w in re.findall(r"[A-Za-z]+",t) if w.lower() not in STOP and len(w)>2]
syn={}
for i,g,ex,ws in db.execute('select id,gloss,examples,words from syn'): syn[i]=(g or '')+' '+' '.join(json.loads(ex) if ex else [])+' '+' '.join(json.loads(ws) if ws else [])
senses=collections.defaultdict(list)
for l,p,r,s in db.execute('select lemma,pos,rank,syn_id from sense'): senses[l].append((r,s))
def bag_word(w, k=6):
    out=set()
    for r,s in sorted(senses.get(w,[]))[:k]: out|=set(words(syn[s]))
    return out
exd={}
for p,c,js in db.execute('select phrase,cat,json from exd'): exd[(p,c)]=js
expr_en={}
for p,c,en,ex in db.execute('select phrase,cat,en,ex from expr'): expr_en[(p,c)]=(en or '')+' '+(ex or '')
def idiom_bag(p,c):
    t=expr_en.get((p,c),'')
    js=exd.get((p,c))
    if js:
        for s in json.loads(js):
            t+=' '+str(s.get('title_en',''))+' '+str(s.get('explain_en',''))+' '+' '.join(str(x.get('en','')) for x in s.get('examples',[]))
    return set(words(t))
def feats(r):
    comp=[lemma(w) for w in re.findall(r"[A-Za-z]+",r['phrase']) if w.lower() not in STOP]
    L=set()
    for w in comp: L|=bag_word(w)|{w}
    I=idiom_bag(r['phrase'],r['cat'])-set(comp)
    ctx=set(words(r['sentence']))-set(comp)
    L-=set(comp)
    # second order: context words' own glosses
    C2=set()
    for w in ctx: C2|=bag_word(w,3)
    return dict(ovL=len(ctx&L), ovI=len(ctx&I), ovL2=len(C2&set(comp)), n=len(ctx))
if __name__=='__main__':
    rows=[json.loads(l) for l in open(sys.argv[1])]
    f=[r for r in rows if r['found']]
    for r in f: r['co']=feats(r)
    def auc(key):
        pos=[key(r) for r in f if r['gold']=='literal']; neg=[key(r) for r in f if r['gold']=='idiom']
        s=sum((a>b)+0.5*(a==b) for a in pos for b in neg); return round(s/len(pos)/len(neg),3)
    for k in ['ovL','ovI','ovL2']: print(k, auc(lambda r:r['co'][k]))
    print('ovL-ovI', auc(lambda r:r['co']['ovL']-r['co']['ovI']))
    print('ovL+ovL2-ovI', auc(lambda r:r['co']['ovL']+r['co']['ovL2']-r['co']['ovI']))
    print('engine sL-sI', auc(lambda r:(r['sL'] or 0)-r['sI']))
    for th in [1,2,3]:
        k=lambda r:r['co']['ovL']+r['co']['ovL2']-r['co']['ovI']
        lit=sum(1 for r in f if r['gold']=='literal' and k(r)>=th); idi=sum(1 for r in f if r['gold']=='idiom' and k(r)>=th)
        print(th, 'lit',lit,'idi',idi)

"""Gloss cross-encoder training pairs from WordNet's own examples in dict.db (WordNet licence: free incl. commercial,
with its notice). Positive: (lemma: gloss of the synset the example illustrates, example with [ word ]); negatives: other
synsets of the same lemma. Lemmas split 95/5 into train/dev."""
import sqlite3, json, re, random, collections
c=sqlite3.connect('file:/home/user/vocabloom/assets/dict.db?mode=ro',uri=True)
exc=collections.defaultdict(set)
for f,l,p in c.execute('select form,lemma,pos from exc'): exc[l].add(f.lower())
senses=collections.defaultdict(list)
for l,p,r,sid in c.execute('select lemma,pos,rank,syn_id from sense'): senses[l].append((r,p,sid))
syn={i:(p,g,json.loads(e or '[]'),w) for i,p,g,e,w in c.execute('select id,pos,gloss,examples,words from syn')}
def forms(l):
    f={l,l+'s',l+'es',l+'ed',l+'d',l+'ing',l+"'s"}
    if l.endswith('e'): f|={l[:-1]+'ing',l[:-1]+'ed'}
    if l.endswith('y'): f|={l[:-1]+'ies',l[:-1]+'ied'}
    if re.search(r'[^aeiou][aeiou][bdgklmnprt]$',l): f|={l+l[-1]+'ed',l+l[-1]+'ing',l+l[-1]+'er'}
    if l.endswith('f'): f|={l[:-1]+'ves'}
    return f|exc.get(l,set())
rng=random.Random(5)
lemmas=sorted(senses); rng.shuffle(lemmas); dev=set(lemmas[:len(lemmas)//20])
out={'train':[], 'dev':[]}
for l in senses:
    if not re.fullmatch(r"[a-z]+",l) or len(senses[l])<2: continue
    F=forms(l)
    for r,p,sid in senses[l]:
        sp,g,ex,_=syn[sid]
        for e in ex:
            toks=list(re.finditer(r"[A-Za-z']+",e))
            hit=[t for t in toks if t.group().lower() in F]
            if len(hit)!=1: continue
            a,b=hit[0].span(); m=e[:a]+'[ '+e[a:b]+' ]'+e[b:]
            neg=[x for x in senses[l] if x[2]!=sid]; rng.shuffle(neg)
            grp=[(f'{l}: {g}', m, 1, r)]+[(f'{l}: {syn[x[2]][1]}', m, 0, x[0]) for x in neg[:3]]
            out['dev' if l in dev else 'train'].append(grp)
for k,v in out.items():
    json.dump(v,open(f'/home/user/exp5n/wsd/wn_{k}.json','w'))
    print(k,len(v),'groups',sum(len(g) for g in v),'pairs')
print(out['train'][0])

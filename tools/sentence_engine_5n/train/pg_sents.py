import pyarrow.parquet as pq, re, random, sys
t=pq.read_table('/home/user/pg/en0.parquet').to_pylist()
rng=random.Random(11); rng.shuffle(t)
out=open(sys.argv[1],'w'); n=0
for b in t[:600]:
    x=b['text']; a=x.find('*** START'); z=x.find('*** END')
    if a<0 or z<0: continue
    x=x[x.find('\n',a)+1:z]
    paras=[re.sub(r'\s+',' ',p).strip() for p in re.split(r'\n\s*\n',x)]
    paras=[p for p in paras if len(p)>80 and not p.isupper() and '_' not in p and '[' not in p]
    rng.shuffle(paras); k=0
    for p in paras[:40]:
        for s in re.split(r'(?<=[.!?])\s+(?=[A-Z"\'])',p):
            w=s.split()
            if 7<=len(w)<=32 and s[-1] in '.!?"\'' and not re.search(r'[0-9]{3}|http|www|\t',s):
                out.write('pg%d\t%s\n'%(n,s)); n+=1; k+=1
            if k>=60: break
        if k>=60: break
print(n)

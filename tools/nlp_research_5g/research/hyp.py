import os
import json, re, sqlite3, collections, sys
db=sqlite3.connect('file:'+os.environ.get('DICT_DB','assets/dict.db')+'?mode=ro',uri=True)
pos=collections.defaultdict(set)
for l,p in db.execute('select lemma,pos from sense'): pos[l].add({'s':'a'}.get(p,p))
DET={'a','an','the','my','your','his','her','its','our','their','this','that','these','those','some','any','no','every','each'}
PREPS={'of','in','on','at','for','with','by','from','to','into'}
def W(s): return [(m.group(0),m.start()) for m in re.finditer(r"[A-Za-z]+(?:['’][A-Za-z]+)*(?:-[A-Za-z]+)*",s)]
for name in sys.argv[1:]:
    rows=[json.loads(l) for l in open(os.environ['OUT5G_CUES']+f'/{name}.jsonl')]
    H=collections.defaultdict(lambda: collections.Counter())
    for r in rows:
        if not r['found']: continue
        w=W(r['sentence']); idx=r['idx']; first=idx[0]; last=idx[-1]
        g=('lit' if r['gold']=='literal' else 'idi')+('*' if r['asIdiom'] else '')
        pat=r['phrase'].split()
        v0=pat[0]
        verbish='v' in pos[v0] and r['cat']=='idioms'
        prev=w[first-1][0].lower() if first>0 else ''
        tok=w[first][0].lower()
        if verbish and (prev in DET or prev=='of') and (tok.endswith('ing') or tok.endswith('ed') or tok==v0): H['H1 verb idiom used as noun group'][g]+=1
        if r['cues']['nounGoesOn']: H['H3 nounGoesOn '+r['cat']][g]+=1
        caps=[w[i][0] for i in idx if i>0 and w[i][0][:1].isupper() and w[i][0].lower() not in ('i',)]
        if caps and not r['sentence'].isupper(): H['H4 capitalised word mid-sentence'][g]+=1
    print(name)
    for k,v in sorted(H.items()): print('  ',k,dict(v))

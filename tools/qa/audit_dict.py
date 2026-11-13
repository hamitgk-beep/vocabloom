"""Quality audit of the built-in dictionary (assets/dict.db).

Hamit's standard: every panel must read like a tutor explaining the word in
English and Turkish. Each sense has a Turkish explanation, and every English
example has its Turkish translation under it. Nothing empty or English-only.

This script checks the data behind every panel the app shows:
  * expressions (Dictionary categories, the "phrase" cards in the reader,
    Kelimelerim and review cards): expr + exd + exs tables
  * words (reader word sheet): ft + syn + sense + wd tables
  * word families (Word Family tab): famg + fam + wfd tables

Each finding is one of two kinds:
  bug      - wrong or incomplete content that is already in the app
             (an AI answer without Turkish, an English word in a Turkish
             line, a junk definition, ...). These must go down to zero.
  pending  - not translated yet; the nightly dictionary-data job is
             expected to fill it. Reported so progress can be followed.

usage:
  python3 tools/qa/audit_dict.py assets/dict.db --out qa-report
      [--baseline tools/qa/baseline.json] [--write-baseline]

Writes qa-report/report.md (Turkish, for people), qa-report/summary.json and
qa-report/samples/<check>.tsv. With --baseline it exits 1 when any bug count
went up compared to the baseline, so a release never gets worse.
"""
import argparse
import json
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

# ---------------------------------------------------------------- checks

# id: (kind, Turkish title, what the user sees)
CHECKS = {
    # expressions
    'expr_no_tr': ('pending', 'İfadenin Türkçe anlamı yok',
                   'Kartta yalnızca İngilizce tanım ya da "kelime kelime" çeviri görünür.'),
    'expr_en_only_def': ('pending', 'İngilizce tanımın Türkçe açıklaması yok',
                         'Tanım satırı yalnızca İngilizce (öğretmen anlatımı henüz yok).'),
    'expr_no_example': ('pending', 'İfadenin hiç örnek cümlesi yok', 'Kartta örnek cümle görünmez.'),
    'expr_example_no_tr': ('pending', 'Örnek cümle var ama Türkçesi yok',
                           'İngilizce örneğin altında Türkçe satır yok.'),
    'expr_junk_def': ('bug', 'Anlamsız tanım ("Used other than figuratively…")',
                      'Wiktionary\'nin iç notu tanım gibi gösteriliyor.'),
    'expr_tr_has_english': ('bug', 'Türkçe anlam satırına İngilizce karışmış',
                            'Türkçe satırda İngilizce kelimeler görünüyor.'),
    'expr_tr_equals_en': ('bug', 'Türkçe anlam İngilizcesinin aynısı', 'Türkçe satır aslında İngilizce.'),
    'exd_bad_json': ('bug', 'Hazır açıklama okunamıyor (bozuk JSON)', 'Panel açıklamayı gösteremez.'),
    'exd_sense_no_title_tr': ('bug', 'Anlamın Türkçe başlığı boş', 'Anlam kartında başlık yalnızca İngilizce.'),
    'exd_sense_no_explain_tr': ('bug', 'Anlamın Türkçe açıklaması boş', 'Anlam kartında açıklama yalnızca İngilizce.'),
    'exd_sense_no_example': ('bug', 'Anlamın örnek cümlesi yok', 'Anlam kartında örnek yok.'),
    'exd_example_no_tr': ('bug', 'Hazır açıklamadaki örneğin Türkçesi yok', 'Örnek cümlenin altı boş.'),
    'exd_tr_has_english': ('bug', 'Hazır açıklamanın Türkçesinde İngilizce var',
                           'Türkçe başlık, açıklama ya da örnek çevirisinde İngilizce kelimeler.'),
    'exd_tr_equals_en': ('bug', 'Hazır açıklamada Türkçe = İngilizce', 'Çeviri yapılmamış, İngilizce kopyalanmış.'),
    # words
    'word_no_tr': ('pending', 'Sık kelimenin hiç Türkçesi yok', 'Kelime panelinde Türkçe anlam görünmez.'),
    'word_sense_no_tr': ('pending', 'Kelime anlamının (WordNet) Türkçesi yok',
                         'Türkçe kapalıyken anlam ve tür başlığı kaybolur, açıkken yalnızca İngilizce.'),
    'word_example_no_tr': ('pending', 'Kelime anlamının örneğinin Türkçesi yok',
                           '"Bu cümledeki anlamı" altında İngilizce örneğin Türkçesi yok.'),
    'word_no_teacher': ('pending', 'Sık kelimenin öğretmen anlatımı yok',
                        '"Anlamları ve kullanımı" bölümü görünmez.'),
    'word_ft_abbrev': ('bug', 'Türkçe karşılıkta kısaltma ya da etiket',
                       '"(çoğ.)", "(son ek)", "(Amerikan İngilizcesi)" gibi etiketler okuyanı şaşırtır.'),
    'word_ft_tag_first': ('bug', 'İlk Türkçe karşılık bir etiketle başlıyor',
                          'En sık anlam yerine "(sonek) …" gibi nadir anlam en üstte.'),
    'word_ft_corrupt': ('bug', 'Türkçe karşılıkta bozuk kelime',
                        'Kısaltma açılırken kelimenin ortasına etiket girmiş: "de(sigortacılık)ns", "(kısaltma)ımlardan".'),
    'word_ft_has_english': ('bug', 'Türkçe karşılık satırına İngilizce karışmış',
                            'Ör. "work force", "work stoppage" Türkçe listede.'),
    'wd_bad': ('bug', 'Kelimenin hazır açıklaması eksik', 'Öğretmen anlatımında Türkçe başlık/açıklama/örnek eksik.'),
    # word family
    'fam_member_no_tr': ('pending', 'Kelime ailesi üyesinin Türkçesi yok',
                         'Word Family sekmesinde kelimenin yanında anlam yok.'),
    'fam_member_no_example': ('pending', 'Kelime ailesi üyesinin örnek cümlesi yok',
                              'Word Family sekmesinde örnek ve Türkçesi yok.'),
    'wfd_bad': ('bug', 'Hazır kelime ailesinde eksik alan', 'Türkçe, ek açıklaması ya da örnek eksik.'),
    'wfd_bad_base': ('bug', 'Kelime ailesinde yanlış kök', 'Ek açıklaması yanlış kelimeden türetilmiş gösteriyor.'),
}

JUNK_DEF = re.compile(r'^\s*(used other than|used in (a )?(non-?idiomatic|literal)|see also|alternative form of|'
                      r'misspelling of|obsolete form of|archaic form of)', re.I)

# Plain English words that never appear in a Turkish sentence. Kept short on
# purpose: a hit is very likely a real mix-up, not a Turkish word.
EN_MARKERS = set('''the of and with for from someone something somebody anything everything nothing
which whose would could should been being were was are this that these those their there where when
what who whom into onto upon over under about after before because while though although however
used use using such than then very more most much many your our its they them she he we you
make makes made take takes took get gets got give gives gave do does did done have has had will shall
not no yes force stoppage work works worker way thing things people person time year
figuratively literally idiomatic informal formal slang'''.split())
# Turkish words that look like the markers above.
TR_LOOKALIKES = set('o bu şu ne da de ki mi mu mı mü ve ile için her not has had his on at kim ben'.split())

WORD_RE = re.compile(r"[A-Za-zÇĞİÖŞÜçğıöşüâîû']+")
TR_CHARS = set('çğıöşüÇĞİÖŞÜ')
# Bracketed labels in FreeDict Turkish lines.
FT_TAG = re.compile(r'\((?:çoğ\.?|çoğul|son ?ek|sonek|ön ?ek|önek|amer\.?|ing\.?|argo|kon\.?|esk\.?|'
                    r'Amerikan İngilizcesi|İngiliz İngilizcesi|denizcilik|tıb|tıp|huk|mat|kim|fiz|bot|zool|'
                    r'mak|mim|müz|coğ|dilb|ask|tic|elek|biy|jeol|astr|fot|spor|mec|edeb)[^)]*\)', re.I)


# A "(label)" glued to letters on both sides: an abbreviation was expanded
# inside a word ("design" -> "de(sigortacılık)ns").
GLUED_TAG = re.compile(r'[A-Za-zÇĞİÖŞÜçğıöşü]\([a-zçğıöşü ]{3,}\)[A-Za-zçğıöşü]')


def english_words(text, extra=()):
    """English marker words found in a line that should be Turkish."""
    if not text:
        return []
    out = []
    for w in WORD_RE.findall(text):
        lw = w.lower().strip("'")
        if lw in TR_LOOKALIKES:
            continue
        if lw in EN_MARKERS or lw in extra:
            out.append(lw)
    return out


def norm(s):
    return re.sub(r'\W+', ' ', (s or '').lower()).strip()


def jl(s):
    if s is None:
        return None
    try:
        return json.loads(s)
    except Exception:
        return None


def has_table(c, name):
    return c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def cols(c, table):
    return {r[1] for r in c.execute(f'PRAGMA table_info({table})')}


class Audit:
    def __init__(self, db, top_words):
        self.c = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
        self.top_words = top_words
        self.counts = Counter()
        self.by_cat = defaultdict(Counter)  # check -> category -> n
        self.samples = defaultdict(list)
        self.totals = Counter()

    def hit(self, check, item, detail='', cat=None):
        self.counts[check] += 1
        if cat:
            self.by_cat[check][cat] += 1
        if len(self.samples[check]) < 400:
            self.samples[check].append((item, cat or '', detail))

    # ------------------------------------------------------------ expressions
    def exprs(self):
        c = self.c
        ecols = cols(c, 'expr')
        exd = {}
        if has_table(c, 'exd'):
            for p, cat, js in c.execute('SELECT phrase, cat, json FROM exd'):
                exd[(p, cat)] = js
        exs = Counter()
        if has_table(c, 'exs'):
            for k, n in c.execute("SELECT key, count(*) FROM exs WHERE key NOT LIKE 'w:%' GROUP BY key"):
                exs[k] = n
        sel = ['id', 'phrase', 'cat', 'tr', 'en'] + [x for x in ('ex', 'entr', 'extr') if x in ecols]
        for row in c.execute(f'SELECT {", ".join(sel)} FROM expr'):
            r = dict(zip(sel, row))
            p, cat = r['phrase'], r['cat']
            self.totals['expr'] += 1
            self.totals[f'expr:{cat}'] += 1
            label = p
            d = exd.get((p, cat))
            senses = None
            if d is not None:
                senses = jl(d)
                if not isinstance(senses, list):
                    self.hit('exd_bad_json', label, d[:120], cat)
                    senses = None
                else:
                    self.totals['exd'] += 1
            tr, en = (r['tr'] or '').strip(), (r['en'] or '').strip()

            # Turkish meaning
            if not tr and not senses:
                self.hit('expr_no_tr', label, en[:120], cat)
            if tr:
                bad = english_words(tr)
                if bad:
                    self.hit('expr_tr_has_english', label, f'{tr}  ← {", ".join(sorted(set(bad)))}', cat)
                if en and norm(tr) == norm(en):
                    self.hit('expr_tr_equals_en', label, tr, cat)
            # English definition
            if en and JUNK_DEF.search(en) and not senses:
                self.hit('expr_junk_def', label, en[:160], cat)
            elif en and JUNK_DEF.search(en.split(';')[0]):
                # Shown even next to built-in senses when English is on.
                self.hit('expr_junk_def', label, en[:160], cat)
            if en and not (r.get('entr') or '').strip() and not senses:
                self.hit('expr_en_only_def', label, en[:120], cat)
            # Examples
            ex_ok = bool(senses and any(
                (e.get('en') and e.get('tr')) for s in senses if isinstance(s, dict)
                for e in (s.get('examples') or []) if isinstance(e, dict)))
            if not ex_ok and r.get('ex') and (r.get('extr') or '').strip():
                ex_ok = True
            if not ex_ok and exs.get(f'{p}|{cat}'):
                ex_ok = True
            if not ex_ok:
                if r.get('ex'):
                    self.hit('expr_example_no_tr', label, r['ex'][:140], cat)
                else:
                    self.hit('expr_no_example', label, '', cat)
            if senses:
                self.check_senses(senses, label, cat, 'exd')

    def check_senses(self, senses, label, cat, prefix):
        for i, s in enumerate(senses):
            if not isinstance(s, dict):
                self.hit(f'{prefix}_bad_json' if prefix == 'exd' else 'wd_bad', label, f'sense {i + 1} is not an object', cat)
                continue
            n = f'{label} #{i + 1}'
            ttr, xtr = (s.get('title_tr') or '').strip(), (s.get('explain_tr') or '').strip()
            if prefix == 'exd':
                if not ttr:
                    self.hit('exd_sense_no_title_tr', n, s.get('title_en') or '', cat)
                if not xtr:
                    self.hit('exd_sense_no_explain_tr', n, (s.get('explain_en') or '')[:120], cat)
            elif not ttr or not xtr:
                self.hit('wd_bad', n, 'Türkçe başlık ya da açıklama boş', cat)
            exs = [e for e in (s.get('examples') or []) if isinstance(e, dict) and (e.get('en') or '').strip()]
            if not exs:
                self.hit('exd_sense_no_example' if prefix == 'exd' else 'wd_bad', n, 'örnek yok', cat)
            for e in exs:
                if not (e.get('tr') or '').strip():
                    self.hit('exd_example_no_tr' if prefix == 'exd' else 'wd_bad', n, e['en'][:140], cat)
                elif norm(e['tr']) == norm(e['en']):
                    self.hit('exd_tr_equals_en' if prefix == 'exd' else 'wd_bad', n, e['tr'][:140], cat)
            for field in ('title_tr', 'explain_tr'):
                bad = english_words(s.get(field))
                # The expression itself may be quoted inside the Turkish text.
                bad = [b for b in bad if b not in label.lower().split()]
                if len(bad) >= 2:
                    self.hit('exd_tr_has_english' if prefix == 'exd' else 'wd_bad', n,
                             f'{field}: {s.get(field)}  ← {", ".join(sorted(set(bad)))}', cat)
            if ttr and norm(ttr) == norm(s.get('title_en')) and len(ttr.split()) > 1:
                self.hit('exd_tr_equals_en' if prefix == 'exd' else 'wd_bad', n, ttr, cat)

    # ------------------------------------------------------------ words
    def words(self):
        c = self.c
        top = [w for (w,) in c.execute('SELECT word FROM wfreq ORDER BY n DESC')]
        senses_of = defaultdict(list)
        scols = cols(c, 'syn')
        has_extr = 'extr' in scols
        lemmas = {w for (w,) in c.execute('SELECT DISTINCT lemma FROM sense')}
        ft = {w: jl(t) or [] for w, t in c.execute('SELECT word, tr FROM ft')}
        wd = {}
        if has_table(c, 'wd'):
            for w, t, js in c.execute('SELECT word, tr, json FROM wd'):
                wd[w] = (t, js)
        # Only real dictionary words, most frequent first (wfreq comes from books
        # and includes names like "tom").
        top = [w for w in top if w in lemmas or w in ft][: self.top_words]
        topset = set(top)
        q = ('SELECT x.lemma, s.pos, s.gloss, s.examples, s.tr' + (', s.extr' if has_extr else '') +
             ' FROM sense x JOIN syn s ON s.id = x.syn_id ORDER BY x.lemma, x.rank')
        for row in c.execute(q):
            if row[0] in topset:
                senses_of[row[0]].append(row)
        def base_known(w):
            for suf, add in (('ies', 'y'), ('es', ''), ('s', ''), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e'), ('d', '')):
                if w.endswith(suf) and len(w) - len(suf) >= 2:
                    b = w[: len(w) - len(suf)] + add
                    if b in ft or b in wd:
                        return True
            return False

        for w in top:
            self.totals['word'] += 1
            ss = senses_of.get(w, [])
            fts = ft.get(w, [])
            has_sense_tr = any(jl(s[4]) for s in ss)
            if not fts and not has_sense_tr and w not in wd and not base_known(w):
                self.hit('word_no_tr', w, ss[0][2][:100] if ss else '')
            if w not in wd:
                self.hit('word_no_teacher', w)
            else:
                d = jl(wd[w][1])
                if not isinstance(d, list) or not d:
                    self.hit('wd_bad', w, 'boş ya da bozuk JSON')
                else:
                    self.check_senses(d, w, None, 'wd')
            # The sheet shows at most 8 senses per part of speech.
            per_pos = Counter()
            for s in ss:
                per_pos[s[1]] += 1
                if per_pos[s[1]] > 8:
                    continue
                self.totals['word_sense'] += 1
                if not jl(s[4]):
                    self.hit('word_sense_no_tr', f'{w} ({s[1]})', s[2][:100])
                exs = jl(s[3]) or []
                extr = (jl(s[5]) if has_extr else None) or []
                for k, e in enumerate(exs[:2]):
                    self.totals['word_example'] += 1
                    if k >= len(extr) or not (extr[k] or '').strip():
                        self.hit('word_example_no_tr', f'{w} ({s[1]})', e[:120])
            for i, t in enumerate(fts[:12]):
                if FT_TAG.search(t):
                    self.hit('word_ft_abbrev', w, f'{i + 1}. {t}')
                if i == 0 and t.lstrip().startswith('(') and FT_TAG.match(t.lstrip()):
                    self.hit('word_ft_tag_first', w, t)
                if GLUED_TAG.search(t):
                    self.hit('word_ft_corrupt', w, f'{i + 1}. {t}')
                bad = english_words(t, extra={w} if len(w) > 3 else ())
                if bad:
                    self.hit('word_ft_has_english', w, f'{i + 1}. {t}  ← {", ".join(sorted(set(bad)))}')

    # ------------------------------------------------------------ families
    def families(self):
        c = self.c
        ft = {w for (w,) in c.execute('SELECT word FROM ft')}
        sense_tr = {w for (w,) in c.execute(
            'SELECT DISTINCT x.lemma FROM sense x JOIN syn s ON s.id=x.syn_id WHERE s.tr IS NOT NULL')}
        wexs = {k[2:] for (k,) in c.execute("SELECT DISTINCT key FROM exs WHERE key LIKE 'w:%'")}
        wfd = {}
        if has_table(c, 'wfd'):
            for root, js in c.execute('SELECT root, json FROM wfd'):
                wfd[root] = js
        freq = dict(c.execute('SELECT word, n FROM wfreq'))
        groups = list(c.execute('SELECT id, root, members, negs FROM famg'))
        # Families of words people actually meet first.
        groups.sort(key=lambda g: -max([freq.get(m[0], 0) for m in (jl(g[2]) or [])] + [0]))
        seen = set()
        for gid, root, members, negs in groups[: self.top_words]:
            self.totals['family'] += 1
            words = [m[0] for m in (jl(members) or [])] + [n[0] for n in (jl(negs) or [])]
            for w in words:
                if w in seen:
                    continue
                seen.add(w)
                self.totals['family_member'] += 1
                if w not in ft and w not in sense_tr:
                    self.hit('fam_member_no_tr', w, f'aile: {root}')
                if w not in wexs:
                    self.hit('fam_member_no_example', w, f'aile: {root}')
            if root in wfd:
                self.check_wfd(root, wfd[root])

    def check_wfd(self, root, js):
        d = jl(js)
        if not isinstance(d, dict):
            self.hit('wfd_bad', root, 'bozuk JSON')
            return
        entries = []
        for key in ('members', 'negatives', 'items', 'forms'):
            v = d.get(key)
            if isinstance(v, list):
                entries += [e for e in v if isinstance(e, dict)]
        for e in entries:
            w = e.get('word') or e.get('w') or '?'
            if not (e.get('tr') or '').strip():
                self.hit('wfd_bad', f'{root}: {w}', 'Türkçe yok')
            if not (e.get('ex_en') or e.get('exEn') or e.get('example_en')):
                self.hit('wfd_bad', f'{root}: {w}', 'örnek yok')
            elif not (e.get('ex_tr') or e.get('exTr') or e.get('example_tr')):
                self.hit('wfd_bad', f'{root}: {w}', 'örneğin Türkçesi yok')
            base = e.get('base') or e.get('from')
            if base and w != '?' and not plausible_base(w, base):
                self.hit('wfd_bad_base', f'{root}: {w}', f'kök gösterilen: {base}')


SUFFIXES = sorted('able ible al ial ation ition ion tion ate ance ence ant ent ary ery ory dom ed en er or ist ism '
                  'ity ty ive ize ise less ly ment ness ous ious ful ship ward wise y ic ical'.split(), key=len, reverse=True)


def plausible_base(word, base):
    """A base must be shorter than the word and share its start (work -> workable,
    different -> differential). 'differently -> differential' is not plausible:
    the base carries a suffix (-ly) that the word does not have."""
    if len(base) >= len(word) and not word.startswith(('un', 'in', 'im', 'il', 'ir', 'dis', 'non', 'mis', 'de')):
        return False
    stem = base[:max(3, len(base) - 2)]
    core = re.sub(r'^(un|in|im|il|ir|dis|non|mis|de)', '', word)
    if not (word.startswith(stem) or core.startswith(stem)):
        return False
    for suf in SUFFIXES:
        if base.endswith(suf) and len(base) - len(suf) >= 3 and base not in word and base not in core:
            # base carries a suffix that is not part of the word
            return False
    return True


# ---------------------------------------------------------------- report

def write_report(a, out, baseline, db):
    os.makedirs(os.path.join(out, 'samples'), exist_ok=True)
    summary = {
        'db': os.path.basename(db),
        'totals': dict(a.totals),
        'counts': {k: a.counts.get(k, 0) for k in CHECKS},
        'by_category': {k: dict(v) for k, v in a.by_cat.items()},
    }
    with open(os.path.join(out, 'summary.json'), 'w', encoding='utf-8') as f:
        json.dump(summary, f, ensure_ascii=False, indent=1, sort_keys=True)
    for k, rows in a.samples.items():
        with open(os.path.join(out, 'samples', f'{k}.tsv'), 'w', encoding='utf-8') as f:
            f.write('item\tcategory\tdetail\n')
            for r in rows:
                f.write('\t'.join(x.replace('\t', ' ').replace('\n', ' ') for x in r) + '\n')

    worse = []
    if baseline:
        for k, (kind, *_x) in CHECKS.items():
            if kind == 'bug' and a.counts.get(k, 0) > baseline.get('counts', {}).get(k, 0):
                worse.append(k)

    L = []
    L.append('# VocaBloom sözlük kalite raporu\n')
    t = a.totals
    L.append(f"Taranan: {t['expr']} ifade ({t['exd']} tanesinin hazır öğretmen anlatımı var), "
             f"en sık {t['word']} kelime, {t['family']} kelime ailesi ({t['family_member']} kelime).\n")
    if baseline:
        L.append('**Sonuç:** ' + ('önceki sürüme göre kötüleşen yok ✅' if not worse else
                                  'kötüleşen kontroller var ❌: ' + ', '.join(CHECKS[k][1] for k in worse)) + '\n')

    def table(kind, title, note):
        L.append(f'\n## {title}\n\n{note}\n')
        L.append('| Kontrol | Sayı | Önceki | Kullanıcının gördüğü | Örnekler |')
        L.append('|---|---:|---:|---|---|')
        for k, (kk, name, seen) in CHECKS.items():
            if kk != kind:
                continue
            n = a.counts.get(k, 0)
            prev = baseline.get('counts', {}).get(k, '') if baseline else ''
            ex = '; '.join(s[0] for s in a.samples.get(k, [])[:4]).replace('|', '/')
            L.append(f'| {name} | {n} | {prev} | {seen} | {ex} |')

    table('bug', 'Hatalar (sıfıra inmeli)',
          'Uygulamada şu an görünen yanlış ya da eksik içerik. Gece çeviri işi bunları kendiliğinden düzeltmez.')
    table('pending', 'Henüz çevrilmemiş (gece işinde bekliyor)',
          'Gece çalışan ücretsiz yapay zekâ işi dolduruyor; sayılar her sürümde azalmalı.')

    L.append('\n## Kategoriye göre ifadeler\n')
    L.append('| Kategori | İfade | Türkçe anlam yok | Türkçe açıklama yok | Örnek yok | Örneğin Türkçesi yok | Anlamsız tanım |')
    L.append('|---|---:|---:|---:|---:|---:|---:|')
    for key in sorted(k for k in t if k.startswith('expr:')):
        cat = key[5:]
        g = lambda c: a.by_cat.get(c, {}).get(cat, 0)
        L.append(f"| {cat} | {t[key]} | {g('expr_no_tr')} | {g('expr_en_only_def')} | {g('expr_no_example')} | "
                 f"{g('expr_example_no_tr')} | {g('expr_junk_def')} |")
    L.append('\nTüm örnek listeleri: `samples/<kontrol>.tsv` (her kontrol için ilk 400 kayıt).\n')
    with open(os.path.join(out, 'report.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(L))
    return summary, worse


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('db')
    ap.add_argument('--out', default='qa-report')
    ap.add_argument('--top-words', type=int, default=5000)
    ap.add_argument('--baseline')
    ap.add_argument('--write-baseline', action='store_true')
    args = ap.parse_args()
    a = Audit(args.db, args.top_words)
    a.exprs()
    a.words()
    a.families()
    baseline = None
    if args.baseline and os.path.exists(args.baseline) and not args.write_baseline:
        with open(args.baseline, encoding='utf-8') as f:
            baseline = json.load(f)
    summary, worse = write_report(a, args.out, baseline, args.db)
    if args.write_baseline and args.baseline:
        with open(args.baseline, 'w', encoding='utf-8') as f:
            json.dump({'counts': summary['counts'], 'totals': summary['totals']}, f, indent=1, sort_keys=True)
    for k, (kind, name, _) in CHECKS.items():
        print(f'{kind:8} {a.counts.get(k, 0):7}  {k}  {name}')
    if worse:
        print('WORSE than baseline:', ', '.join(worse), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()

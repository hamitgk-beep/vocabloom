"""Builds the Turkish part of the free library from public-domain texts.

Sources: Turkish Wikisource (tr.wikisource.org). Only authors who died in 1955
or earlier are taken: in Turkey a work is protected for 70 years after its
author's death, so their works are in the public domain. Folk tales
(Nasreddin Hoca) have no author.

Each short work (a story, tale or anecdote) becomes one story of the library.
Its level (A2 … C1) is estimated from how common its words are (OpenSubtitles
word list, FrequencyWords) and how long its sentences are.

  python3 tools/library_tr/build_library_tr.py tr_full.txt assets/library

writes catalog_tr.json and stories_tr.json.gz, and prints a report.
"""
import gzip
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from html.parser import HTMLParser

API = 'https://tr.wikisource.org/w/api.php'
UA = 'LibraryBuilder/1.0 (open-source reading app; python-urllib)'

# (name on Wikisource, year of death). Everyone here died in 1955 or earlier.
AUTHORS = [
    ('Ömer Seyfettin', 1920),
    ('Sait Faik Abasıyanık', 1954),
    ('Sabahattin Ali', 1948),
    ('Memduh Şevket Esendal', 1952),
    ('Hüseyin Rahmi Gürpınar', 1944),
    ('Halit Ziya Uşaklıgil', 1945),
    ('Ahmet Rasim', 1932),
    ('Ahmet Hikmet Müftüoğlu', 1927),
    ('Ahmet Mithat Efendi', 1912),
    ('Mehmet Rauf', 1931),
    ('Nabizade Nazım', 1893),
    ('Samipaşazade Sezai', 1936),
    ('Refik Halit Karay', 1965),  # left out below: protected until 2035
    ('Fatma Aliye Topuz', 1936),
    ('Emine Semiye', 1944),
    ('Musahipzade Celal', 1959),  # left out below
]
FOLK = ['Nasreddin Hoca']
LAST_DEATH = 1955
MIN_WORDS, MAX_WORDS = 120, 9000
PER_AUTHOR = 40


def api(**params):
    params.update(format='json', formatversion='2')
    url = API + '?' + urllib.parse.urlencode(params)
    for i in range(4):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.loads(r.read().decode('utf-8'))
            time.sleep(0.25)
            return data
        except Exception as e:  # noqa: BLE001
            print(f'  retry {i + 1}: {e}', file=sys.stderr)
            time.sleep(3 * (i + 1))
    return {}


def links_of(title):
    """Main-namespace pages linked from [title], in page order."""
    out = []
    d = api(action='parse', page=title, prop='links', redirects=1)
    for l in d.get('parse', {}).get('links', []):
        if l.get('ns') == 0 and l.get('exists'):
            out.append(l['title'])
    return out


def category_members(cat):
    out, cont = [], {}
    while True:
        d = api(action='query', list='categorymembers', cmtitle=cat, cmlimit='500', cmnamespace='0', **cont)
        out += [m['title'] for m in d.get('query', {}).get('categorymembers', [])]
        if 'continue' not in d:
            return out
        cont = {'cmcontinue': d['continue']['cmcontinue']}


def search(text, limit=100):
    d = api(action='query', list='search', srsearch=text, srnamespace='0', srlimit=str(limit))
    return [s['title'] for s in d.get('query', {}).get('search', [])]


SKIP_CLASSES = ('header', 'noprint', 'ws-noexport', 'licenseContainer', 'navbox', 'mw-editsection', 'reference',
                'toc', 'metadata', 'mw-references', 'ambox', 'catlinks', 'footer', 'mw-heading')


class Paras(HTMLParser):
    """Paragraph texts of a parsed Wikisource page, without its header,
    notes and navigation."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.paras, self.cur, self.skip, self.stack, self.links = [], None, 0, [], 0
        self.headings = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get('class') or ''
        skip = tag in ('table', 'style', 'script', 'sup', 'ol', 'ul') or any(c in cls for c in SKIP_CLASSES) or a.get('id') == 'toc'
        if tag in ('br',):
            if self.cur is not None and not self.skip:
                self.cur.append('\n')
            return
        if tag in ('img', 'hr', 'meta', 'link', 'input', 'wbr'):
            return
        self.stack.append((tag, skip))
        if skip:
            self.skip += 1
        if self.skip:
            return
        if tag in ('p', 'dd', 'h2', 'h3', 'h4', 'center', 'blockquote') and self.cur is None:
            self.cur = []
            self.kind = 'h' if tag.startswith('h') else 'p'
        if tag == 'a':
            self.links += 1

    def handle_endtag(self, tag):
        while self.stack:
            t, skip = self.stack.pop()
            if skip:
                self.skip -= 1
            if t == tag:
                break
        if tag in ('p', 'dd', 'h2', 'h3', 'h4', 'center', 'blockquote') and self.cur is not None and not self.skip:
            text = re.sub(r'[ \t ]+', ' ', ''.join(self.cur))
            text = '\n'.join(l.strip() for l in text.split('\n')).strip()
            if text:
                (self.headings if self.kind == 'h' else self.paras).append(text)
                if self.kind == 'h':
                    self.paras.append('\u0000' + text)
            self.cur = None

    def handle_data(self, data):
        if self.cur is not None and not self.skip:
            self.cur.append(data)


def page_text(title):
    d = api(action='parse', page=title, prop='text|displaytitle', redirects=1, disableeditsection=1)
    p = d.get('parse')
    if not p:
        return None, None, 0
    h = Paras()
    h.feed(p.get('text', ''))
    return p.get('title', title), h.paras, len(re.findall(r'<a ', p.get('text', '')))


TR_LETTERS = set('çğıöşüÇĞİÖŞÜâîûÂÎÛ')
ranks = {}


def load_ranks(path):
    with open(path, encoding='utf-8') as f:
        for i, line in enumerate(f):
            w = line.split(' ')[0]
            if w and w not in ranks:
                ranks[w] = i
            if i > 300000:
                break


def lower(s):
    return s.replace('I', 'ı').replace('İ', 'i').lower()


def stats(text):
    sentences = [s for s in re.split(r'(?<=[.!?…])["\'”’»)]*\s+', text) if re.search(r'\w', s)]
    known = rare = total = 0
    for s in sentences:
        toks = re.findall(r"[A-Za-zÇĞİÖŞÜçğıöşüÂÎÛâîû]+", s)
        total += len(toks)
        for i, t in enumerate(toks):
            if i > 0 and t[0].isupper():
                continue
            r = ranks.get(lower(t))
            if r is None:
                r = ranks.get(lower(t).replace('â', 'a').replace('î', 'i').replace('û', 'u'), 10 ** 6)
            known += 1
            rare += r > 5000
    rare_pct = 100 * rare / max(1, known)
    msl = total / max(1, len(sentences))
    return rare_pct + 0.6 * msl, rare_pct, msl, total


def looks_turkish(text):
    letters = sum(c.isalpha() for c in text)
    tr = sum(c in TR_LETTERS for c in text)
    arabic = sum('؀' <= c <= 'ۿ' for c in text)
    return letters > 0 and arabic < 10 and tr / letters > 0.012


def clean(paras, title):
    out = []
    for p in paras:
        if p.startswith('\u0000'):
            h = p[1:].strip()
            if h and lower(h) != lower(title) and len(h) < 80:
                out.append('\u0000' + h)
            continue
        p = re.sub(r'\[\d+\]', '', p).strip()
        if not p or re.fullmatch(r'[\W\d_]+', p):
            continue
        out.append(p)
    # Drop a trailing heading with nothing after it.
    while out and out[-1].startswith('\u0000'):
        out.pop()
    return out


def markdown(title, paras):
    body = []
    for p in paras:
        if p.startswith('\u0000'):
            body.append('**' + p[1:] + '**')
        else:
            body.append(p.replace('\n', '  \n'))
    return f'# {title}\n\n' + '\n\n'.join(body) + '\n'


def candidates(name):
    seen, out = set(), []
    for t in links_of(f'Yazar:{name}') + category_members(f'Kategori:{name}') + category_members(f'Kategori:{name} eserleri'):
        if t not in seen and not t.startswith(('Yazar:', 'Kategori:')):
            seen.add(t)
            out.append(t)
    return out


def main():
    load_ranks(sys.argv[1])
    out_dir = sys.argv[2]
    items, texts = [], {}
    report = []
    seen_text = set()

    def take(title, author, folk=False):
        t, paras, nlinks = page_text(title)
        if not paras:
            return 'empty'
        paras = clean(paras, t)
        text = '\n'.join(p for p in paras if not p.startswith('\u0000'))
        words = len(re.findall(r'\w+', text))
        if words < MIN_WORDS:
            # An index of a book's parts or of anecdotes: look one level down.
            return f'short ({words} words, {nlinks} links)'
        if words > MAX_WORDS:
            return f'long ({words} words)'
        if not looks_turkish(text):
            return 'not Latin-script Turkish'
        key = text[:400]
        if key in seen_text:
            return 'duplicate'
        seen_text.add(key)
        score, rare, msl, total = stats(text)
        sid = 'trws-' + re.sub(r'[^a-z0-9]+', '-', lower(t).translate(str.maketrans('çğıöşüâîû', 'cgiosuaiu'))).strip('-')[:60]
        base, k = sid, 2
        while sid in texts:
            sid = f'{base}-{k}'
            k += 1
        display = t.split('/')[-1].strip()
        items.append({
            'id': sid, 'kind': 'story', 'title': display, 'author': None if folk else author, 'level': None,
            'words': total, 'license': 'Public domain',
            'credit': (f'{author}. ' if not folk else 'Halk anlatısı. ') + 'Vikikaynak (tr.wikisource.org)',
            'source': 'https://tr.wikisource.org/wiki/' + urllib.parse.quote(t.replace(' ', '_')),
            'pics': 0, 'lang': 'tr', '_score': score, '_rare': rare, '_msl': msl,
        })
        texts[sid] = markdown(display, paras)
        return f'ok {total} words, rare {rare:.1f}%, sentence {msl:.1f}'

    for name, died in AUTHORS:
        if died > LAST_DEATH:
            report.append(f'## {name} (d. {died}): left out, not yet public domain')
            continue
        cands = candidates(name)
        report.append(f'## {name} (d. {died}): {len(cands)} pages')
        n = 0
        for c in cands:
            if n >= PER_AUTHOR:
                break
            r = take(c, name)
            report.append(f'- {c}: {r}')
            if r.startswith('ok'):
                n += 1
            elif r.startswith('short') and n < PER_AUTHOR:
                # A collection: its own pages are the stories.
                for sub in [x for x in links_of(c) if x.startswith(c + '/')][:PER_AUTHOR - n]:
                    r2 = take(sub, name)
                    report.append(f'  - {sub}: {r2}')
                    n += r2.startswith('ok')
    for name in FOLK:
        cands = candidates(name) + [t for t in search(f'{name} fıkra', 50)]
        report.append(f'## {name} (folk): {len(cands)} pages')
        n = 0
        for c in dict.fromkeys(cands):
            if n >= PER_AUTHOR:
                break
            r = take(c, name, folk=True)
            report.append(f'- {c}: {r}')
            n += r.startswith('ok')

    # Levels: the easiest quarter B1 (the shortest, plainest anecdotes A2),
    # the hardest quarter C1, the rest B2. These are literary texts for adults.
    items.sort(key=lambda c: c['_score'])
    n = len(items)
    for i, c in enumerate(items):
        q = i / max(1, n - 1)
        c['level'] = 'B1' if q < 0.25 else ('C1' if q >= 0.75 else 'B2')
        if c['words'] < 600 and c['_score'] < (items[n // 4]['_score'] if n else 0):
            c['level'] = 'A2'
    levels = ['A1', 'A2', 'B1', 'B2', 'C1']
    items.sort(key=lambda c: (levels.index(c['level']), c['words']))
    report.insert(0, f'# Turkish library: {n} texts\n')
    report.insert(1, 'levels: ' + json.dumps({l: sum(c["level"] == l for c in items) for l in levels}) + '\n')
    for c in items:
        report.append(f'{c["level"]} {c["words"]:5} rare={c["_rare"]:.1f} sl={c["_msl"]:.1f} {c["title"]} ({c["author"] or "folk"})')
        for k in ('_score', '_rare', '_msl'):
            c.pop(k)
    with open(f'{out_dir}/catalog_tr.json', 'w', encoding='utf-8') as f:
        json.dump(items, f, ensure_ascii=False, indent=0)
    with gzip.open(f'{out_dir}/stories_tr.json.gz', 'wt', encoding='utf-8') as f:
        json.dump(texts, f, ensure_ascii=False)
    print('\n'.join(report))


if __name__ == '__main__':
    main()

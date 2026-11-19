"""Builds the Turkish part of the free library from public-domain texts.

Sources: Turkish Wikisource (tr.wikisource.org), read from its public
database dump (no requests to the live site). Only authors who died in 1955
or earlier are taken: in Turkey a work is protected for 70 years after its
author's death, so their works are in the public domain. Folk tales
(Nasreddin Hoca) have no author.

Each short work (a story, tale or anecdote) becomes one story of the library.
Its level (A2 … C1) is estimated from how common its words are (OpenSubtitles
word list, FrequencyWords) and how long its sentences are.

  python3 tools/library_tr/build_library_tr.py tr_full.txt assets/library trwikisource-pages-articles.xml.bz2

writes catalog_tr.json and stories_tr.json.gz, and prints a report.
"""
import gzip
import json
import re
import sys
from collections import Counter
import urllib.parse

DUMP_NOTE = 'trwikisource-latest-pages-articles.xml(.bz2) from dumps.wikimedia.org'

# (name on Wikisource, year of death). Only those who died in 1955 or earlier are used.
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
    ('Fatma Aliye Topuz', 1936),
    ('Emine Semiye', 1944),
    ('Yakup Kadri Karaosmanoğlu', 1974),
    ('Refik Halit Karay', 1965),
    ('Reşat Nuri Güntekin', 1956),
]
FOLK = ['Nasreddin Hoca']  # also anonymous folk tales and anecdotes (masal, fıkra)
LAST_DEATH = 1955
MIN_WORDS, MAX_WORDS = 120, 9000
PER_AUTHOR = 60


def read_dump(path):
    """(main pages: title -> wikitext, Page-namespace pages: title -> wikitext)."""
    import bz2
    import xml.etree.ElementTree as ET
    opener = bz2.open if path.endswith('.bz2') else open
    main, pages, authors = {}, {}, {}
    ns_page, ns_author = set(), set()
    with opener(path, 'rb') as f:
        title = ns = None
        for ev, el in ET.iterparse(f, events=('end',)):
            tag = el.tag.rsplit('}', 1)[-1]
            if tag == 'namespace':
                if (el.text or '').strip() in ('Sayfa', 'Page'):
                    ns_page.add(el.get('key'))
                if (el.text or '').strip() in ('Yazar', 'Author'):
                    ns_author.add(el.get('key'))
            elif tag == 'title':
                title = el.text
            elif tag == 'ns':
                ns = el.text
            elif tag == 'text':
                text = el.text or ''
                if ns == '0' and not text.lstrip().lower().startswith('#yönlendir') and not text.lstrip().lower().startswith('#redirect'):
                    main[title] = text
                elif ns in ns_page:
                    pages[title.split(':', 1)[1]] = text
                elif ns in ns_author:
                    authors[title.split(':', 1)[1]] = text
            elif tag == 'page':
                el.clear()
    return main, pages, authors


def death_year(wt):
    """The year an author died, from their Wikisource page, or None."""
    for rx in (r'ölüm[ _]?(?:yılı|tarihi|yıl)?\s*=\s*\[*(\d{3,4})', r'(?:deathyear|death_year|death)\s*=\s*\[*(\d{3,4})',
               r'Kategori:(\d{3,4})[^\]]*(?:ölen|vefat)', r'\(\s*\d{3,4}\s*[-–—]\s*(\d{3,4})\s*\)'):
        m = re.search(rx, wt, re.I)
        if m:
            return int(m.group(1))
    return None


_KEEP = {'center', 'c', 'ortala', 'büyük', 'küçük', 'kalın', 'smaller', 'larger', 'big', 'small', 'sc', 'nowrap', 'ortalı', 'blok ortala'}


def _templates(t):
    # Innermost first; formatting templates keep their text.
    rx = re.compile(r'\{\{([^{}]*)\}\}')
    for _ in range(12):
        def rep(m):
            parts = m.group(1).split('|')
            name = parts[0].strip().lower()
            if name in _KEEP and len(parts) > 1:
                return parts[-1].split('=', 1)[-1] if '=' in parts[-1] and len(parts[-1].split('=', 1)[0]) < 12 else parts[-1]
            return ''
        n = rx.sub(rep, t)
        if n == t:
            break
        t = n
    return t


def header_author(wt):
    m = re.search(r'\|\s*(?:yazar|author)\s*=\s*((?:\[\[[^\]]*\]\]|[^|}\n])*)', wt, re.I)
    if not m:
        return ''
    a = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]', r'\1', m.group(1))
    return a.replace('Yazar:', '').strip()


def resolve_pages(wt, pages):
    def rep(m):
        attrs = dict(re.findall(r'(\w+)\s*=\s*"?([^"\s/>]+)"?', m.group(0)))
        idx = attrs.get('index')
        if not idx:
            return ''
        try:
            a, b = int(attrs.get('from', 1)), int(attrs.get('to', attrs.get('from', 1)))
        except ValueError:
            return ''
        out = []
        for n in range(a, min(b, a + 400) + 1):
            pt = pages.get(f'{idx}/{n}', '')
            pt = re.sub(r'<noinclude>.*?</noinclude>', '', pt, flags=re.S)
            out.append(pt)
        return '\n'.join(out)
    return re.sub(r'<pages\b[^>]*/?>', rep, wt, flags=re.I)


def wikitext_paras(wt, pages):
    t = resolve_pages(wt, pages)
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r'<ref[^>/]*/>', '', t, flags=re.I)
    t = re.sub(r'<ref[^>]*>.*?</ref>', '', t, flags=re.S | re.I)
    t = re.sub(r'<noinclude>.*?</noinclude>', '', t, flags=re.S)
    t = re.sub(r'\{\|.*?\|\}', '', t, flags=re.S)
    t = _templates(t)
    t = re.sub(r'\[\[(?:Dosya|File|Resim|Image|Kategori|Category)[^\]]*\]\]', '', t, flags=re.I)
    t = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]', r'\1', t)
    t = re.sub(r'\[https?://\S+\s+([^\]]*)\]', r'\1', t)
    t = re.sub(r'\[https?://\S+\]', '', t)
    t = re.sub(r"'{2,}", '', t)
    t = re.sub(r'<br\s*/?>', '\n', t, flags=re.I)
    t = re.sub(r'</?(?:poem|div|span|center|p|small|big|font|sup|sub|u|i|b|s|blockquote|section)[^>]*>', '\n', t, flags=re.I)
    t = re.sub(r'<[^>]+>', '', t)
    t = html_unescape(t)
    paras = []
    for block in re.split(r'\n\s*\n', t):
        lines = [l.strip() for l in block.split('\n')]
        lines = [l for l in lines if l and not l.startswith(('__', '{{', '}}', '|', '!'))]
        if not lines:
            continue
        h = re.fullmatch(r'=+\s*(.*?)\s*=+', lines[0])
        if h and len(lines) == 1:
            paras.append('\u0000' + h.group(1))
            continue
        lines = [re.sub(r'^[:*#;]+\s*', '', l) for l in lines]
        # Prose wraps freely; a poem keeps its lines.
        short = sum(len(l) < 60 for l in lines) > len(lines) * 0.6 and len(lines) > 2
        paras.append('\n'.join(lines) if short else ' '.join(lines))
    return paras


def html_unescape(t):
    import html
    return html.unescape(t)


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


def main():
    load_ranks(sys.argv[1])
    out_dir = sys.argv[2]
    main_pages, page_ns, author_pages = read_dump(sys.argv[3])
    items, texts = [], {}
    report = [f'dump: {len(main_pages)} main pages, {len(page_ns)} scan pages, {len(author_pages)} author pages']
    seen_text = set()
    # Every author with a known year of death: from the list above, otherwise
    # from their Wikisource author page.
    allowed = {a: d for a, d in AUTHORS}
    for name, wt in author_pages.items():
        if name not in allowed:
            d = death_year(wt)
            if d:
                allowed[name] = d
    report.append(f'authors with a known year of death: {len(allowed)}, public domain: {sum(d <= LAST_DEATH for d in allowed.values())}')
    keys = {name: lower(name) for name in allowed}
    by_author = {}
    unknown = Counter()
    cat_count = Counter()
    for title, wt in main_pages.items():
        a = lower(header_author(wt))
        linked = {lower(m) for m in re.findall(r'\[\[\s*(?:Yazar|Author)\s*:\s*([^|\]]+)', wt)}
        hit = None
        for name, k in keys.items():
            if (a and (k in a or a in k and len(a) > 5)) or k in linked:
                hit = name
                break
        cats = [lower(c) for c in re.findall(r'\[\[\s*(?:Kategori|Category)\s*:\s*([^|\]]+)', wt)]
        if hit:
            by_author.setdefault(hit, []).append(title)
        elif any(lower(f) in a or lower(f) in lower(title) for f in FOLK) or (not a and any(
                w in c for c in cats for w in ('masal', 'fıkra', 'halk hikâye', 'halk hikaye', 'nasreddin'))):
            by_author.setdefault(FOLK[0], []).append(title)
        else:
            unknown[a or '(no author)'] += 1
            if not a:
                for c in cats:
                    cat_count[c] += 1
    report.append('categories of pages with no author: ' + ', '.join(f'{k} {n}' for k, n in cat_count.most_common(60)))
    report.append('most common authors with no year of death: ' + ', '.join(f'{k} {n}' for k, n in unknown.most_common(40)))

    def take(t, author, folk=False):
        paras = clean(wikitext_paras(main_pages[t], page_ns), t)
        text = '\n'.join(p for p in paras if not p.startswith('\u0000'))
        words = len(re.findall(r'\w+', text))
        if words < MIN_WORDS:
            return f'short ({words} words)'
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
        display = t.split('/')[-1].strip() if '/' in t and len(t.split('/')[-1]) > 3 else t
        items.append({
            'id': sid, 'kind': 'story', 'title': display, 'author': None if folk else author, 'level': None,
            'words': total, 'license': 'Public domain',
            'credit': (f'{author}. ' if not folk else 'Halk anlatısı (anonim). ') + 'Vikikaynak (tr.wikisource.org)',
            'source': 'https://tr.wikisource.org/wiki/' + urllib.parse.quote(t.replace(' ', '_')),
            'pics': 0, 'lang': 'tr', '_score': score, '_rare': rare, '_msl': msl,
        })
        texts[sid] = markdown(display, paras)
        return f'ok {total} words, rare {rare:.1f}%, sentence {msl:.1f}'

    order = sorted(by_author, key=lambda n: -len(by_author[n]))
    for name in order:
        died = allowed.get(name)
        titles = sorted(by_author.get(name, []))
        if died is not None and died > LAST_DEATH:
            report.append(f'## {name} (d. {died}): {len(titles)} pages, left out (not yet public domain)')
            continue
        report.append(f'## {name}' + (f' (d. {died})' if died else ' (folk)') + f': {len(titles)} pages')
        n = 0
        for t in titles:
            if n >= PER_AUTHOR:
                break
            r = take(t, name, folk=died is None)
            report.append(f'- {t}: {r}')
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
    print('\n# Samples\n')
    for c in items[:: max(1, len(items) // 6)][:6]:
        print(f'## {c["title"]} ({c["level"]})\n')
        print(texts[c['id']][:1500])
        print()


if __name__ == '__main__':
    main()

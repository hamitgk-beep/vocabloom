"""Builds the Turkish books of the free library (public-domain works).

Two sources, both read without touching the live sites' pages:

* Turkish Wikisource (its database dump): the short works of each
  public-domain author, and the Nasreddin Hoca anecdotes, are gathered into
  books with one chapter per work, the way printed collections are made.
  Every short anecdote is kept, also the very short ones that the story
  list leaves out.
* Project Gutenberg: its books in Turkish (Latin script) by authors who died
  in 1955 or earlier (in Turkey a work is protected for 70 years after its
  author's death), read from its catalog (pg_catalog.csv) and plain-text
  files.

  python3 tools/library_tr/build_books_tr.py tr_full.txt trws.xml.bz2 pg_catalog.csv pg_texts/ .

writes library/books/<id>.md.gz (downloaded by the app when a book is first
opened) and assets/library/catalog_tr_books.json, and prints a report.
pg_texts/ holds pg<n>.txt for the Gutenberg books listed by --list.

  python3 tools/library_tr/build_books_tr.py --list pg_catalog.csv

prints the numbers of the Gutenberg books to download.
"""
import csv
import gzip
import json
import os
import re
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_library_tr as L  # noqa: E402

LAST_DEATH = L.LAST_DEATH
STORIES_PER_BOOK = 25
ANECDOTES_PER_BOOK = 60
MIN_BOOK_WORDS = 1500


def slug(s):
    return re.sub(r'[^a-z0-9]+', '-', L.lower(s).translate(str.maketrans('çğıöşüâîû', 'cgiosuaiu'))).strip('-')[:50]


def tr_upper(s):
    return s.replace('i', 'İ').replace('ı', 'I').upper()


def tr_title(s):
    """'BİRİNCİ BÖLÜM' -> 'Birinci Bölüm' (Turkish dotted and dotless i)."""
    return ' '.join(tr_upper(w[:1]) + L.lower(w[1:]) for w in s.split(' '))


def level_of(score):
    # Same scale as the stories: rare-word share plus sentence length.
    return 'B1' if score < 52 else 'B2' if score < 62 else 'C1'


# ---------------------------------------------------------------- Gutenberg

def gutenberg_candidates(catalog):
    """(number, title, author, died) of public-domain Turkish texts."""
    out = []
    with open(catalog, encoding='utf-8') as f:
        for row in csv.DictReader(f):
            if row.get('Type') != 'Text':
                continue
            langs = [x.strip() for x in (row.get('Language') or '').split(';')]
            if 'tr' not in langs:
                continue
            authors = row.get('Authors') or ''
            years = [int(y) for y in re.findall(r'\d{4}\s*-\s*(\d{4})', authors)]
            died = max(years) if years else None
            if died is None or died > LAST_DEATH:
                continue
            name = re.split(r',\s*\d', authors.split(';')[0])[0].strip()
            # "Uşaklıgil, Halit Ziya" -> "Halit Ziya Uşaklıgil"
            if ',' in name:
                last, first = [x.strip() for x in name.split(',', 1)]
                name = f'{first} {last}'
            name = re.sub(r'\s*\[.*?\]', '', name)
            title = re.sub(r'\s+', ' ', (row.get('Title') or '').replace('\n', ' ')).strip()
            out.append((int(row['Text#']), title, name, died))
    return out


_CHAPTER = re.compile(
    r'^(?:[IVXLC]+\.?|\d{1,3}\.?|(?:BİRİNCİ|İKİNCİ|ÜÇÜNCÜ|DÖRDÜNCÜ|BEŞİNCİ|ALTINCI|YEDİNCİ|SEKİZİNCİ|DOKUZUNCU|ONUNCU)\b.*'
    r'|(?:BÖLÜM|FASIL|KISIM)\b.*|.*\b(?:BÖLÜM|FASIL|KISIM)\s*[IVXLC\d]*\.?)$')


def gutenberg_book(path, title):
    raw = open(path, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
    s = re.search(r'\*\*\*\s*START OF.*?\*\*\*', raw)
    e = re.search(r'\*\*\*\s*END OF', raw)
    body = raw[s.end() if s else 0:e.start() if e else len(raw)]
    blocks = [b.strip() for b in re.split(r'\n\s*\n', body) if b.strip()]
    # Leading credits ("Produced by ...") and a title page are not text.
    while blocks and re.search(r'produced by|transcribed|e-text|ebook|gutenberg', blocks[0], re.I):
        blocks.pop(0)
    chapters, cur, name = [], [], None
    for b in blocks:
        one = ' '.join(x.strip() for x in b.split('\n'))
        if len(one) < 60 and '\n' not in b.strip() and _CHAPTER.match(tr_upper(one.strip())):
            if cur:
                chapters.append((name, cur))
            cur, name = [], one.strip().rstrip('.')
            continue
        short = sum(len(x) < 60 for x in b.split('\n')) > len(b.split('\n')) * 0.6 and len(b.split('\n')) > 2
        cur.append('  \n'.join(x.strip() for x in b.split('\n')) if short else one)
    if cur:
        chapters.append((name, cur))
    # No headings found: parts of about 2500 words.
    if len(chapters) < 2:
        paras = [p for _, ps in chapters for p in ps]
        chapters, part, n = [], [], 0
        for p in paras:
            part.append(p)
            n += len(p.split())
            if n > 2500:
                chapters.append((None, part))
                part, n = [], 0
        if part:
            chapters.append((None, part))
    md = []
    for i, (h, ps) in enumerate(chapters):
        md.append(f'# {tr_title(h) if h and h == tr_upper(h) else h or f"Bölüm {i + 1}"}')
        md.extend(ps)
    return '\n\n'.join(md) + '\n', len(chapters)


# ---------------------------------------------------------------- Wikisource

def wikisource_groups(main_pages):
    """author -> sorted page titles, as in build_library_tr (authors with a
    known year of death, and the folk anecdotes under Nasreddin Hoca)."""
    keys = {name: L.lower(name) for name, _ in L.AUTHORS}
    groups = {}
    for title, wt in main_pages.items():
        a = L.lower(L.header_author(wt))
        linked = {L.lower(m) for m in re.findall(r'\[\[\s*(?:Yazar|Author)\s*:\s*([^|\]]+)', wt)}
        cats = [L.lower(c) for c in re.findall(r'\[\[\s*(?:Kategori|Category)\s*:\s*([^|\]]+)', wt)]
        hit = None
        for name, k in keys.items():
            if (a and (k in a or a in k and len(a) > 5)) or k in linked or (not a and any(k in c for c in cats)):
                hit = name
                break
        if hit is None and (any(L.lower(f) in a or L.lower(f) in L.lower(title) for f in L.FOLK) or (not a and any(
                w in c for c in cats for w in ('nasreddin', 'fıkra')))):
            hit = L.FOLK[0]
        if hit:
            groups.setdefault(hit, []).append(title)
    return {k: sorted(v) for k, v in groups.items()}


def work_text(t, main_pages, page_ns):
    paras = L.clean(L.wikitext_paras(main_pages[t], page_ns), t)
    text = '\n'.join(p for p in paras if not p.startswith('\u0000'))
    return paras, text


def display_title(t):
    d = t.split('/')[-1].strip() if '/' in t and len(t.split('/')[-1]) > 3 else t
    return re.sub(r'\s*\([^)]*\)\s*$', '', d) or d


def main():
    if sys.argv[1] == '--list':
        for n, title, author, died in gutenberg_candidates(sys.argv[2]):
            print(n)
        return
    L.load_ranks(sys.argv[1])
    dump, catalog, pg_dir, root = sys.argv[2:6]
    books_dir = os.path.join(root, 'library', 'books')
    os.makedirs(books_dir, exist_ok=True)
    items, report = [], []

    def add(bid, title, author, md, chapters, credit, source, level=None):
        text = re.sub(r'^#.*$', '', md, flags=re.M)
        score, rare, msl, total = L.stats(text)
        if total < MIN_BOOK_WORDS:
            report.append(f'- {title}: left out ({total} words)')
            return
        data = gzip.compress(md.encode('utf-8'), 9)
        open(os.path.join(books_dir, f'{bid}.md.gz'), 'wb').write(data)
        lv = level or level_of(score)
        items.append({
            'id': bid, 'kind': 'book', 'title': title, 'author': author, 'level': lv, 'words': total,
            'chapters': chapters, 'size': len(data), 'license': 'Public domain', 'credit': credit,
            'source': source, 'pics': 0, 'lang': 'tr',
        })
        report.append(f'- {lv} {total:6} words, {chapters:3} chapters, rare {rare:.1f}%, sentence {msl:.1f}: {title} ({author or "folk"})')

    # Wikisource collections.
    main_pages, page_ns, _ = L.read_dump(dump)
    groups = wikisource_groups(main_pages)
    died = dict(L.AUTHORS)
    report.append('## Vikikaynak')
    for name in sorted(groups, key=lambda n: -len(groups[n])):
        folk = name == L.FOLK[0]
        if not folk and died.get(name, 9999) > LAST_DEATH:
            continue
        works, seen = [], set()
        for t in groups[name]:
            paras, text = work_text(t, main_pages, page_ns)
            words = len(re.findall(r'\w+', text))
            if words < (15 if folk else 300) or not L.looks_turkish(text) or text[:300] in seen:
                continue
            seen.add(text[:300])
            body = [('### ' + p[1:]) if p.startswith('\u0000') else p.replace('\n', '  \n') for p in paras]
            works.append((display_title(t), body, t))
        per = ANECDOTES_PER_BOOK if folk else STORIES_PER_BOOK
        # Parts of even size, none much bigger than [per].
        count = max(1, -(-len(works) // per))
        size = -(-len(works) // count) if works else 1
        parts = [works[i:i + size] for i in range(0, len(works), size)]
        for k, part in enumerate(parts):
            if folk:
                title = 'Nasreddin Hoca Fıkraları' + (f' {k + 1}' if len(parts) > 1 else '')
            else:
                title = f'{name}: Hikâyeler' + (f' {k + 1}' if len(parts) > 1 else '')
            md = '\n\n'.join(f'# {wt}\n\n' + '\n\n'.join(body) for wt, body, _ in part) + '\n'
            first = part[0][2]
            add(f'trb-{slug(title)}', title, None if folk else name, md, len(part),
                ('Halk anlatısı (anonim). ' if folk else f'{name}. ') + 'Vikikaynak (tr.wikisource.org)',
                'https://tr.wikisource.org/wiki/' + urllib.parse.quote((first.split('/')[0] if '/' in first else first).replace(' ', '_')),
                level='B1' if folk else None)

    # Project Gutenberg.
    report.append('## Project Gutenberg')
    for n, title, author, d in gutenberg_candidates(catalog):
        path = os.path.join(pg_dir, f'pg{n}.txt')
        if not os.path.exists(path):
            report.append(f'- {n} {title}: no text file')
            continue
        md, chapters = gutenberg_book(path, title)
        if not L.looks_turkish(md[:20000]):
            report.append(f'- {n} {title}: not Latin-script Turkish')
            continue
        add(f'trpg-{n}', title, author, md, chapters, f'{author}. Project Gutenberg', f'https://www.gutenberg.org/ebooks/{n}')

    levels = ['A1', 'A2', 'B1', 'B2', 'C1']
    items.sort(key=lambda c: (levels.index(c['level']), c['title']))
    with open(os.path.join(root, 'assets', 'library', 'catalog_tr_books.json'), 'w', encoding='utf-8') as f:
        json.dump(items, f, ensure_ascii=False, indent=0)
    print(f'# Turkish books: {len(items)}\n')
    print('\n'.join(report))


if __name__ == '__main__':
    main()

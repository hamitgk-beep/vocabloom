#!/usr/bin/env python3
"""Builds the in-app library of free, openly licensed English reading.

Sources (all usable in a free app with ads):
  * Short stories: Pratham Books / StoryWeaver, CC BY 4.0 (a few public domain),
    taken from https://github.com/global-asp/pb-source (folder `en`).
  * Books: public-domain classics from Project Gutenberg, taken from the
    GITenberg mirrors listed in books.tsv. The Project Gutenberg header and
    licence are removed, so the texts are plain public-domain works.

Every text is turned into the Markdown the app's importer already reads
(`# Title` starts a chapter). Short stories get an estimated CEFR level (A1 … C1)
from how common their words are (word frequencies in assets/dict.db) and how
long their sentences are. Old classics fool that formula (short everyday words,
old-fashioned style), so their level is set by hand in books.tsv, following the
levels graded-reader lists usually give them.

Outputs
  assets/library/catalog.json      list shown in the app (bundled)
  assets/library/stories.json.gz   every short story's text (bundled, small)
  library/books/<id>.md.gz         each book's text, downloaded when opened

Usage
  git clone --depth 1 https://github.com/global-asp/pb-source /tmp/pb-source
  python3 tools/library/build_library.py --stories /tmp/pb-source/en --books-cache /tmp/gut
  (books missing from --books-cache are downloaded from raw.githubusercontent.com)
"""
import argparse
import glob
import gzip
import hashlib
import html
import io
from html.parser import HTMLParser
import json
import math
import os
import re
import sqlite3
import sys
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LEVELS = ['A1', 'A2', 'B1', 'B2', 'C1']

# --------------------------------------------------------------- level estimate
_rank = {}


def load_ranks():
    db = sqlite3.connect(os.path.join(ROOT, 'assets', 'dict.db'))
    words = [r[0] for r in db.execute('SELECT word FROM wfreq ORDER BY n DESC')]
    for i, w in enumerate(words):
        _rank.setdefault(w, i + 1)
    # inflected forms take the rank of their lemma when that is more common
    for form, lemma in db.execute('SELECT form, lemma FROM exc'):
        if lemma in _rank:
            _rank[form] = min(_rank.get(form, 10 ** 9), _rank[lemma])


def _word_rank(w):
    best = _rank.get(w, 50000)
    for suf, rep in (("'s", ''), ('s', ''), ('es', ''), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e'),
                     ('ly', ''), ('ies', 'y'), ('ied', 'y'), ('er', ''), ('est', '')):
        if w.endswith(suf) and len(w) - len(suf) >= 3:
            best = min(best, _rank.get(w[: -len(suf)] + rep, 50000))
    return best


def stats(text):
    """(score, rare-word %, mean sentence length, words) for English text.

    rare-word % is the share of words outside the 2000 most common ones (names,
    places and sounds the dictionary does not know are left out)."""
    body = re.sub(r'^#.*$', ' ', text, flags=re.M)
    sentences = [s for s in re.split(r'(?<=[.!?])["\'”’)]*\s+', body) if re.search(r'[A-Za-z]', s)]
    known = rare = total = 0
    for s in sentences:
        toks = re.findall(r"[A-Za-z][A-Za-z']*", s)
        total += len(toks)
        for i, t in enumerate(toks):
            if i > 0 and t[0].isupper():
                continue
            r = _word_rank(t.lower().strip("'"))
            if r >= 50000:
                continue
            known += 1
            rare += r > 2000
    rare_pct = 100 * rare / max(1, known)
    msl = total / max(1, len(sentences))
    return rare_pct + 0.5 * msl, rare_pct, msl, total


# score limits between A1|A2, A2|B1, B1|B2, B2|C1 (checked against the stories'
# own reading levels on StoryWeaver and well-known graded classics)
_cuts = [12, 17, 20, 24]


def level(score):
    return LEVELS[sum(score >= c for c in _cuts)]


# Children's picture books: even the hardest are B1 at most; the few rare words
# (animal names, festival foods) make the formula overrate them.
_story_cuts = [12, 16.5]


def story_level(score):
    return LEVELS[sum(score >= c for c in _story_cuts)]


# Read and left out by hand: grammar or spelling mistakes the check above misses.
_excluded_stories = {'0288'}

_vocab = set()


def load_vocab():
    db = sqlite3.connect(os.path.join(ROOT, 'assets', 'dict.db'))
    for q in ('SELECT word FROM wd', 'SELECT form FROM exc', 'SELECT lemma FROM sense', 'SELECT word FROM wfreq'):
        _vocab.update(r[0] for r in db.execute(q))


def _known(w):
    if w in _vocab:
        return True
    for suf, rep in (("'s", ''), ('s', ''), ('es', ''), ('ed', ''), ('ed', 'e'), ('ing', ''), ('ing', 'e'), ('ly', ''),
                     ('ies', 'y'), ('ied', 'y'), ('er', ''), ('est', ''), ("n't", '')):
        if w.endswith(suf) and w[: -len(suf)] + rep in _vocab:
            return True
    return False


def unknown_words(text):
    """Lower-case words the dictionary does not know: misspellings, and words
    from other languages a learner cannot look up. Names and sounds
    ("Brrrr") are not counted."""
    toks = re.findall(r"[A-Za-z][A-Za-z']*", text)
    names = {t.lower() for t in toks if t[0].isupper()}
    return sorted({t for t in toks if t[0].islower() and len(t) > 2 and t not in names
                   and not re.search(r'(.)\1\1', t) and not _known(t.strip("'"))})


# --------------------------------------------------------------- short stories
def read_story(path):
    raw = open(path, encoding='utf-8').read().replace('\r\n', '\n')
    parts = re.split(r'^##\s*$', raw, flags=re.M)
    head, pages, meta = parts[0], parts[1:-1], parts[-1]
    title = re.sub(r'^#\s*', '', head.strip().split('\n')[0]).strip()
    info = dict(re.findall(r'^\*\s*([^:]+):\s*(.*)$', meta, flags=re.M))
    lic = info.get('License', '')
    if 'CC-BY' in lic and 'NC' not in lic and 'ND' not in lic:
        lic = 'CC BY 4.0'
    elif 'Public Domain' in lic:
        lic = 'Public domain'
    else:
        return None
    out = []
    for pg in pages:
        paras = []
        for p in re.split(r'\n\s*\n', pg.strip()):
            p = ' '.join(p.split())
            p = re.sub(r'[*_]+', '', p)
            if p:
                paras.append(p)
        out.append(paras)
    if not title or not any(out):
        return None
    credit = '; '.join(f'{k}: {info[k].strip()}' for k in ('Text', 'Illustration', 'Translation') if info.get(k, '').strip())
    return title, out, lic, credit


# --------------------------------------------------------------- Gutenberg books
_num = r'(\d+|[IVXLC]+|[Ii]|(?:ONE|TWO|THREE|FOUR|FIVE|SIX|SEVEN|EIGHT|NINE|TEN|ELEVEN|TWELVE|THIRTEEN|FOURTEEN|FIFTEEN|SIXTEEN|SEVENTEEN|EIGHTEEN|NINETEEN|TWENTY|THIRTY|FORTY|FIFTY|One|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|Eleven|Twelve|Thirteen|Fourteen|Fifteen|Sixteen|Seventeen|Eighteen|Nineteen|Twenty|Thirty|Forty|Fifty)(?:-[A-Za-z]+)?)'
_chapterish = re.compile(r'^(CHAPTER|Chapter|STAVE|Stave|ADVENTURE|LETTER|Letter)[ .]+' + _num + r'(?=$|[.:]|\s+[A-Z(\["\u201c\']|\s*--)')
_part = re.compile(r'^(BOOK|Book|PART|Part|VOLUME|Volume)\b[ .:]*([0-9IVXLCivxlc]+|[A-Z][A-Za-z-]*)\b.*$')
_roman = re.compile(r'^([IVXLC]+)\.?(\s+.*)?$')
_skip_titles = re.compile(r'^(CONTENTS|Contents|Table of Contents|ILLUSTRATIONS|List of Illustrations|INDEX|TRANSCRIBER|FOOTNOTES|'
                          r'CHAPTER|Chapter)(\s+TITLE|\s+Title|\s+PAGE|\s+Page)?\.?:?$')


_skip_norm = {'contents', 'table of contents', 'illustrations', 'list of illustrations', 'index', 'footnotes',
              'chapter', 'chapter title', 'chapter page', 'transcriber s note', 'transcriber s notes'}


def gutenberg_body(raw):
    raw = raw.replace('\ufeff', '').replace('\r\n', '\n').replace('\r', '\n')
    m = re.search(r'^\*\*\* ?START OF.*$', raw, flags=re.M)
    if m:
        raw = raw[m.end():]
    m = re.search(r'^\*\*\* ?END OF.*$|^End of (the )?Project Gutenberg', raw, flags=re.M | re.I)
    if m:
        raw = raw[: m.start()]
    raw = re.sub(r'\[Illustration[^\]]*\]', '', raw, flags=re.S)
    raw = re.sub(r'\[Footnote[^\]]*\]', '', raw, flags=re.S)
    raw = re.sub(r'\[Picture[^\]]*\]', '', raw, flags=re.S)
    return raw


def _is_heading(b):
    return len(b) < 80 and '\n' not in b.strip()


def _norm(t):
    return re.sub(r'[^a-z]+', ' ', t.lower()).strip()


def _toc_titles(blocks):
    """Titles listed under CONTENTS (one per line, or one per block)."""
    for k, b in enumerate(blocks):
        if re.match(r'^(CONTENTS|Contents|Table of Contents)\b', b.strip()):
            lines = []
            for bb in blocks[k + 1:k + 120]:
                ls = [x.strip() for x in bb.split('\n') if x.strip()]
                # wrapped prose (long lines, sentence ends): the list is over
                if any(len(x) > 80 for x in ls) or (len(ls) >= 3 and sum(map(len, ls)) / len(ls) > 55):
                    break
                lines += ls
            out = []
            for x in lines:
                x = re.sub(r'\s{2,}\d+$|\.{2,}.*$', '', x).strip()
                x = re.sub(r'^([IVXLC]+|\d+)\.\s+', '', x)
                if _norm(x) and _norm(x) not in ('page', 'chapter'):
                    out.append(_norm(x))
            return set(out)
    return set()


def book_markdown(raw, title, author, how='auto'):
    """Gutenberg plain text → app Markdown. [how] picks the chapter headings:
    auto (CHAPTER/STAVE/ADVENTURE/LETTER lines, else Roman numerals), caps
    (lines in capitals), toc (the titles listed under CONTENTS), none, or
    re:<regex> (re2:<regex> also takes two-line headings). PART/BOOK lines become sub-headings inside the next chapter."""
    body = gutenberg_body(raw)
    blocks = [b.strip() for b in re.split(r'\n\s*\n', body)]
    blocks = [b for b in blocks if b]

    def find(rx):
        return [i for i, b in enumerate(blocks) if _is_heading(b) and rx.match(' '.join(b.split()))]

    if how == 'auto':
        heads = find(_chapterish)
        if len(heads) < 3:
            heads = find(_roman)
    elif how == 'caps':
        heads = [i for i, b in enumerate(blocks)
                 if _is_heading(b) and re.search(r'[A-Z]{3}', b) and not re.search(r'[a-z]', b) and len(b.split()) <= 12]
    elif how == 'toc':
        toc = _toc_titles(blocks)
        # (a CONTENTS list written one title per block matches too; those
        # empty sections are dropped below)
        heads = [i for i, b in enumerate(blocks)
                 if _is_heading(b) and not re.search(r'[,;]|^["\u201c\']', b)
                 and _norm(re.sub(r'^([IVXLC]+|\d+)\.\s+', '', ' '.join(b.split()))) in toc]
    elif how == 'none':
        heads = []
    elif how.startswith('re2:'):
        # like re:, for headings with the chapter name on a second line
        rx = re.compile(how[4:])
        heads = [i for i, b in enumerate(blocks)
                 if len(b) < 80 and b.count('\n') <= 1 and rx.match(' '.join(b.split()))]
    else:
        heads = find(re.compile(how[3:]))
    hs = set(heads)
    parts = set(find(_part)) - hs
    sections = []  # (title, [paragraphs])
    cur = None
    pending_part = None
    i = 0
    while i < len(blocks):
        b = blocks[i]
        if i in hs:
            t = ' '.join(b.split())
            # "CHAPTER I" with its name in the next short block
            if (i + 1 < len(blocks) and (i + 1) not in hs and len(blocks[i + 1]) < 160
                    and blocks[i + 1].count('\n') <= 2 and re.match(r'^\S+(\s+\S+)?\.?$', t)):
                nxt = ' '.join(blocks[i + 1].split())
                if re.match(r'^["\u201c\']', nxt):
                    pass
                elif (not re.search(r'[.!?,;]["\'\u201d]?$', nxt) and len(nxt.split()) <= 10) or not re.search(r'[a-z]', nxt):
                    t = f'{t.rstrip(".:")}. {_title_case(nxt)}'
                    i += 1
            cur = (t, [])
            sections.append(cur)
            if pending_part:
                cur[1].append('### ' + _title_case(pending_part))
                pending_part = None
        elif i in parts:
            pending_part = ' '.join(b.split())
        elif cur is not None or not heads:
            if cur is None:
                cur = (title, [])
                sections.append(cur)
            p = ' '.join(b.split())
            p = re.sub(r'(?<![A-Za-z])_([^_]+)_(?![A-Za-z])', r'\1', p)
            if not re.fullmatch(r'[*\s.]+', p):
                cur[1].append(p)
        i += 1
    # Drop the table of contents (headings with little under them) and lists.
    sections = [s for s in sections if not _skip_titles.match(s[0]) and re.sub(r'[^a-z0-9]+', ' ', s[0].lower()).strip() not in _skip_norm]
    # "XII. The Copper Beeches" / "1" → named like the book's other headings
    kws = [m.group(1).capitalize() for t, _ in sections for m in [re.match(r'^(CHAPTER|Chapter|STAVE|Stave|ADVENTURE|Adventure)\b', t)] if m]
    kw = max(set(kws), key=kws.count) if kws else 'Chapter'
    sections = [((f'{kw} {t}' if re.fullmatch(r'([IVXLC]+|\d+)\.?(\s.*)?', t) else t), ps) for t, ps in sections]
    words = lambda s: sum(len(p.split()) for p in s[1] if not p.startswith('###'))
    while len(sections) > 1 and words(sections[0]) < 40:
        sections.pop(0)
    sections = [s for s in sections if words(s) > 0]
    md = [f'# {_chapter_title(t)}\n\n' + '\n\n'.join(ps) for t, ps in sections]
    return '\n\n'.join(md) + '\n', len(sections)


def _chapter_title(t):
    t = re.sub(r'(?<![A-Za-z])_([^_]+)_(?![A-Za-z])', r'\1', t)
    m = re.match(r'^(CHAPTER|STAVE|ADVENTURE|LETTER)\b(.*)$', t)
    if m:
        t = m.group(1).capitalize() + m.group(2)
    m = re.match(r'^((?:Chapter|Stave|Adventure|Letter)\s+)(\S+?)([.:]?\s+)(.*)$', t)
    if m:
        n = m.group(2) if re.fullmatch(r'[IVXLC0-9]+', m.group(2)) else m.group(2).capitalize()
        rest = m.group(4)
        rest = _title_case(rest) if not re.search(r'[a-z]', re.sub(r'--.*', '', rest)) else rest
        return m.group(1) + n + m.group(3) + rest
    return _title_case(t)


def _title_case(t):
    if re.search(r'[a-z]', re.sub(r'--.*', '', t)):
        return t
    small = {'a', 'an', 'the', 'of', 'and', 'in', 'on', 'to', 'at', 'by', 'for', 'or', 'with', 'from'}
    out = []
    for k, w in enumerate(t.lower().split()):
        if re.fullmatch(r'[ivxlc]+[.:]?', w):
            out.append(w.upper())
        elif k and w in small:
            out.append(w)
        else:
            out.append(w[:1].upper() + w[1:])
    return ' '.join(out)


def read_books_tsv():
    rows = []
    for line in open(os.path.join(os.path.dirname(__file__), 'books.tsv'), encoding='utf-8'):
        if line.startswith('#') or not line.strip():
            continue
        f = line.rstrip('\n').split('\t')
        gid, repo, fname, title, author, lvl = f[:6]
        how = f[6] if len(f) > 6 and f[6] else 'auto'
        assert lvl in LEVELS, line
        rows.append((gid, repo, fname, title, author, lvl, how))
    return rows


def fetch_book(cache, gid, repo, fname):
    path = os.path.join(cache, f'{gid}.txt')
    if os.path.exists(path):
        return open(path, encoding='utf-8', errors='replace').read()
    for f in [fname, f'{gid}.txt', f'{gid}-0.txt', f'{gid}-8.txt']:
        clone = os.path.join(cache, gid, f)
        if f != '?' and os.path.exists(clone):
            data = open(clone, 'rb').read()
            try:
                return data.decode('utf-8')
            except UnicodeDecodeError:
                return data.decode('latin-1')
    for f in [fname, f'{gid}.txt', f'{gid}-0.txt', f'{gid}-8.txt']:
        if f == '?':
            continue
        try:
            data = urllib.request.urlopen(f'https://raw.githubusercontent.com/GITenberg/{repo}/master/{f}', timeout=60).read()
        except Exception:
            continue
        os.makedirs(cache, exist_ok=True)
        open(path, 'wb').write(data)
        return data.decode('utf-8', errors='replace')
    raise SystemExit(f'could not download Gutenberg #{gid}')



# --------------------------------------------------------------- pictures
# A picture in the app's Markdown: ![description](address "caption"). Short
# addresses keep the bundled stories small; the app expands them:
#   pb:0002/03.jpg  -> the Pratham Books image bank (CC BY 4.0, per story page)
#   lib:pg-120/7.jpg -> library/images in this repository (recompressed copies
#                      of a Gutenberg book's illustrations)
PB_IMAGES = 'https://raw.githubusercontent.com/global-asp/pb-imagebank/master/medium/'


def story_pictures(imagebank, sid):
    """File names of a story's pictures in pb-imagebank/medium (01 = cover)."""
    d = os.path.join(imagebank, 'medium', sid)
    if not os.path.isdir(d):
        return []
    return sorted(f for f in os.listdir(d) if f.endswith('.jpg'))


def story_pictures_from_list(listing, sid):
    return sorted(listing.get(sid, []))


_BLOCK = {'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'br', 'hr', 'tr', 'td', 'li', 'blockquote', 'pre', 'table', 'dd', 'dt'}
_HEAD = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'}


class _Html(HTMLParser):
    """A Gutenberg HTML book as blank-line separated blocks (like the plain
    text), with each picture as a block of its own: @@imgN@@."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.buf = []
        self.pics = []  # (src, href, caption)
        self.skip = 0
        self.caption = None  # depth of an element with class "caption"
        self.cap_text = []
        self.depth = 0
        self.href = None
        self.pre = False

    def flush(self):
        # (U+2028 marks a line break kept inside a block)
        t = '\u2028'.join(' '.join(x.split()) for x in ''.join(self.buf).split('\u2028'))
        t = t.strip('\u2028 ')
        if t:
            self.out.append(t.replace('\u2028', '\n'))
        self.buf = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        self.depth += 1
        if tag in ('script', 'style', 'head'):
            self.skip += 1
        if tag == 'a':
            self.href = a.get('href')
        if self.caption is None and 'caption' in (a.get('class') or ''):
            self.caption = self.depth
            self.cap_text = []
        if tag == 'img':
            src = a.get('src') or ''
            alt = (a.get('alt') or '').strip()
            # A large first letter drawn as a picture: the letter is the text.
            if len(alt) == 1 and alt.isalpha():
                self.buf.append(alt)
                return
            self.flush()
            self.pics.append([src, self.href, ''])
            self.out.append(f'@@img{len(self.pics) - 1}@@')
            return
        if tag in _BLOCK:
            if tag in _HEAD or tag in ('p', 'div', 'hr', 'blockquote', 'table', 'pre', 'tr', 'li'):
                self.flush()
            elif tag == 'br':
                self.buf.append('\u2028')
        if tag == 'pre':
            self.pre = True

    def handle_endtag(self, tag):
        if tag in ('script', 'style', 'head'):
            self.skip = max(0, self.skip - 1)
        if tag == 'pre':
            self.pre = False
        if tag == 'a':
            self.href = None
        if self.caption is not None and self.depth <= self.caption:
            cap = ' '.join(''.join(self.cap_text).split())
            if cap and self.pics and not self.pics[-1][2]:
                self.pics[-1][2] = cap
            self.caption = None
        self.depth -= 1
        if tag in _HEAD or tag in ('p', 'div', 'blockquote', 'table', 'pre', 'tr', 'li', 'td'):
            self.flush()

    def handle_data(self, data):
        if self.skip:
            return
        if self.caption is not None:
            self.cap_text.append(data)
            return
        self.buf.append(data.replace('\n', '\u2028') if self.pre else data)


def html_book(path):
    """(text, pictures) of a Gutenberg HTML book: the text in the shape of the
    plain-text edition, with @@imgN@@ blocks where its pictures are."""
    p = _Html()
    p.feed(open(path, encoding='utf-8', errors='replace').read())
    p.flush()
    blocks = []
    for b in p.out:
        # <br> inside a block: lines of a poem or a list stay lines; the
        # lines of <pre> (the Gutenberg header) become blocks of their own
        ls = [x.strip() for x in b.split('\n') if x.strip()]
        if any(re.match(r'^\*\*\* ?(START|END) OF', x) for x in ls):
            blocks.extend(ls)
        else:
            blocks.append('\n'.join(ls))
    return '\n\n'.join(blocks), p.pics


def keep_book_pictures(folder, pics, bid, out_dir):
    """Recompresses the pictures worth showing into out_dir/<bid>/ and returns
    {index: (short address, caption)}. Left out: icons used again and again
    ("enlarge"), ornaments, and anything tiny."""
    from PIL import Image
    used = {}
    for src, href, cap in pics:
        used[src] = used.get(src, 0) + 1
    keep = {}
    dest = os.path.join(out_dir, bid)
    os.makedirs(dest, exist_ok=True)
    n = 0
    for i, (src, href, cap) in enumerate(pics):
        if used[src] >= 3:
            continue
        cands = [src]
        if href and re.search(r'\.(jpe?g|png|gif)$', href, re.I):
            cands.insert(0, href)
        img = None
        for c in cands:
            f = os.path.join(folder, html.unescape(c))
            if os.path.exists(f):
                try:
                    img = Image.open(f)
                    img.load()
                    break
                except Exception:
                    img = None
        # (decorated first letters are about 150 pixels square: left out too)
        if img is None or min(img.size) < 80 or max(img.size) < 165:
            continue
        if img.mode in ('P', 'LA', 'RGBA', 'PA'):
            bg = Image.new('RGB', img.size, 'white')
            rgba = img.convert('RGBA')
            bg.paste(rgba, mask=rgba.split()[3])
            img = bg
        img = img.convert('RGB')
        px = list(img.resize((32, 32)).getdata())
        if all(abs(r - g) < 12 and abs(g - b) < 12 for r, g, b in px):
            img = img.convert('L')
        if img.size[0] > 640:
            img = img.resize((640, round(img.size[1] * 640 / img.size[0])), Image.LANCZOS)
        n += 1
        name = f'{n}.jpg'
        img.save(os.path.join(dest, name), 'JPEG', quality=64, optimize=True, progressive=True)
        keep[i] = (f'lib:{bid}/{name}', cap)
    if not keep:
        os.rmdir(dest)
    return keep


# --------------------------------------------------------------- main
def _story_markdown(title, pages, pics, sid):
    """A picture book in the app's Markdown: the cover, then each page with
    its picture. Pictures go with pages only when the image bank has exactly
    one per page (and the cover); otherwise only the cover is shown."""
    out = [f'# {title}']
    if pics:
        out.append(f'![](pb:{sid}/{pics[0]})')
    per_page = len(pics) == len(pages) + 1
    for k, pg in enumerate(pages):
        out.append('---')
        if per_page:
            out.append(f'![](pb:{sid}/{pics[k + 1]})')
        out.extend(pg)
    return '\n\n'.join(out) + '\n', (len(pics) if per_page else min(1, len(pics)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--stories', required=True, help='pb-source/en folder')
    ap.add_argument('--imagebank', help='a clone of pb-imagebank (only the file list is read)')
    ap.add_argument('--books-cache', required=True,
                    help='folder with Gutenberg books: <id>.txt, or a GITenberg clone in <id>/ (its HTML edition gives the pictures)')
    a = ap.parse_args()
    load_ranks()
    load_vocab()
    bank = {}
    if a.imagebank:
        import subprocess
        names = subprocess.run(['git', '-C', a.imagebank, 'ls-tree', '-r', '--name-only', 'HEAD', 'medium'],
                               capture_output=True, text=True, check=True).stdout.split()
        for n in names:
            parts = n.split('/')
            if len(parts) == 3 and parts[2].endswith('.jpg'):
                bank.setdefault(parts[1], []).append(parts[2])
    skipped = []
    catalog = []
    texts = {}
    for f in sorted(os.listdir(a.stories)):
        if not re.match(r'^\d{4}_.*\.md$', f) or f[:4] in _excluded_stories:
            continue
        s = read_story(os.path.join(a.stories, f))
        if s is None:
            continue
        title, pages, lic, credit = s
        paras = [p for pg in pages for p in pg]
        plain = f'# {title}\n\n' + '\n\n'.join(paras) + '\n'
        score, _, _, words = stats(plain)
        if words < 60:
            continue
        bad = unknown_words(plain)
        lower = len(re.findall(r"\b[a-z][a-z']*", plain))
        if len(bad) >= 4 or len(bad) >= 0.015 * lower:
            skipped.append(f'{f}: {", ".join(bad)}')
            continue
        sid = 'pb-' + f[:4]
        md, npics = _story_markdown(title, pages, story_pictures_from_list(bank, f[:4]), f[:4])
        texts[sid] = md
        item = {
            'id': sid, 'kind': 'story', 'title': title, 'author': None, 'level': story_level(score),
            'words': words, 'license': lic, 'credit': f'{credit}. Pratham Books, StoryWeaver.',
            'source': f'https://github.com/global-asp/pb-source/blob/master/en/{f}',
        }
        if npics:
            item['pics'] = npics
        catalog.append(item)
    out_books = os.path.join(ROOT, 'library', 'books')
    out_images = os.path.join(ROOT, 'library', 'images')
    os.makedirs(out_books, exist_ok=True)
    for gid, repo, fname, title, author, lvl, how in read_books_tsv():
        bid = f'pg-{gid}'
        raw = fetch_book(a.books_cache, gid, repo, fname)
        md, chapters = book_markdown(raw, title, author, how)
        pics = {}
        htm = sorted(glob.glob(os.path.join(a.books_cache, gid, f'{gid}-h', '*.htm*')))
        if os.path.isdir(os.path.join(out_images, bid)):
            for old in os.listdir(os.path.join(out_images, bid)):
                os.remove(os.path.join(out_images, bid, old))
        if htm:
            text, found = html_book(htm[0])
            if found:
                pics = keep_book_pictures(os.path.dirname(htm[0]), found, bid, out_images)
                md, placed = _insert_pictures(md, text, pics)
                for k in set(pics) - placed:
                    os.remove(os.path.join(out_images, bid, pics[k][0].split('/')[-1]))
                    del pics[k]
                if not pics and os.path.isdir(os.path.join(out_images, bid)):
                    os.rmdir(os.path.join(out_images, bid))
        score, rare, msl, words = stats(re.sub(r'^!\[.*$', '', md, flags=re.M))
        data = gzip.compress(md.encode('utf-8'), 9, mtime=0)
        open(os.path.join(out_books, f'{bid}.md.gz'), 'wb').write(data)
        pic_bytes = sum(os.path.getsize(os.path.join(out_images, bid, f)) for f in os.listdir(os.path.join(out_images, bid))) if pics else 0
        item = {
            'id': bid, 'kind': 'book', 'title': title, 'author': author, 'level': lvl,
            'words': words, 'chapters': chapters, 'size': len(data), 'license': 'Public domain',
            'credit': 'Project Gutenberg', 'source': f'https://www.gutenberg.org/ebooks/{gid}',
        }
        if pics:
            item['pics'] = len(pics)
            item['picsSize'] = pic_bytes
        catalog.append(item)
        print(f'{bid:10} {lvl} (formula {level(score)}) rare={rare:4.1f} sl={msl:4.1f} ch={chapters:3} words={words:6} '
              f'{len(data)//1024}KB pics={len(pics)} {pic_bytes//1024}KB {title}', file=sys.stderr)
    print(f'{len(skipped)} stories left out (misspellings or many non-English words):', file=sys.stderr)
    for x in skipped:
        print('  ' + x, file=sys.stderr)
    lv = {l: [0, 0] for l in LEVELS}
    for c in catalog:
        lv[c['level']][c['kind'] == 'book'] += 1
    print('levels (stories, books):', lv, file=sys.stderr)
    assets = os.path.join(ROOT, 'assets', 'library')
    os.makedirs(assets, exist_ok=True)
    catalog.sort(key=lambda c: (LEVELS.index(c['level']), c['kind'] != 'book', c['words']))
    json.dump(catalog, open(os.path.join(assets, 'catalog.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=0)
    open(os.path.join(assets, 'stories.json.gz'), 'wb').write(
        gzip.compress(json.dumps(texts, ensure_ascii=False).encode('utf-8'), 9, mtime=0))


def _norm_words(t):
    return re.findall(r"[a-z0-9]+", t.lower().replace("'", ''))


def _insert_pictures(md, text, pics):
    """Puts each kept picture of the HTML edition into the book's Markdown
    (made from the plain text, so the text is the same as without pictures):
    before the paragraph that follows the picture in the HTML edition, found
    by its first words; a picture with no text after it goes after the
    paragraph before it. Returns the Markdown and the pictures placed."""
    blocks = [b for b in text.split('\n\n') if b.strip()]
    paras = md.split('\n\n')
    keys = [' '.join(_norm_words(p)) for p in paras]
    joined = ''
    starts = []
    for k in keys:
        starts.append(len(joined))
        joined += k + ' | '

    def para_at(pos):
        lo, hi = 0, len(starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if starts[mid] <= pos:
                lo = mid
            else:
                hi = mid - 1
        return lo

    before = {}  # paragraph index -> pictures to put before it
    after = {}
    placed = set()
    cursor = 0
    for i, b in enumerate(blocks):
        m = re.fullmatch(r'@@img(\d+)@@', b.strip())
        if not m or int(m.group(1)) not in pics:
            continue
        k = int(m.group(1))
        # the first text after the picture, then the last text before it
        nxt = next((x for x in blocks[i + 1:i + 8] if not x.startswith('@@img') and len(_norm_words(x)) >= 4), None)
        prv = next((x for x in reversed(blocks[max(0, i - 8):i]) if not x.startswith('@@img') and len(_norm_words(x)) >= 4), None)
        hit = None
        for cand, where in ((nxt, 'before'), (prv, 'after')):
            if not cand:
                continue
            w = _norm_words(cand)
            for n in (8, 6, 4):
                key = ' '.join(w[:n]) if where == 'before' else ' '.join(w[-n:])
                pos = joined.find(key, cursor)
                if pos >= 0:
                    hit = (para_at(pos), where)
                    break
            if hit:
                break
        if not hit:
            continue
        idx, where = hit
        cursor = starts[idx]
        (before if where == 'before' else after).setdefault(idx, []).append(k)
        placed.add(k)

    def pic(k):
        addr, cap = pics[k]
        cap = cap.replace('"', "'")
        return f'![]({addr} "{cap}")' if cap else f'![]({addr})'

    out = []
    for i, p in enumerate(paras):
        ks = before.get(i, [])
        if p.startswith('# ') and ks:
            # a picture just before a chapter heading goes under the heading
            out.append(p)
            out.extend(pic(k) for k in ks)
        else:
            out.extend(pic(k) for k in ks)
            out.append(p)
        out.extend(pic(k) for k in after.get(i, []))
    res = '\n\n'.join(out)
    if not res.endswith('\n'):
        res += '\n'
    return res, placed


if __name__ == '__main__':
    main()

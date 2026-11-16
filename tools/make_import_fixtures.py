#!/usr/bin/env python3
"""Builds the books used by test/import_completeness_test.dart.

One made-up story (story.json) is written in every format the app imports,
in the layouts that broke imports before: a picture book with running
headers, page numbers, captions under and beside pictures and paragraphs
that go on over the page; a two-column article with a footnote; and the
plain formats (EPUB, DOCX, ODT, RTF, HTML, Markdown, TXT, FB2) from pandoc.
The test checks that every word of the story arrives, in order.

    python3 tools/make_import_fixtures.py test/fixtures/import

Needs reportlab, pandoc and (for the DOCX/ODT made PDF) LibreOffice.
"""
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile

from reportlab.lib.enums import TA_JUSTIFY, TA_CENTER
from reportlab.lib.pagesizes import A5, letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Paragraph, Spacer, PageBreak,
                                Table, TableStyle, Flowable, NextPageTemplate, FrameBreak, KeepTogether)

random.seed(7)

NAMES = ['Mira', 'Tomas', 'the old fisherman', 'the baker', 'her brother', 'the teacher', 'Grandmother Ilse',
         'the young soldier', 'a tired traveller', 'the mayor', 'the twins', 'a quiet stranger']
VERBS = ['carried', 'found', 'painted', 'repaired', 'forgot', 'hid', 'opened', 'counted', 'sold', 'borrowed',
         'watched', 'followed', 'cleaned', 'described', 'remembered', 'wrapped']
OBJECTS = ['a green lantern', 'the broken clock', 'three silver coins', 'a letter from the north', 'the heavy key',
           'a basket of apples', 'the blue boat', 'an old map', 'the wooden horse', 'a jar of honey',
           'the cracked mirror', 'a bundle of candles', 'the forgotten violin', 'a pair of boots']
PLACES = ['near the harbour', 'behind the mill', 'under the bridge', 'in the narrow street', 'beside the well',
          'at the edge of the forest', 'on the windy hill', 'inside the empty church', 'by the frozen lake',
          'in the busy market', 'before sunrise', 'after the storm']
EXTRA = ['Nobody said a word.', 'It was colder than anyone expected.', '"Why now?" she asked.',
         'The wind changed again.', 'He laughed, but only for a moment.', 'Somewhere a dog was barking.',
         'They decided to wait until morning.', '"Not yet," he answered quietly.']


def sentence():
    s = f'{random.choice(NAMES)} {random.choice(VERBS)} {random.choice(OBJECTS)} {random.choice(PLACES)}'
    if random.random() < 0.3:
        s += f' while {random.choice(NAMES)} {random.choice(VERBS)} {random.choice(OBJECTS)}'
    s = s[0].upper() + s[1:] + '.'
    return s


def paragraph(n):
    out = []
    for _ in range(n):
        out.append(sentence() if random.random() < 0.8 else random.choice(EXTRA))
    return ' '.join(out)


def story():
    chapters = []
    for title in ['The Green Lantern', 'A Letter from the North', 'The Frozen Lake']:
        paras = []
        for i in range(9):
            if i % 4 == 3:
                paras.append(random.choice(EXTRA))  # one-line paragraph
            else:
                paras.append(paragraph(random.randint(3, 7)))
        captions = [f'{sentence()[:-1]}.' for _ in range(2)]
        chapters.append({'title': title, 'paragraphs': paras, 'captions': captions})
    return {'title': 'The Lantern Keeper', 'author': 'VocaBloom Tests', 'chapters': chapters}


# ------------------------------------------------------------------ PDF: picture book
class Picture(Flowable):
    """A grey box standing for an illustration."""

    def __init__(self, w, h):
        super().__init__()
        self.width, self.height = w, h

    def draw(self):
        self.canv.setFillGray(0.82)
        self.canv.rect(0, 0, self.width, self.height, stroke=0, fill=1)


def book_pdf(st, path):
    W, H = A5
    body = ParagraphStyle('body', fontName='Times-Roman', fontSize=11, leading=14, alignment=TA_JUSTIFY,
                          firstLineIndent=12)
    cap = ParagraphStyle('cap', fontName='Times-Italic', fontSize=9, leading=11, alignment=TA_CENTER)
    head = ParagraphStyle('head', fontName='Times-Bold', fontSize=20, leading=26, alignment=TA_CENTER)
    num = ParagraphStyle('num', fontName='Times-Bold', fontSize=26, leading=30, alignment=TA_CENTER)
    small = ParagraphStyle('small', fontName='Times-Roman', fontSize=11, leading=16)
    state = {'chapter': ''}

    def deco(canv, doc):
        n = doc.page
        if n <= 2:
            return
        canv.setFont('Times-Italic', 9)
        txt = st['title'] if n % 2 == 0 else state['chapter']
        if not getattr(doc, '_chapter_start', False):
            canv.drawCentredString(W / 2, H - 14 * mm, txt)
        doc._chapter_start = False
        canv.setFont('Times-Roman', 9)
        canv.drawCentredString(W / 2, 10 * mm, str(n))

    class Doc(BaseDocTemplate):
        def afterFlowable(self, f):
            if isinstance(f, Paragraph) and f.style.name == 'head':
                state['chapter'] = f.getPlainText()
                self._chapter_start = True

    doc = Doc(path, pagesize=A5, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=20 * mm,
              bottomMargin=18 * mm, title=st['title'])
    frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id='f')
    doc.addPageTemplates([PageTemplate(id='p', frames=[frame], onPageEnd=deco)])
    flow = [Spacer(1, 40 * mm), Paragraph(st['title'], head), Paragraph('by ' + st['author'], cap), PageBreak()]
    # Contents without dot leaders, page numbers worked out below.
    flow += [Paragraph('CONTENTS', head), Spacer(1, 8 * mm)]
    starts = st.get('_starts') or [3, 6, 9]
    for i, c in enumerate(st['chapters']):
        flow.append(Paragraph(f'{i + 1}&nbsp;&nbsp;&nbsp;{c["title"]}&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;{starts[i]}', small))
    flow.append(PageBreak())
    pw = doc.width
    for i, c in enumerate(st['chapters']):
        flow += [Spacer(1, 18 * mm), Paragraph(str(i + 1), num), Paragraph(c['title'], head), Spacer(1, 8 * mm)]
        ps = c['paragraphs']
        for j, p in enumerate(ps):
            flow.append(Paragraph(p, body))
            if j == 2:
                # A picture across the page with its caption under it.
                flow += [Spacer(1, 4), KeepTogether([Picture(pw * 0.8, 70), Spacer(1, 3), Paragraph(c['captions'][0], cap)]),
                         Spacer(1, 6)]
            if j == 5:
                # A picture on the left, the caption under it, the next paragraph beside it.
                side = ParagraphStyle('side', parent=body)
                txt = Paragraph(ps[j + 1], side) if j + 1 < len(ps) else Spacer(1, 1)
                t = Table([[[Picture(pw * 0.42, 90), Spacer(1, 3), Paragraph(c['captions'][1], cap)], txt]],
                          colWidths=[pw * 0.46, pw * 0.54])
                t.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('LEFTPADDING', (0, 0), (-1, -1), 0),
                                       ('RIGHTPADDING', (0, 0), (-1, -1), 4)]))
                flow.append(t)
        flow.append(PageBreak())
    # Paragraph 7 of each chapter is already beside the picture.
    doc.build(list(_skip_beside(flow, st)))


def _skip_beside(flow, st):
    """The paragraph placed beside a picture is not repeated after the table."""
    beside = {c['paragraphs'][6] for c in st['chapters']}
    seen = set()
    for f in flow:
        if isinstance(f, Paragraph) and f.style.name == 'body' and f.getPlainText() in beside and f.getPlainText() not in seen:
            seen.add(f.getPlainText())
            continue
        yield f


# ------------------------------------------------------------------ PDF: two columns
def columns_pdf(st, path):
    W, H = letter
    body = ParagraphStyle('body', fontName='Helvetica', fontSize=9.5, leading=12, alignment=TA_JUSTIFY,
                          spaceAfter=5)
    head = ParagraphStyle('head', fontName='Helvetica-Bold', fontSize=12, leading=15, spaceBefore=6, spaceAfter=4)
    title = ParagraphStyle('title', fontName='Helvetica-Bold', fontSize=18, leading=22, alignment=TA_CENTER)
    note = ParagraphStyle('note', fontName='Helvetica', fontSize=7, leading=8.5)

    def deco(canv, doc):
        canv.setFont('Helvetica', 8)
        canv.drawString(54, H - 36, 'Journal of Made-up Stories')
        canv.drawRightString(W - 54, H - 36, 'Vol. 3')
        canv.drawCentredString(W / 2, 30, f'Page {doc.page}')
        if doc.page == 1:
            canv.setFont('Helvetica', 7)
            canv.drawString(54, 48, '* This story was written for testing a book reader.')

    doc = BaseDocTemplate(path, pagesize=letter, leftMargin=54, rightMargin=54, topMargin=54, bottomMargin=60,
                          title=st['title'])
    gap = 18
    cw = (doc.width - gap) / 2
    first = [Frame(doc.leftMargin, doc.height + doc.bottomMargin - 50, doc.width, 50, id='t'),
             Frame(doc.leftMargin, doc.bottomMargin + 14, cw, doc.height - 64, id='l1'),
             Frame(doc.leftMargin + cw + gap, doc.bottomMargin + 14, cw, doc.height - 64, id='r1')]
    rest = [Frame(doc.leftMargin, doc.bottomMargin, cw, doc.height, id='l'),
            Frame(doc.leftMargin + cw + gap, doc.bottomMargin, cw, doc.height, id='r')]
    doc.addPageTemplates([PageTemplate(id='first', frames=first, onPage=deco),
                          PageTemplate(id='rest', frames=rest, onPage=deco)])
    flow = [Paragraph(st['title'] + '*', title), NextPageTemplate('rest'), FrameBreak()]
    for c in st['chapters']:
        flow.append(Paragraph(c['title'], head))
        flow += [Paragraph(p, body) for p in c['paragraphs']]
    doc.build(flow)


# ------------------------------------------------------------------ other formats
def markdown(st):
    out = [f'# {st["title"]}', '']
    for c in st['chapters']:
        out += [f'## {c["title"]}', '']
        for p in c['paragraphs']:
            out += [p, '']
    return '\n'.join(out)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'test/fixtures/import'
    os.makedirs(out, exist_ok=True)
    st = story()
    with open(os.path.join(out, 'story.json'), 'w') as f:
        json.dump(st, f, indent=1, ensure_ascii=False)
    # Build once to learn where chapters start, then again with the right contents page.
    tmp = tempfile.mkdtemp()
    book_pdf(st, os.path.join(tmp, 'b.pdf'))
    starts = []
    txt = subprocess.run(['pdftotext', '-layout', os.path.join(tmp, 'b.pdf'), '-'], capture_output=True, text=True).stdout
    for c in st['chapters']:
        for n, page in enumerate(txt.split('\f')):
            if c['title'] in page and 'CONTENTS' not in page:
                starts.append(n + 1)
                break
    st['_starts'] = starts
    book_pdf(st, os.path.join(out, 'book.pdf'))
    del st['_starts']
    columns_pdf(st, os.path.join(out, 'columns.pdf'))
    md = os.path.join(tmp, 'story.md')
    with open(md, 'w') as f:
        f.write(markdown(st))
    shutil.copy(md, os.path.join(out, 'story.md'))
    meta = ['--metadata', f'title={st["title"]}', '--metadata', f'author={st["author"]}']
    for ext in ['epub', 'docx', 'odt', 'rtf', 'html', 'fb2']:
        args = ['pandoc', md, '-s', '-o', os.path.join(out, f'story.{ext}')] + meta
        if ext == 'epub':
            args += ['--split-level=2']
        subprocess.run(args, check=True)
    # Plain text the way Project Gutenberg writes it: hard-wrapped lines, blank lines between paragraphs.
    subprocess.run(['pandoc', md, '-t', 'plain', '--columns=72', '-o', os.path.join(out, 'story.txt')], check=True)
    # A PDF as a word processor exports it.
    subprocess.run(['soffice', '--headless', '--convert-to', 'pdf', '--outdir', tmp, os.path.join(out, 'story.odt')],
                   check=True, capture_output=True)
    shutil.copy(os.path.join(tmp, 'story.pdf'), os.path.join(out, 'office.pdf'))
    shutil.rmtree(tmp)


if __name__ == '__main__':
    main()

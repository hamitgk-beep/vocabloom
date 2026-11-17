"""Writes test/fixtures/import/slips.* : small books with the text slips that
real books bring with them, for test/text_repair_test.dart.

* slips.pdf: a picture book page set by hand: words broken with a hyphen at
  the end of a line (PDFium returns them with a hidden mark), a compound
  broken after its own hyphen ("good-for-nothing"), a drop cap, a list with
  ZapfDingbats bullets and a picture caption in the middle of a sentence.
* slips.docx: a Word file with a Wingdings bullet (a private-use character),
  a tab and a line break inside paragraphs.
* slips.odt: the same file saved by LibreOffice (<text:tab/>,
  <text:line-break/>).

The expected paragraphs are in slips.json. Needs reportlab, python-docx and
LibreOffice (soffice) for the ODT.
"""
import json, os, shutil, subprocess, sys, tempfile

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from reportlab.lib.pagesizes import A5
from reportlab.pdfgen import canvas

OUT = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures', 'import')

# Lines exactly as they are set on the page; "|" marks where a line ends.
PAGE = [
    ('drop', 'O', 'nce upon a time a lazy boy lived with his'),
    ('line', 'mother near the market. Every morning he ran'),
    ('line', 'through the streets, and his mother called him a good-for-'),
    ('line', 'nothing. She was often hungry and very unhap-'),
    ('line', 'py, because the boy never helped her.'),
    ('gap',),
    ('line', 'One day an old man came to the market. "Is your'),
    ('line', 'name Aladdin?" he asked. "I am your father\'s brother,'),
    ('caption', 'The old man went up to an orange-seller.'),
    ('line', 'and I want to help you." He gave the boy ten pieces'),
    ('line', 'of gold and a new coat. The boy was very sur-'),
    ('line', 'prised, but he took the gold home.'),
    ('gap',),
    ('bullet', 'The old man was not his uncle.'),
    ('bullet', 'He wanted to find a magic lamp.'),
    ('bullet', 'Only a poor boy could get into the garden.'),
]
EXPECTED_PDF = [
    'Once upon a time a lazy boy lived with his mother near the market. Every morning he ran through the streets, '
    'and his mother called him a good-for-nothing. She was often hungry and very unhappy, because the boy never helped her.',
    'One day an old man came to the market. "Is your name Aladdin?" he asked. "I am your father\'s brother, and I want '
    'to help you." He gave the boy ten pieces of gold and a new coat. The boy was very surprised, but he took the gold home.',
    'The old man was not his uncle.',
    'He wanted to find a magic lamp.',
    'Only a poor boy could get into the garden.',
]
EXPECTED_CAPTIONS = ['The old man went up to an orange-seller.']


def pdf(path):
    W, H = A5
    c = canvas.Canvas(path, pagesize=A5)
    c.setTitle('Slips')
    x, y, lead = 50, H - 70, 16
    for item in PAGE:
        kind = item[0]
        if kind == 'gap':
            y -= 10
            continue
        if kind == 'drop':
            c.setFont('Times-Roman', 34)
            c.drawString(x, y - 20, item[1])
            c.setFont('Times-Roman', 11)
            c.drawString(x + 26, y, item[2])
            y -= lead
            continue
        if kind == 'caption':
            # A picture with its caption, between two lines of the sentence.
            y -= 8
            c.setFillGray(0.85)
            c.rect(x + 40, y - 70, 160, 70, fill=1, stroke=0)
            c.setFillGray(0)
            c.setFont('Times-Italic', 8)
            c.drawString(x + 40, y - 82, item[1])
            y -= 100
            continue
        if kind == 'bullet':
            c.setFont('ZapfDingbats', 8)
            c.drawString(x + 4, y + 1, 'l')
            c.setFont('Times-Roman', 11)
            c.drawString(x + 18, y, item[1])
            y -= lead
            continue
        c.setFont('Times-Roman', 11)
        c.drawString(x + (26 if y > H - 110 else 0), y, item[1])
        y -= lead
    c.setFont('Times-Roman', 8)
    c.drawCentredString(W / 2, 30, '3')
    c.showPage()
    c.save()


EXPECTED_DOCX = [
    'The Lamp',
    'Twinkle, twinkle, little star, How I wonder what you are!',
    'Name: Aladdin',
    'The jinnee came out of the lamp.',
    'Up the hill and down the hill.',
]


def docx(path):
    d = Document()
    d.add_heading('The Lamp', 1)
    p = d.add_paragraph()
    p.add_run('Twinkle, twinkle, little star,').add_break()
    p.add_run('How I wonder what you are!')
    p = d.add_paragraph()
    p.add_run('Name:')
    p.add_run().add_tab()
    p.add_run('Aladdin')
    # A bullet typed in the Wingdings font, as Word saves it: U+F0D8.
    p = d.add_paragraph()
    r = p.add_run('')
    rpr = r._element.get_or_add_rPr()
    f = OxmlElement('w:rFonts')
    for a in ('w:ascii', 'w:hAnsi'):
        f.set(qn(a), 'Wingdings')
    rpr.append(f)
    p.add_run().add_tab()
    p.add_run('The jinnee came out of the lamp.')
    p = d.add_paragraph()
    p.add_run('Up the hill and')
    p.add_run().add_break()
    p.add_run('down the hill.')
    d.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    pdf(os.path.join(OUT, 'slips.pdf'))
    docx(os.path.join(OUT, 'slips.docx'))
    tmp = tempfile.mkdtemp()
    try:
        subprocess.run(['soffice', '--headless', '--convert-to', 'odt', '--outdir', tmp, os.path.join(OUT, 'slips.docx')],
                       check=True, capture_output=True)
        shutil.copy(os.path.join(tmp, 'slips.odt'), os.path.join(OUT, 'slips.odt'))
    finally:
        shutil.rmtree(tmp)
    with open(os.path.join(OUT, 'slips.json'), 'w') as f:
        json.dump({'pdf': EXPECTED_PDF, 'captions': EXPECTED_CAPTIONS, 'docx': EXPECTED_DOCX}, f, indent=1, ensure_ascii=False)


if __name__ == '__main__':
    sys.exit(main())

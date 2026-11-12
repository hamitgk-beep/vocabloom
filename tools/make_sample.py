"""Creates small sample books (EPUB, DOCX, TXT) used for testing. Original text."""
import sys, zipfile, os
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
ch1 = ["The Lighthouse Keeper",
"Every evening, as soon as the sun went down, old Martin climbed the narrow stairs of the lighthouse. He had been doing this for forty years, and he never once thought of giving it up.",
"Although the village had changed a great deal, the sea was the same. By the way, Martin did not like visitors. He would look out of the window and pretend he was not at home whenever someone knocked on the door.",
"One stormy night, a young woman called Elif turned up at the door. She was soaked to the skin and out of breath. \"I am afraid my boat has broken down,\" she said. \"Could I wait here until the storm is over?\"",
"Martin did not know what to say. In fact, he had not spoken to anyone for weeks. But he made a decision quickly: he let her in and put the kettle on."]
ch2 = ["A Strange Friendship",
"At first, they sat in silence. Then Elif tried to break the ice. She asked him how he had put up with the loneliness for so many years.",
"\"You get used to it,\" Martin answered. \"Besides, the light needs me. If I had left, ships would have run into the rocks.\"",
"Elif was deeply moved. She had come to the village to find out about her grandfather, who used to work on the boats. Little by little, Martin began to tell her stories that he had kept to himself for a long time.",
"When the storm finally calmed down, the sky turned pink. Elif promised that she would come back. Martin smiled for the first time in years. Better late than never, he thought."]
def xhtml(ch):
    body = f"<h1>{ch[0]}</h1>" + "".join(f"<p>{p}</p>" for p in ch[1:])
    return f'<?xml version="1.0" encoding="utf-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>{ch[0]}</title></head><body>{body}</body></html>'
with zipfile.ZipFile(os.path.join(out, 'sample.epub'), 'w') as z:
    z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr('OEBPS/content.opf', '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>The Lighthouse Keeper</dc:title><dc:creator>Sample Author</dc:creator></metadata><manifest><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>')
    z.writestr('OEBPS/ch1.xhtml', xhtml(ch1))
    z.writestr('OEBPS/ch2.xhtml', xhtml(ch2))
with open(os.path.join(out, 'sample.txt'), 'w') as f:
    f.write("CHAPTER ONE\n\n" + "\n\n".join(ch1[1:]) + "\n\nCHAPTER TWO\n\n" + "\n\n".join(ch2[1:]))
def para(t, style=None):
    ps = f'<w:pPr><w:pStyle w:val="{style}"/></w:pPr>' if style else ''
    t = t.replace('&','&amp;').replace('<','&lt;')
    return f'<w:p>{ps}<w:r><w:t xml:space="preserve">{t}</w:t></w:r></w:p>'
doc = ''.join(para(c[0], 'Heading1') + ''.join(para(p) for p in c[1:]) for c in (ch1, ch2))
with zipfile.ZipFile(os.path.join(out, 'sample.docx'), 'w') as z:
    z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
    z.writestr('word/document.xml', f'<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>{doc}</w:body></w:document>')

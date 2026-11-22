// Illustrated books: pictures are kept where the book has them (PDF, EPUB,
// DOCX, ODT, FB2), every paragraph of a PDF knows its page, type size and
// alignment, and the reader cuts any book into pages.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/import/pdf_pictures.dart';
import 'package:kelime_okur/import/text_repair.dart';
import 'package:kelime_okur/ui/pages.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqlite3/sqlite3.dart';

/// A small grey picture with a frame, as PNG.
Uint8List _png(int w, int h) {
  final img = im.Image(width: w, height: h);
  im.fill(img, color: im.ColorRgb8(230, 230, 230));
  im.drawRect(img, x1: 2, y1: 2, x2: w - 3, y2: h - 3, color: im.ColorRgb8(20, 20, 20), thickness: 3);
  return im.encodePng(img);
}

List<int> _zip(Map<String, List<int>> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.addFile(ArchiveFile(e.key, e.value.length, e.value));
  }
  return ZipEncoder().encode(a);
}

void main() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  bool isWord(String w) {
    final l = w.toLowerCase().replaceAll('’', "'");
    return d.lemmatizer.lemmas(l).any(d.lemmatizer.known.contains);
  }

  setUpAll(pdfrxInitialize);

  test('titles in spaced-out capitals are joined into words again', () {
    expect(joinSpacedCaps('AL A D D IN', isWord), 'ALADDIN');
    expect(joinSpacedCaps('AN D T HE EN C H ANTE D L A MP', isWord), 'AND THE ENCHANTED LAMP');
    expect(joinSpacedCaps('CONT ENTS', isWord), 'CONTENTS');
    expect(joinSpacedCaps('ABOUT THE AUTHOR A ND THE STORY', isWord), 'ABOUT THE AUTHOR AND THE STORY');
    expect(joinSpacedCaps('ALADDIN AND THE EN CHANTED LAMP', isWord), 'ALADDIN AND THE ENCHANTED LAMP');
    // Ordinary capitals and ordinary text stay as they are.
    expect(joinSpacedCaps('RETOLD BY JUDITH DEAN', isWord), 'RETOLD BY JUDITH DEAN');
    expect(joinSpacedCaps('THE RING AND THE LAMP', isWord), 'THE RING AND THE LAMP');
    expect(joinSpacedCaps('A man in a coat.', isWord), 'A man in a coat.');
  });

  test('a PDF page is a page of the reader; other books get pages of about 230 words', () {
    Para p(int i, String kind, String text, [int? pg]) => Para(i, i, kind, text, pg == null ? const {} : {'pg': pg});
    final pdf = [p(0, 'h', 'One', 0), p(1, 'p', 'a', 0), p(2, 'i', 'x.jpg', 1), p(3, 'c', 'cap', 1), p(4, 'p', 'b', 3)];
    expect(pagesOf(pdf), [(0, 2), (2, 4), (4, 5)]);
    expect(pageOfPara(pagesOf(pdf), 3), 1);
    final long = List.filled(100, 'word').join(' ');
    final epub = [p(0, 'h', 'Title'), p(1, 'p', long), p(2, 'p', long), p(3, 'p', long), p(4, 'h', 'Next'), p(5, 'p', long)];
    expect(pagesOf(epub), [(0, 3), (3, 4), (4, 6)]);
    expect(pagesOf(const []), [(0, 0)]);
  });

  test('picture book PDF: every paragraph knows its page, captions sit under their pictures', () async {
    final b = await importFile('test/fixtures/import/book.pdf', isWord: isWord);
    final all = [for (final c in b.chapters) for (var i = 0; i < c.paragraphs.length; i++) (c.paragraphs[i], c.metaAt(i))];
    expect(all.every((x) => x.$2?['pg'] is int), isTrue);
    // Pages only go forward.
    final pages = [for (final x in all) x.$2!['pg'] as int];
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i] >= pages[i - 1], isTrue);
    }
    // Every picture of the book has its file.
    for (final x in all.where((x) => x.$1.$1 == 'i')) {
      expect(b.images.containsKey(x.$1.$2), isTrue);
      expect(x.$2!['ar'], isA<num>());
    }
    // The import-only keys do not reach the database.
    expect(all.any((x) => x.$2!.keys.any((k) => k.startsWith('_'))), isFalse);
  });

  test('EPUB: pictures stay where they are, with their captions; icons are left out', () {
    const page = '''<html><body><h1>The Lamp</h1><p>Aladdin found the lamp.</p>
      <figure><img src="../img/lamp.png"/><figcaption>The old lamp.</figcaption></figure>
      <p><img src="../img/dot.png"/>He rubbed it.</p></body></html>''';
    final epub = _zip({
      'META-INF/container.xml': utf8.encode(
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'),
      'OEBPS/content.opf': utf8.encode('<package><metadata><title>Lamp</title></metadata>'
          '<manifest><item id="c1" href="text/c1.xhtml"/></manifest><spine><itemref idref="c1"/></spine></package>'),
      'OEBPS/text/c1.xhtml': utf8.encode(page),
      'OEBPS/img/lamp.png': _png(320, 200),
      'OEBPS/img/dot.png': _png(8, 8),
    });
    final b = importBytes(epub, 'epub', 'x');
    final ps = b.chapters.expand((c) => c.paragraphs).toList();
    expect(ps.map((p) => p.$1).toList(), ['h', 'p', 'i', 'c', 'p']);
    expect(ps[3].$2, 'The old lamp.');
    expect(b.images.keys, [ps[2].$2]);
  });

  test('DOCX, ODT and FB2 pictures are kept', () {
    final png = _png(300, 300);
    final docx = _zip({
      'word/document.xml': utf8.encode('<w:document xmlns:w="w" xmlns:a="a" xmlns:r="r"><w:body>'
          '<w:p><w:r><w:t>Before the picture.</w:t></w:r></w:p>'
          '<w:p><w:r><w:drawing><a:blip r:embed="rId9"/></w:drawing></w:r></w:p>'
          '<w:p><w:r><w:t>After the picture.</w:t></w:r></w:p></w:body></w:document>'),
      'word/_rels/document.xml.rels': utf8.encode('<Relationships><Relationship Id="rId9" Target="media/image1.png"/></Relationships>'),
      'word/media/image1.png': png,
    });
    final odt = _zip({
      'content.xml': utf8.encode('<office:document-content xmlns:office="o" xmlns:text="t" xmlns:draw="d" xmlns:xlink="x">'
          '<office:body><office:text><text:p>Before the picture.</text:p>'
          '<text:p><draw:frame><draw:image xlink:href="Pictures/a.png"/></draw:frame></text:p>'
          '<text:p>After the picture.</text:p></office:text></office:body></office:document-content>'),
      'Pictures/a.png': png,
    });
    final fb2 = '<FictionBook xmlns:l="http://www.w3.org/1999/xlink"><body><section><title><p>One</p></title>'
        '<p>Before the picture.</p><image l:href="#pic"/><p>After the picture.</p></section></body>'
        '<binary id="pic" content-type="image/png">${base64.encode(png)}</binary></FictionBook>';
    for (final (ext, bytes) in [('docx', docx), ('odt', odt), ('fb2', utf8.encode(fb2))]) {
      final b = importBytes(bytes, ext, 'x');
      final ps = b.chapters.expand((c) => c.paragraphs).where((p) => p.$1 != 'h').toList();
      expect(ps.map((p) => p.$1).toList(), ['p', 'i', 'p'], reason: ext);
      expect(b.images.length, 1, reason: ext);
    }
  });

  test('a book keeps its pictures in its own folder, and deleting it removes them', () {
    final dir = Directory.systemTemp.createTempSync('vb_pics');
    final u = UserDb.open(dir);
    final b = ImportedBook('T', null, 'pdf', [
      ImportedChapter('One', [('p', 'Text.'), ('i', 'p1_1.jpg'), ('c', 'A caption.'), ('i', 'missing.jpg')],
          [{'pg': 0, 'al': 'j'}, {'pg': 0, 'ar': 1.5}, {'pg': 0, 'al': 'c'}, {'pg': 0}]),
    ], {'p1_1.jpg': [1, 2, 3]});
    final id = u.insertBook(b);
    final ps = u.paras(id, 0);
    expect(ps.map((p) => p.kind).toList(), ['p', 'i', 'c']);
    expect(ps[0].align, 'j');
    expect(ps[1].aspect, 1.5);
    expect(u.imageFile(ps[1]).readAsBytesSync(), [1, 2, 3]);
    expect(u.bookPages(id), 1);
    expect(u.chapterText(id, 0).contains('p1_1'), isFalse);
    u.saveProgress(id, 0, 120, page: 3);
    expect(u.books().first.lastPage, 3);
    // A picture inside the book is no cover.
    expect(u.coverFile(id), isNull);
    u.deleteBook(id);
    expect(u.imageFile(ps[1]).existsSync(), isFalse);

    // A picture on the first page is the cover.
    final c = u.insertBook(
      ImportedBook(
        'C',
        null,
        'pdf',
        [
          ImportedChapter(
            'One',
            [('i', 'p1_1.jpg'), ('h', 'Title')],
            [
              {'pg': 0, 'ar': 0.66},
              {'pg': 1},
            ],
          ),
        ],
        {
          'p1_1.jpg': [1, 2, 3],
        },
      ),
    );
    expect(u.coverFile(c)?.readAsBytesSync(), [1, 2, 3]);
  });

  test('a drop cap drawn as a picture is read from its shape and the word after it', () {
    InkLetter ink(double aspect, double top, double bottom, bool hole) => InkLetter(0, 0, 0, 0, aspect, top, bottom, hole);
    // "n the garden": In, An or On; a narrow bar is an I.
    expect(dropCapLetter('n the garden', ink(0.38, 1, 1, false), isWord), 'I');
    expect(dropCapLetter('n old man', ink(0.95, 0.2, 1, true), isWord), 'A');
    expect(dropCapLetter('hrough the window', ink(0.9, 1, 0.5, false), isWord), 'T');
    // A letter that is a word of its own.
    expect(dropCapLetter('week later', ink(0.95, 0.2, 1, true), isWord), 'A ');
    expect(dropCapLetter('The garden', ink(0.4, 1, 1, false), isWord), isNull);
  });

  test('slips of a recognised text layer: symbols for letters, spaces in words and before punctuation', () {
    String fix(String s) => repairPdfText(s, isWord);
    expect(fix(r'because it sho\ivs what is there'), 'because it shows what is there');
    expect(fix(r"'Should I go, l\/Ir Gray?'"), "'Should I go, Mr Gray?'");
    expect(fix('He went ho1ne.'), 'He went home.');
    expect(fix("the scent of summer flowers . Lord Henry"), 'the scent of summer flowers. Lord Henry');
    expect(fix("'So that' s my secret,' he said. 'You are not beautiful. '"), "'So that's my secret,' he said. 'You are not beautiful.'");
    // Quoted words and formulas stay.
    expect(fix('"veiled sounds"'), '"veiled sounds"');
    expect(fix('vitamin A1 and C16H10'), 'vitamin A1 and C16H10');

    final book = fixWithBookWords([
      'Lord Henry smiled. Basil Hallward looked at Henry.',
      'Lord Herny laughed, and Basil Hall ward painted.',
      'Henry saw Dori an in the garden of Hallward. Dorian and Dorian Hallward.',
      'He put too much of mys elf into it, every day, evety day.',
      'I see myself, by myself, in myself.',
    ], isWord);
    expect(book[1], 'Lord Henry laughed, and Basil Hallward painted.');
    expect(book[2], startsWith('Henry saw Dorian in'));
    expect(book[3], 'He put too much of myself into it, every day, every day.');
  });
}

// Every word of a book must arrive in the reader, in order, whatever the file
// format and layout. The books in test/fixtures/import are one made-up story
// written by tools/make_import_fixtures.py as a picture book PDF (running
// headers, page numbers, captions under and beside pictures, paragraphs going
// on over the page), a two-column PDF, a word processor PDF and as EPUB,
// DOCX, ODT, RTF, HTML, Markdown, TXT and FB2.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/import/pdf_import.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqlite3/sqlite3.dart';

List<String> _words(String s) =>
    RegExp(r"[a-z]+").allMatches(s.toLowerCase().replaceAll(RegExp(r"['’]"), '')).map((m) => m.group(0)!).toList();

String _norm(String s) => _words(s).join(' ');

/// Length of the longest common subsequence: how many words arrived in order.
int _lcs(List<String> a, List<String> b) {
  var prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    for (var j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] == b[j - 1] ? prev[j - 1] + 1 : (prev[j] > cur[j - 1] ? prev[j] : cur[j - 1]);
    }
    prev = cur;
  }
  return prev[b.length];
}

void main() {
  final dir = 'test/fixtures/import';
  final story = jsonDecode(File('$dir/story.json').readAsStringSync()) as Map<String, dynamic>;
  final chapters = (story['chapters'] as List).cast<Map<String, dynamic>>();
  final paragraphs = [for (final c in chapters) ...(c['paragraphs'] as List).cast<String>()];
  final captions = [for (final c in chapters) ...(c['captions'] as List).cast<String>()];
  final titles = [for (final c in chapters) c['title'] as String];
  final expected = paragraphs.expand(_words).toList();

  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  bool isWord(String w) {
    final l = w.toLowerCase().replaceAll('’', "'");
    return d.lemmatizer.lemmas(l).any(d.lemmatizer.known.contains);
  }

  // Needs the PDFium library: PDFIUM_PATH=/path/to/libpdfium.so (CI downloads it).
  setUpAll(pdfrxInitialize);

  void check(ImportedBook b, String name, {bool hasCaptions = false, bool checkTitles = true}) {
    final paras = [for (final c in b.chapters) ...c.paragraphs];
    final body = [for (final p in paras) if (p.$1 == 'p') p.$2];
    final got = body.expand(_words).toList();
    final arrived = _lcs(expected, got);
    expect(expected.length - arrived, 0,
        reason: '$name: ${expected.length - arrived} of ${expected.length} story words are missing or out of order');
    // No paragraph is cut in two, and nothing (a header, a caption, a page number) is inside one.
    final bodyNorm = body.map(_norm).toList();
    for (final p in paragraphs) {
      final n = _norm(p);
      expect(bodyNorm.any((x) => x.contains(n)), isTrue, reason: '$name: paragraph broken or mixed: "$p"');
    }
    for (final x in body) {
      expect(x.contains('Journal of Made-up Stories'), isFalse, reason: '$name: running header inside the text: $x');
      expect(RegExp(r'Lantern Keeper\b').hasMatch(x) && _words(x).length > 3, isFalse,
          reason: '$name: running header inside the text: $x');
    }
    if (hasCaptions) {
      final caps = [for (final p in paras) if (p.$1 == 'c') _norm(p.$2)];
      for (final c in captions) {
        expect(caps, contains(_norm(c)), reason: '$name: caption not kept apart: $c');
      }
    }
    if (checkTitles) {
      final names = {...b.chapters.map((c) => _norm(c.title)), for (final p in paras) if (p.$1 == 'h') _norm(p.$2)};
      for (final t in titles) {
        expect(names, contains(_norm(t)), reason: '$name: chapter "$t" not found');
      }
    }
  }

  for (final f in ['story.epub', 'story.docx', 'story.odt', 'story.rtf', 'story.html', 'story.md', 'story.txt', 'story.fb2']) {
    test('$f: whole story, in order', () async {
      final b = await importFile('$dir/$f', isWord: isWord);
      check(b, f, checkTitles: !f.endsWith('.txt') && !f.endsWith('.rtf'));
    });
  }

  for (final f in ['book.pdf', 'columns.pdf', 'office.pdf']) {
    test('$f: whole story, in order', () async {
      final b = await importFile('$dir/$f', isWord: isWord);
      check(b, f, hasCaptions: f == 'book.pdf', checkTitles: f != 'office.pdf');
      if (f == 'book.pdf') {
        expect([for (final c in b.chapters) c.title].where(titles.contains).length, titles.length,
            reason: 'chapters follow the contents page');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  test('the saved text of a book has every paragraph', () async {
    final b = await importFile('$dir/book.pdf', isWord: isWord);
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb'));
    final id = u.insertBook(b);
    final text = _norm(u.bookText(id));
    for (final p in paragraphs) {
      expect(text, contains(_norm(p)));
    }
    expect(u.bookText(id), contains('[${captions.first}]'));
  });

  test('a page the scan repeats is read once', () {
    final page = paragraphs.take(3).join('\n');
    final b = buildBookFromPages([page, page, paragraphs[3]], 'T', 'pdf');
    final all = [for (final c in b.chapters) ...c.paragraphs].map((p) => p.$2).join(' ');
    expect(_words(all).length, _words(page).length + _words(paragraphs[3]).length);
  });
}

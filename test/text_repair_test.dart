// Text slips that book files bring with them (see lib/import/text_repair.dart),
// on small examples and on the slips.* fixtures written by
// tools/make_slip_fixtures.py, plus a guard that the repairs leave clean
// English alone.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/import/pdf_import.dart';
import 'package:kelime_okur/import/text_repair.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  bool isWord(String w) {
    final l = w.toLowerCase().replaceAll('’', "'");
    return d.lemmatizer.lemmas(l).any(d.lemmatizer.known.contains);
  }

  // Needs the PDFium library: PDFIUM_PATH=/path/to/libpdfium.so (CI downloads it).
  setUpAll(pdfrxInitialize);

  test('words broken at a line end are joined, compounds keep their hyphen', () {
    String f(String s) => joinBrokenWords(s, isWord);
    expect(f('too conspicuous and dan­gerous for use'), 'too conspicuous and dangerous for use');
    expect(f('the inhabi\u0002tants are now'), 'the inhabitants are now');
    expect(f('a good-for­nothing boy'), 'a good-for-nothing boy');
    expect(f('forty slave­girls'), 'forty slave-girls');
    expect(f('without Badr­al-Budur'), 'without Badr-al-Budur');
  });

  test('hidden characters and symbol-font bullets go', () {
    expect(cleanInvisible(' Once there was a little Tulip'), 'Once there was a little Tulip');
    expect(cleanInvisible('\tIt’s the Rain'), 'It’s the Rain');
    expect(cleanInvisible('a soft­hyphen and zero​width \u0017space'), 'a softhyphen and zerowidth space');
    expect(cleanInvisible('Plain text — with “quotes”, ½ and é.'), 'Plain text — with “quotes”, ½ and é.');
  });

  test('text recognition slips are repaired', () {
    String f(String s) => fixOcrSlips(s, isWord);
    expect(f('Every mormng he ran through the streets'), 'Every morning he ran through the streets');
    expect(f('the most beautiful woman m Morocco'), 'the most beautiful woman in Morocco');
    expect(f("Aladdin,s mother put meat on the table"), "Aladdin's mother put meat on the table");
    expect(f("so I didn 't give him the lamp. Abanazar 's ring"), "so I didn't give him the lamp. Abanazar's ring");
    expect(f('from top to bo�tom.'), 'from top to bottom.');
    expect(f('£arly the next morning'), 'Early the next morning');
    expect(f('into the pocket df his coat'), 'into the pocket of his coat');
    expect(
      f('they do not want change to overwhelmn their traditional customs'),
      'they do not want change to overwhelm their traditional customs',
    );
    expect(f('He came on the 10th of June at 5 m above the sea.'), 'He came on the 10th of June at 5 m above the sea.');
    // Names, abbreviations, old spellings and rare words stay.
    const keep =
        "I'm sure Mr Turnbull and Dashwood saw the cherub. pluckt stretcht macular retellings mRNA iPod "
        'eBay www.example.com hath doth whosoever wherewith';
    expect(f(keep), keep);
  });

  test('symbol-font bullets glued to a word and stray capitals', () {
    expect(
      repairPdfText('uEven with all its energy, Vietnam is still a pOOr country.', isWord),
      'Even with all its energy, Vietnam is still a poor country.',
    );
  });

  test('a drop cap goes back to its word', () {
    expect(joinDropCaps(['A', 'nd as the day passed'], isWord), ['And as the day passed']);
    expect(joinDropCaps(['nd as the day passed', 'A'], isWord), ['And as the day passed']);
    expect(joinDropCaps(['D', 'r Orion Hood paused'], isWord), ['Dr Orion Hood paused']);
    expect(joinDropCaps(['A', 'little cloud rose'], isWord), ['A little cloud rose']);
    expect(joinDropCaps(['Chapter', 'B', 'The end'], isWord), ['Chapter', 'B', 'The end']);
  });

  test('list items run together are split at their bullets', () {
    expect(splitAtBullets('very fair. (Flax.) ■ From house to house he goes. • "Who is that?" she said.'), [
      'very fair. (Flax.)',
      'From house to house he goes.',
      '"Who is that?" she said.',
    ]);
    expect(splitAtBullets(' Once there was a little Tulip'), ['Once there was a little Tulip']);
    expect(splitAtBullets('5 • 3 = 15 and a•b'), ['5 • 3 = 15 and a•b']);
    expect(splitAtBullets('from a little old woman, ■ "And a little old man,"'), [
      'from a little old woman,',
      '"And a little old man,"',
    ]);
    expect(splitAtBullets('Classics • True Stories • Fantasy'), ['Classics • True Stories • Fantasy']);
  });

  test('a sentence cut by a picture after a comma is one paragraph', () {
    final b = buildBookFromPages(
      [
        "'But he knows my name, and my father's name,'\n\nAladdin said. 'And he gave ten pieces of gold to me. He's very nice.'",
      ],
      'T',
      'pdf',
      isWord: isWord,
    );
    final ps = [for (final c in b.chapters) ...c.paragraphs.where((p) => p.$1 == 'p').map((p) => p.$2)];
    expect(ps, [
      "'But he knows my name, and my father's name,' Aladdin said. 'And he gave ten pieces of gold to me. He's very nice.'",
    ]);
  });

  final dir = 'test/fixtures/import';
  final expected = jsonDecode(File('$dir/slips.json').readAsStringSync()) as Map<String, dynamic>;
  List<(String, String)> paras(ImportedBook b) => [for (final c in b.chapters) ...c.paragraphs];

  test('slips.pdf: broken words, drop cap, bullets and a caption mid-sentence', () async {
    final b = await importFile('$dir/slips.pdf', isWord: isWord);
    final body = [
      for (final p in paras(b))
        if (p.$1 == 'p') p.$2,
    ];
    expect(body, (expected['pdf'] as List).cast<String>());
    expect([
      for (final p in paras(b))
        if (p.$1 == 'c') p.$2,
    ], (expected['captions'] as List).cast<String>());
  });

  for (final f in ['slips.docx', 'slips.odt']) {
    test('$f: tabs, line breaks and symbol-font bullets', () async {
      final b = await importFile('$dir/$f', isWord: isWord);
      expect([for (final p in paras(b)) p.$2], (expected['docx'] as List).cast<String>());
    });
  }

  test('plain text: Gutenberg notes, _italics_ and chapter titles', () {
    const txt =
        'The Project Gutenberg eBook of Alice\n\nThis eBook is for the use of anyone.\n\n'
        '*** START OF THE PROJECT GUTENBERG EBOOK ALICE ***\n\n'
        "CHAPTER VIII. The Queen's Croquet-Ground\n\nShe heard a little _tap, tap, tap_ at the door. Fill in: my __ .\n\n"
        'CHAPTER XI. Who Stole the Tarts?\n\nThe King and Queen were seated.\n\n'
        'Part of the fun was the game.\n\n'
        '*** END OF THE PROJECT GUTENBERG EBOOK ALICE ***\n\nSection 1. General Terms of Use';
    final b = importBytes(utf8.encode(txt), 'txt', 'alice');
    expect(
      [for (final c in b.chapters) c.title],
      ["CHAPTER VIII. The Queen's Croquet-Ground", 'CHAPTER XI. Who Stole the Tarts?'],
    );
    final all = paras(b).map((p) => p.$2).join('\n');
    expect(all, contains('She heard a little tap, tap, tap at the door. Fill in: my __ .'));
    expect(all, contains('Part of the fun was the game.'));
    expect(all, isNot(contains('Gutenberg')));
    expect(all, isNot(contains('General Terms')));
  });

  test('HTML and EPUB: Project Gutenberg notes are left out', () {
    const page =
        '<html><body><section id="pg-header">The Project Gutenberg eBook of Alice</section>'
        '<h2>Chapter 1</h2><p>Alice was beginning to get very tired.</p>'
        '<section class="pg-boilerplate" id="pg-footer">START: FULL LICENSE</section></body></html>';
    final b = importBytes(utf8.encode(page), 'html', 'alice');
    expect(paras(b).map((p) => p.$2).toList(), ['Chapter 1', 'Alice was beginning to get very tired.']);
  });

  test('books saved before these repairs are repaired once', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb'));
    final pdfId = u.insertBook(
      ImportedBook('P', null, 'pdf', [
        ImportedChapter('One', [('p', 'Every mormng he ran. It was dan\u0002gerous. uEven so, a pOOr boy.')]),
      ]),
    );
    final epubId = u.insertBook(
      ImportedBook('E', null, 'epub', [
        ImportedChapter('One', [('p', 'A soft­hyphen and a mormng.')]),
      ]),
    );
    String fix(String t, String format) =>
        format == 'pdf' || format == 'image' ? repairPdfText(t, isWord) : cleanInvisible(t);
    u.repairImportedTextOnce(fix);
    String text(int id) => (u.db.select('SELECT text FROM paras WHERE book_id=?', [id]).first['text'] as String);
    expect(text(pdfId), 'Every morning he ran. It was dangerous. Even so, a poor boy.');
    // Only PDFs and pictures get the recognition repairs.
    expect(text(epubId), 'A softhyphen and a mormng.');
    // Once only.
    u.db.execute('UPDATE paras SET text=? WHERE book_id=?', ['mormng', pdfId]);
    u.repairImportedTextOnce(fix);
    expect(text(pdfId), 'mormng');
  });

  test('clean English is left alone: WordNet glosses and examples', () {
    // Two foreign words read as recognition slips ("chili con carne" -> "came",
    // "Ovis ammon" -> "amnion"): the price of repairing "mormng"; only PDFs and
    // pictures get these repairs.
    const known = 2;
    var changed = 0;
    final samples = <String>[];
    for (final r in d.db.select('SELECT gloss, examples FROM syn')) {
      for (final t in ['${r['gloss']}', '${r['examples'] ?? ''}']) {
        if (t.isEmpty) continue;
        final f = repairPdfText(t, isWord);
        if (f != t) {
          changed++;
          if (samples.length < 10) samples.add('$t\n  -> $f');
        }
      }
    }
    expect(changed, lessThanOrEqualTo(known), reason: samples.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));
}

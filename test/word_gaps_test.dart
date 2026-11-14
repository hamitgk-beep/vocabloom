import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/pdf_import.dart';
import 'package:kelime_okur/import/word_gaps.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  bool isWord(String w) {
    final l = w.toLowerCase().replaceAll('’', "'");
    return d.lemmatizer.lemmas(l).any(d.lemmatizer.known.contains);
  }

  test('glued function words are split', () {
    String f(String s) => splitJoinedWords(s, isWord);
    expect(f('as a pole witha rice basket'), 'as a pole with a rice basket');
    expect(f('the end ofthe road'), 'the end of the road');
    expect(f('he went tothe market inthe morning'), 'he went to the market in the morning');
  });

  test('real words, names and URLs are kept', () {
    String f(String s) => splitJoinedWords(s, isWord);
    const keep = [
      'Welcome to Vietnam. The shape of this beautiful country is described by the Vietnamese people.',
      'Lining many streets are the stalls of vendors, motorcycles, motorbikes, and scooters.',
      'three-wheeled pedicabs (bicycles pulling passenger carriages) hysterically appetizing',
      'Visit www.harcourtschool.com and Ina, Tomas, Withers or Hebert.',
      'another often theatre within without anyway into onto inside thereby atone herein attire',
      'washing toward Hamlet tomato tooth season aside abroad asleep oneself nowhere',
      'herself cannot whereof amidst adown ahold withall menthe della firma habitan heare weare',
    ];
    for (final s in keep) {
      expect(f(s), s);
    }
  });

  test('gap spaces from glyph positions', () {
    // "witha" where the 'a' sits a word space away from "with".
    GlyphBox box(double l, double r) => (left: l, top: 10, right: r, bottom: 0);
    final text = 'witha';
    final boxes = [box(0, 7), box(8, 10), box(11, 13), box(14, 19), box(23, 29)];
    expect(addGapSpaces(text, boxes, isWord), 'with a');
    // Same letters tightly set: a real word stays whole.
    final word = 'within';
    final wb = [box(0, 7), box(8, 10), box(11, 13), box(14, 19), box(20, 22), box(23, 29)];
    expect(addGapSpaces(word, wb, isWord), 'within');
    // Wide letter spacing inside a known word is not split.
    final wide = [box(0, 7), box(11, 13), box(17, 19), box(23, 29), box(33, 35), box(39, 45)];
    expect(addGapSpaces(word, wide, isWord), 'within');
  });

  test('book from pages fixes glued words', () {
    final b = buildBookFromPages(
      [
        'Welcome to Vietnam. The shape of this beautiful country is described by the Vietnamese people as a pole witha rice basket on each end.',
      ],
      'T',
      'pdf',
      isWord: isWord,
    );
    expect(b.chapters.first.paragraphs.first.$2, contains('pole with a rice basket'));
  });

  test('books imported earlier are repaired once', () {
    final dir = Directory.systemTemp.createTempSync('vb');
    final u = UserDb.open(dir);
    final pdf = u.insertBook(
      ImportedBook('P', null, 'pdf', [
        ImportedChapter('C', [('p', 'a pole witha rice basket')]),
      ]),
    );
    final epub = u.insertBook(
      ImportedBook('E', null, 'epub', [
        ImportedChapter('C', [('p', 'a pole witha rice basket')]),
      ]),
    );
    u.repairJoinedWordsOnce((t) => splitJoinedWords(t, isWord));
    expect(u.paras(pdf, 0).first.text, 'a pole with a rice basket');
    expect(u.paras(epub, 0).first.text, 'a pole witha rice basket');
    var calls = 0;
    u.repairJoinedWordsOnce((t) {
      calls++;
      return t;
    });
    expect(calls, 0);
    u.db.close();
    dir.deleteSync(recursive: true);
  });
}

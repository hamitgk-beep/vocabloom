// The Dictionary tab's search: English → Turkish, Turkish → English (accents
// optional) and the word list shown before anything is typed.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/data/dict_db.dart';

late DictDb d;

void main() {
  setUpAll(() {
    d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
  });

  test('Turkish word finds its English word first', () {
    expect(d.searchTurkish('kitap').first.$1, 'book');
    expect(d.searchTurkish('köpek').first.$1, 'dog');
    expect(d.searchTurkish('kopek').first.$1, 'dog', reason: 'accents are optional');
    expect(d.searchTurkish('KÖPEK').first.$1, 'dog');
    expect(d.searchTurkish('ev').take(3).map((r) => r.$1), contains('house'));
    expect(d.searchTurkish('güzel').take(3).map((r) => r.$1), anyOf(contains('beautiful'), contains('pretty')));
  });

  test('English derived words inside meanings are not Turkish matches', () {
    expect(d.searchTurkish('wor').map((r) => r.$1), isNot(contains('worry')));
  });

  test('Turkish letters are not searched as English', () {
    expect(d.searchWords('köpek'), isEmpty);
    expect(d.searchWords('wor').first, startsWith('wor'));
  });

  test('word list: common words without names or grammar words, and by letter', () {
    final common = d.commonWords(limit: 50);
    expect(common, hasLength(50));
    expect(common, isNot(contains('tom')));
    expect(common, isNot(contains('the')));
    expect(common, contains('know'));
    expect(d.commonWords(limit: 10, offset: 10), common.sublist(10, 20));
    final b = d.searchWords('b', limit: 100);
    expect(b, hasLength(100));
    expect(b.every((w) => w.startsWith('b')), isTrue);
    expect(d.searchWords('b', limit: 10, offset: 10), b.sublist(10, 20));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/review.dart';
import 'package:kelime_okur/data/user_db.dart';

ImportedBook _book(String title, String text) => ImportedBook(title, null, 'txt', [
      ImportedChapter('1', [('p', text)]),
    ]);

void main() {
  late Directory dir;
  late UserDb u;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lang_sep_');
    u = UserDb.open(dir);
  });
  tearDown(() {
    u.db.dispose();
    dir.deleteSync(recursive: true);
  });

  test('each language has its own saved words and reviews', () {
    u.setWord('house', WordStatus.learning, meaning: 'ev');
    u.lang = 'tr';
    expect(u.statuses, isEmpty);
    expect(u.words(WordStatus.learning), isEmpty);
    u.setWord('ev', WordStatus.learning, meaning: 'house');
    // The same spelling in both languages stays two words.
    u.setWord('on', WordStatus.learned, meaning: 'ten');
    expect(u.words(WordStatus.learning).map((w) => w.lemma), ['ev']);
    expect(ReviewStore(u).due().map((c) => c.word.lemma), ['ev']);
    u.lang = 'en';
    expect(u.statuses.keys, ['house']);
    expect(u.statuses['on'], isNull);
    expect(u.words(WordStatus.learning).map((w) => w.lemma), ['house']);
    expect(ReviewStore(u).due().map((c) => c.word.lemma), ['house']);
    // Reopening keeps the separation.
    u.db.dispose();
    u = UserDb.open(dir);
    expect(u.statuses.keys, ['house']);
    u.lang = 'tr';
    expect(u.statuses.keys.toSet(), {'ev', 'on'});
  });

  test('a review answer is kept for its own language', () {
    final r = ReviewStore(u);
    u.lang = 'tr';
    u.setWord('ev', WordStatus.learning);
    r.answer('ev', 0, ReviewAnswer.good);
    expect(r.due(), isEmpty);
    u.lang = 'en';
    u.setWord('ev', WordStatus.learning);
    expect(r.due().map((c) => c.word.lemma), ['ev']);
  });

  test('books are listed under the language of their text', () {
    expect(UserDb.textLang(_book('a', 'Bir varmış bir yokmuş, çok uzak bir ülkede küçük bir kız yaşarmış.')), 'tr');
    expect(UserDb.textLang(_book('b', 'Once upon a time a little girl lived in a faraway land.')), 'en');
    u.insertBook(_book('Masal', 'Bir varmış bir yokmuş, çok uzak bir ülkede küçük bir kız yaşarmış.'));
    u.insertBook(_book('Tale', 'Once upon a time a little girl lived in a faraway land.'));
    expect(u.books().map((b) => b.title), ['Tale']);
    u.lang = 'tr';
    expect(u.books().map((b) => b.title), ['Masal']);
    expect(u.books(lang: 'en').map((b) => b.title), ['Tale']);
  });
}

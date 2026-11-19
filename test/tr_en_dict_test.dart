import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';

void main() {
  final d = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));

  test('Turkish lower case', () {
    expect(TrEnDict.lower('İYİ'), 'iyi');
    expect(TrEnDict.lower('IŞIK'), 'ışık');
  });

  test('a word, an inflected form and an apostrophe find their base word', () {
    expect(d.lemmas('ev').first, 'ev');
    expect(d.lemmas('evlerimizden'), contains('ev'));
    expect(d.lemmas('İstanbul\'da').first, 'istanbul');
    expect(d.lemmas('İyi').first, 'iyi');
  });

  test('a common base word wins over a rare one', () {
    expect(d.lemmas('onu').first, 'o');
  });

  test('endings the tables leave out', () {
    expect(['sen', 'senin'], contains(d.lemmas('seninle').first));
    expect(d.lemmas('olduğumu').first, 'olmak');
    expect(d.lemmas('yaptığını').first, 'yapmak');
  });

  test('an entry has English meanings and examples', () {
    final e = d.entry('kitap')!;
    expect(e.senses.first.glosses.first.toLowerCase(), contains('book'));
    expect(e.examples, isNotEmpty);
  });
}

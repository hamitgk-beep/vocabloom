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

  test('an English meaning finds the Turkish word', () {
    expect(d.searchEnglish('dog').map((e) => e.$1).take(5), contains('köpek'));
    expect(d.searchEnglish('book').first.$1, 'kitap');
  });

  test('the word list starts with the most common words', () {
    expect(d.commonWords(limit: 50), containsAll(['bir', 've']));
    expect(d.search('kit').first, 'kitap');
  });

  test('wrong options for a review quiz are English meanings', () {
    final g = d.randomGlosses(limit: 50);
    expect(g.length, greaterThan(20));
  });

  test('the words around a word pick its meaning', () {
    List<String> ctx(String s) => [for (final w in s.split(' ')) d.lemmas(w).firstOrNull ?? w];
    String? gloss(String lemma, String sentence) {
      final g = d.meaningInContext(lemma, ctx(sentence));
      if (g == null) return null;
      return [for (final s in d.entry(lemma)!.senses) ...s.glosses][g];
    }

    expect(gloss('sürmek', 'program yaklaşık on yıl sürmüştür'), contains('last'));
    expect(gloss('sürmek', 'arabayı çok hızlı sürdü'), contains('drive'));
    expect(gloss('yüz', 'üç yüz dolar'), 'hundred');
    expect(gloss('yüz', 'güzel bir yüz'), contains('face'));
    expect(gloss('çekmek', 'çok acı çekti'), contains('endure'));
  });
}

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review_quiz.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:sqlite3/sqlite3.dart';

DictDb openDict() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return d;
}

SavedWord saved(String lemma, String? ctx) => SavedWord(lemma, WordStatus.learning, ctx, null, null, DateTime.now());

void main() {
  final d = openDict();

  test('golf course: the sentence meaning is the sports ground, never "akmak"', () {
    const s = 'American-style supermarkets and a new golf course can now be found in Ho Chi Minh City.';
    final m = d.meaningIn('course', s);
    expect(m.pos, 'n');
    expect(m.sense?.gloss, contains('sport'));
    expect(m.tr ?? '', isNot(contains('akmak')));
  });

  // Hamit: "through" saved from a book was asked as "aktarmasız, direkt"; the
  // card asks the word's most common meaning, not the book's sense, and only
  // grades it when the context picker confirms it for the card's sentence
  // (ReviewQuiz.confirms). Unconfirmed: a plain flashcard, nothing graded.
  test('review card: the most common meaning, graded only when the sentence confirms it', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('rq'));
    const train = 'We took a through train from London to Edinburgh.';
    const golf = 'American-style supermarkets and a new golf course can now be found in Ho Chi Minh City.';
    for (final (lemma, s, graded) in [
      ('through', train, false),
      ('bank', 'They sat on the bank of the river.', false),
      ('bank', 'The bank approved the loan.', true),
      ('course', golf, false),
    ]) {
      final common = d.commonMeaning(lemma);
      expect(common.tr, isNotNull, reason: lemma);
      final q = ReviewQuiz(d, u, rnd: Random(1));
      expect(q.answerFor(saved(lemma, s)).tr, common.tr, reason: lemma);
      final ch = q.choiceFor(saved(lemma, s));
      expect(ch?.right, graded ? common.tr : null, reason: '$lemma in "$s"');
      // The same word saved with no sentence asks the common meaning.
      final plain = ReviewQuiz(d, u, rnd: Random(1)).choiceFor(saved(lemma, null))!;
      expect(plain.right, common.tr, reason: lemma);
      expect(plain.options.toSet().length, 4, reason: lemma);
    }
    // ft's first meaning (DictDb.sourcePolicy); the AI draft said "boyunca, baştan sona".
    expect(d.commonMeaning('through').tr, 'boyunca');
    expect(d.commonMeaning('except').tr, 'dışında, hariç'); // ft order; the AI draft said "hariç, dışında"
    // KNOWN WEAKNESS (reported): ft's first meaning of course is "mecra"; the AI draft's
    // "kurs, ders" reads better but is unreviewed. It is only graded on a card with no sentence.
    expect(d.commonMeaning('course').tr, 'mecra');
    expect(d.commonMeaning('bank').tr, contains('banka'));
    // A meaning the AI service gave for the sentence does not replace the
    // dictionary's common meaning, and does not make it graded.
    u.setContextAi('course', golf, 'saha, golf sahası');
    expect(ReviewQuiz(d, u, rnd: Random(1)).answerFor(saved('course', golf)).tr, 'mecra');
    expect(ReviewQuiz(d, u, rnd: Random(1)).choiceFor(saved('course', golf)), isNull);
  });

  test('simply is "sadece", with four choices', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('rq'));
    const s = 'How often does some crime come to light simply by reason of a bit of unmitigated bungling, '
        'and each tune one asks oneself the question: If this hadn\'t been bungled, would anyone ever have known?';
    final q = ReviewQuiz(d, u, rnd: Random(2));
    // ft's first meaning (DictDb.sourcePolicy); the AI draft said "sadece, yalnızca".
    expect(q.answerFor(saved('simply', s)).tr, 'sadece');
    // In this long sentence the context picker does not confirm it: shown, not graded.
    expect(q.choiceFor(saved('simply', s)), isNull);
    final ch = ReviewQuiz(d, u, rnd: Random(2)).choiceFor(saved('simply', null))!;
    expect(ch.right, 'sadece');
    expect(ch.options.toSet().length, 4);
  });

  test('a lesson course is still "ders, kurs"', () {
    final m = d.meaningIn('course', 'She took an evening course in English literature.');
    expect(m.tr, contains('ders'));
  });

  // Every word people meet often, in real sentences: the question must have
  // exactly one right option (the word's most common meaning), three different
  // wrong ones, no wrong option that is also a meaning of the word, and a noun
  // meaning is never answered with a verb.
  test('audit: questions of common words in real sentences', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('rq'));
    final q = ReviewQuiz(d, u, rnd: Random(7));
    final rows = d.db.select(
        "SELECT substr(e.key, 3) AS w, e.en FROM exs e JOIN wfreq f ON f.word = substr(e.key, 3) "
        "WHERE e.key LIKE 'w:%' AND length(substr(e.key, 3)) > 3 GROUP BY e.key ORDER BY f.n DESC LIMIT 1500");
    var asked = 0, flash = 0, unsure = 0, untranslatable = 0, notGraded = 0, other = 0, unknown = 0;
    final seenLemma = <String>{};
    final unsureList = <String>[];
    final bad = <String>[];
    for (final r in rows) {
      // Words are saved under their dictionary form ("said" -> "say").
      final ls = d.lemmatizer.lemmas(r['w'] as String);
      int freq(String x) => (d.db.select('SELECT n FROM wfreq WHERE word=?', [x]).firstOrNull?['n'] as int?) ?? 0;
      final known = [...ls.where((l) => !d.lookup(l).isEmpty)]..sort((a, b) => freq(b) - freq(a));
      final irr = d.irregularOf[(r['w'] as String).toLowerCase()];
      final w = irr != null ? irr.first : known.isEmpty ? ls.first : known.first;
      final s = r['en'] as String;
      // Names and words the dictionary has no Turkish for at all ("Esperanto").
      final info = d.lookup(w);
      if (info.trFreeDict.isEmpty && info.senses.every((x) => x.tr.isEmpty)) {
        untranslatable++;
        continue;
      }
      if (!seenLemma.add(w)) continue;
      final ch = q.choiceFor(saved(w, s));
      final a = q.answerFor(saved(w, s));
      if (!a.choice) {
        // Not confirmed for the sentence: a plain flashcard, never a wrong
        // "right" answer.
        notGraded++;
        final f = q.fit(w, s, a.tr!);
        if (f == SentenceFit.other) other++;
        if (f == SentenceFit.unknown) unknown++;
        continue;
      }
      if (ch == null) {
        flash++;
        bad.add('$w: no four-choice question for "$s"');
        continue;
      }
      if (!a.sure) {
        unsure++;
        unsureList.add('$w\t${a.gloss}\t$s');
      }
      asked++;
      final own = d.trWordsOf(w);
      if (ch.options.length != 4 || ch.options.toSet().length != 4) bad.add('$w: duplicate options ${ch.options}');
      if (ch.options.where((o) => o == ch.right).length != 1) bad.add('$w: right answer not once');
      if (ch.right != DictDb.shortTr(a.tr!)) bad.add('$w: right ${ch.right} is not the common meaning ${a.tr}');
      for (var i = 0; i < 4; i++) {
        if (i == ch.correct) continue;
        final parts = ch.options[i].toLowerCase().split(RegExp(r'[,;]')).map((e) => e.trim());
        if (parts.any(own.contains)) bad.add('$w: wrong option "${ch.options[i]}" is also a meaning of the word');
        if (a.pos == null && DictDb.isTrVerb(ch.options[i]) != DictDb.isTrVerb(ch.right)) bad.add('$w: mixed verb/non-verb options ${ch.options}');
      }
      if (a.pos == 'n' && DictDb.isTrVerb(ch.right) && !ch.right.contains(' ')) bad.add('$w: noun answered with verb "${ch.right}"');
    }
    // ignore: avoid_print
    print('audit: ${rows.length} words, $asked four-choice questions, $flash flashcards, $notGraded not graded (picker chose another meaning: $other, chose none: $unknown), $unsure answers guessed, $untranslatable words with no Turkish at all');
    final dump = Platform.environment['AUDIT_UNSURE'];
    if (dump != null) File(dump).writeAsStringSync(unsureList.join('\n'));
    expect(bad, isEmpty, reason: bad.take(30).join('\n'));
    expect(flash, 0);
    // The price of never grading an unconfirmed answer (measured: 625 graded,
    // 639 not, of 1,264). The floor keeps the share of graded cards from
    // falling further unnoticed.
    expect(asked, greaterThan(rows.length * 0.38));
    expect(untranslatable, lessThan(rows.length * 0.02));
    expect(unsure, lessThan(rows.length * 0.03));
  });

  test('machine-made book titles get a title from the text', () {
    expect(looksGeneratedTitle('9bfdefed-8b6d-4c1e-9a7b-2f3c4d5e6f70'), isTrue);
    expect(looksGeneratedTitle('1f3a9c0b7d2e4f5a'), isTrue);
    expect(looksGeneratedTitle('msf:1234'), isTrue);
    expect(looksGeneratedTitle('Animal Farm'), isFalse);
    expect(looksGeneratedTitle('1984'), isFalse);
    expect(titleFromContent(['Bölüm 1'], [('h', 'Vietnam Opens Up'), ('p', 'Text.')]), 'Vietnam Opens Up');
    expect(titleFromContent(['Chapter 1'], [('p', 'American-style supermarkets are here. More text.')]),
        'American-style supermarkets are here.');
    final b = withReadableTitle(ImportedBook('9bfdefed-8b6d-4c1e-9a7b-2f3c4d5e6f70', null, 'pdf', [
      ImportedChapter('Saigon Today', [('p', 'Hello.')])
    ]));
    expect(b.title, 'Saigon Today');

    final u = UserDb.open(Directory.systemTemp.createTempSync('rt'));
    const old = '9bfdefed-8b6d-4c1e-9a7b-2f3c4d5e6f70';
    u.insertBook(ImportedBook(old, null, 'pdf', [ImportedChapter('Chapter 1', [('h', 'Saigon Today'), ('p', 'Hi.')])]));
    u.setWord('course', WordStatus.learning, context: 'a golf course', book: old);
    u.repairBookTitles(looksGeneratedTitle, titleFromContent);
    expect(u.books().single.title, 'Saigon Today');
    expect(u.words(WordStatus.learning).single.bookTitle, 'Saigon Today');
  });
}

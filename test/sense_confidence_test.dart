// Task 5B regressions: a wrong meaning must not be shown as sure, and old
// cards must not change. Each case stands for a general rule, named in its
// test; none of the rules lists words.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review_quiz.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  final engine = SenseEngine(d);
  final tr = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));

  ContextSense at(String sentence, String word) {
    final toks = tokenize(sentence);
    final i = toks.indexWhere((t) => t.lower == word.toLowerCase());
    expect(i, greaterThanOrEqualTo(0), reason: '$word not in "$sentence"');
    return engine.resolve(SenseQuery(sentence: sentence, tokens: toks, index: i));
  }

  group('no wrong "sure"', () {
    test('Rector\'s next stop was …: the noun, and the verb "durmak" is not shown as sure', () {
      final c = at("Rector's next stop was the old church.", 'stop');
      expect(c.best?.pos, 'n', reason: c.reason);
      expect(c.confidence == SenseConfidence.sure && (c.tr ?? '').contains('durmak'), isFalse, reason: c.reason);
    });

    test('an AI draft is sure only when a checked meaning of the same part of speech has its Turkish', () {
      // The main meaning list has "durmak" too; it no longer counts, being the
      // drafts' own source and having no part of speech.
      for (final (s, w) in [
        ("Rector's next stop was the old church.", 'stop'),
        ('The bus stop is near my house.', 'stop'),
        ('We need more chairs for the meeting.', 'chairs'),
        ('Commerce and industry grew quickly.', 'Commerce'),
      ]) {
        final c = at(s, w);
        final b = c.best;
        if (b == null || !b.unverified || c.confidence != SenseConfidence.sure) continue;
        final checked = c.ranked.where((x) => !x.unverified && (x.pos == null || b.pos == null || x.pos == b.pos));
        expect(checked.any((x) => x.tr.any(b.tr.contains)), isTrue, reason: '$w in "$s": ${c.reason}');
      }
    });

    test('a sure meaning has Turkish of its part of speech (a verb a verb, a noun no verb)', () {
      for (final (s, w) in [
        ('Please stop the car.', 'stop'),
        ('The bus stop is near my house.', 'stop'),
        ('She runs a small company.', 'runs'),
        ('They sat on the river bank.', 'bank'),
        ('It is not within the scope of this report to elaborate in great detail.', 'elaborate'),
      ]) {
        final c = at(s, w);
        if (c.confidence != SenseConfidence.sure || c.best?.pos == null) continue;
        final shown = c.best!.tr.take(3);
        final verbs = shown.where(DictDb.isTrVerb).length;
        expect(c.best!.pos == 'v' ? verbs > 0 : verbs < shown.length, isTrue, reason: '$w: ${c.best!.tr} ${c.reason}');
      }
    });

    test('a noun in a noun group is not a sure verb ("Deep tissue massage")', () {
      for (final (s, w) in [
        ('Deep tissue massage helps after a long run.', 'tissue'),
        ('The police station was closed.', 'station'),
        ('US troops fired into the crowd.', 'troops'),
      ]) {
        final c = at(s, w);
        expect(c.confidence == SenseConfidence.sure && c.best?.pos == 'v', isFalse, reason: '$w: ${c.reason}');
      }
    });

    test('a comma ends the object: "He showered, shaved" is not "shower someone with"', () {
      final c = at('He showered, shaved, dressed and went down to breakfast.', 'showered');
      expect(c.confidence == SenseConfidence.sure && (c.tr ?? '').contains('yağdırmak'), isFalse, reason: c.reason);
    });

    test('the clear cases stay sure', () {
      expect(at('Please stop the car.', 'stop').confidence, SenseConfidence.sure);
      expect(at('The bank approved the loan.', 'bank').tr, contains('banka'));
    });
  });

  group('names', () {
    test('"Nook" inside a sentence is not shown as sure "köşe"; the word "nook" still is a word', () {
      final n = at('I bought a Nook last week and love it.', 'Nook');
      expect(n.confidence, isNot(SenseConfidence.sure), reason: n.reason);
      final w = at('She sat in a cozy nook by the window.', 'nook');
      expect(w.tr, contains('köşe'));
    });

    test('a word the dictionary knows as a name gets no common meaning ("John" is not "tuvalet")', () {
      final c = at('The judge replaced John Montague Steadman.', 'John');
      expect(c.shown, isFalse, reason: c.reason);
    });

    test('a name\'s own meaning stays ("Iraq" → Irak)', () {
      final c = at('The troops left Iraq in December.', 'Iraq');
      expect(c.tr ?? '', contains('Irak'));
    });

    test('the first word of a sentence is not taken for a name', () {
      expect(SenseEngine.nameLike('Nook is a small word.', tokenize('Nook is a small word.'), 0), isFalse);
      expect(SenseEngine.nameLike('Note: Bill came.', tokenize('Note: Bill came.'), 1), isFalse);
      expect(SenseEngine.nameLike('I met Bill there.', tokenize('I met Bill there.'), 2), isTrue);
    });
  });

  group('idioms', () {
    test('an idiom made of ordinary words is never sure, and never confirms a card', () {
      for (final (s, phrase) in [
        ('Drinks are on the house tonight.', 'on the house'),
        // the noun group goes on: the words are meant one by one
        ('Stone attacks were reported on the houses of the magistrate.', 'on the house'),
        ('Ian Osborne is my guest in this piece.', 'be my guest'),
      ]) {
        final q = SenseQuery.find(d, s, phrase);
        if (q.expr == null) continue;
        final c = engine.resolve(q);
        // Read as the idiom: never sure (the words read one by one may be).
        if (c.cat != null) expect(c.confidence, isNot(SenseConfidence.sure), reason: '$phrase: ${c.reason}');
        if (q.expr!.tr != null) expect(engine.fit(phrase, s, q.expr!.tr!).confirmed, isFalse, reason: phrase);
      }
    });

    test('phrasal verbs keep their own checks: "looked up at the sky"', () {
      final c = engine.resolve(SenseQuery.find(d, 'She looked up at the sky.', 'look up'));
      expect(c.tr, contains('yukarı bakmak'));
    });
  });

  group('English base forms', () {
    test('a noun of its own in -er is not a comparative: customer, owner, buffer, opener', () {
      for (final w in ['customer', 'owner', 'buffer', 'opener', 'customers', 'owners']) {
        expect(d.headword(w), w.replaceAll(RegExp(r's$'), ''), reason: w);
      }
    });

    test('real comparatives and superlatives still reach the adjective', () {
      expect(d.headword('longer'), 'long');
      expect(d.headword('bigger'), 'big');
      expect(d.headword('lowest'), 'low');
      expect(d.headword('number'), 'number');
    });
  });

  group('Turkish base forms', () {
    test('an entry that is only a form of another word comes after it', () {
      expect(tr.lemmas('annesi').first, 'anne');
      expect(tr.lemmas('yılında').first, 'yıl');
      // a form with a meaning of its own keeps it first
      expect(tr.lemmas('içinde').first, 'içinde');
    });

    test('noun endings the tables leave out, with vowel harmony and softening', () {
      expect(tr.lemmas('tehlikesi'), ['tehlike']);
      expect(tr.lemmas('hesabına'), ['hesap']);
      expect(tr.lemmas('kendinden').first, isNot('kent'));
      expect(tr.isGuess('tehlikesi'), isTrue);
      expect(tr.isGuess('ev'), isFalse);
      expect(tr.isGuess('evlerimizden'), isFalse);
    });

    test('a negative verb form reaches the verb', () {
      expect(tr.lemmas('olmadığından').first, 'olmak');
    });
  });

  group('review cards', () {
    test('a saved meaning is kept as it was saved and the card is not rewritten', () {
      final u = UserDb.open(Directory.systemTemp.createTempSync('sc'));
      const s = "Rector's next stop was the old church.";
      u.setWord('stop', WordStatus.learning, context: s, meaning: 'durmak');
      final before = u.words(WordStatus.learning).firstWhere((w) => w.lemma == 'stop');
      final q = ReviewQuiz(d, u, rnd: Random(1), senses: engine);
      final a = q.answerFor(before);
      expect(a.tr, 'durmak');
      // The verb meaning is not confirmed for the noun in this sentence: shown, not graded.
      expect(a.choice, isFalse);
      final after = u.words(WordStatus.learning).firstWhere((w) => w.lemma == 'stop');
      expect([after.meaning, after.context, after.status], [before.meaning, before.context, before.status]);
    });

    test('a noun meaning never confirms a verb answer, also when the meaning is an AI draft', () {
      final f = engine.fit('stop', 'The bus stop is near my house.', 'durmak');
      expect(f.confirmed, isFalse, reason: f.why);
    });
  });
}

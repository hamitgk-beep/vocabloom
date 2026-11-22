// Sentence analysis: where a sentence ends, which words it has, which
// dictionary word a written word stands for, its part of speech, and that the
// reader, the word panel and the context picker look at the same sentence.
// The examples here were looked at while the rules were written; the
// independent measurements are in text_eval_test.dart and sense_eval_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  final engine = SenseEngine(d);

  group('words', () {
    test('letters with accents stay inside the word', () {
      expect(tokenize('The Zurbarán paintings in a naïve café.').map((t) => t.text), ['The', 'Zurbarán', 'paintings', 'in', 'a', 'naïve', 'café']);
    });
    test('every token is the text at its place', () {
      const t = "Don’t go — it’s a well-known résumé, isn't it?";
      for (final k in tokenize(t)) {
        expect(t.substring(k.start, k.end), k.text);
      }
    });
  });

  group('the dictionary word of a written word', () {
    String forms(String w) => d.baseForms(w).map((b) => b.lemma).join(' ');
    test('an ending is taken off only where it is an ending', () {
      expect(d.headword('only'), 'only');
      expect(d.headword('thing'), 'thing');
      expect(d.headword('letter'), 'letter');
      expect(d.headword('daily'), 'daily');
      expect(d.headword('offer'), 'offer');
      expect(d.headword('upper'), 'upper');
      expect(forms('sites'), isNot(contains('sit ')));
      expect(forms('offer'), isNot(contains('off ')));
    });
    test('plain plurals and past forms go to their base', () {
      expect(d.headword('years'), 'year');
      expect(d.headword('things'), 'thing');
      expect(d.headword('stopped'), 'stop');
      expect(d.headword('goes'), 'go');
      expect(d.headword('went'), 'go');
      expect(d.headword('is'), 'be');
    });
    test('the ending says which part of speech the base has', () {
      final train = d.baseForms('training').firstWhere((b) => b.lemma == 'train');
      expect(train.pos, {'v'}); // never the noun (a train)
      expect(d.baseForms('years').first.pos, {'n'});
      expect(d.baseForms('went').first.pos, {'v'});
    });
    test('the picker names the same word', () {
      for (final w in ['only', 'years', 'letter', 'stopped', 'offer']) {
        expect(engine.lemmaOf(w), d.headword(w), reason: w);
      }
    });
    test('"training" in a sentence is not shown as a train', () {
      final r = engine.resolve(SenseQuery.find(d, 'The training lasted two weeks.', 'training'));
      expect(r.best?.tr ?? const <String>[], isNot(contains('tren')));
    });
  });

  group('expressions stay inside one sentence', () {
    List<String> found(String t) => [for (final m in d.matcher.match(tokenize(t), text: t)) m.expr.phrase];
    test('no expression is made of the end of one sentence and the start of the next', () {
      expect(found('She did not care. For him it was over.'), isNot(contains('care for')));
      expect(found('It was hot. Air came in.'), isNot(contains('hot air')));
      expect(found('He kicked the bucket. List it.'), isNot(contains('bucket list')));
    });
    test('inside a sentence they are still found', () {
      expect(found('They care for him.'), contains('care for'));
      expect(found('He gave up. Then he left.'), contains('give up'));
      expect(found('He kicked the bucket. List it.'), contains('kick the bucket'));
    });
  });

  group('clauses and part of speech', () {
    String? pos(String s, String w) {
      final toks = tokenize(s);
      final i = toks.indexWhere((t) => t.lower == w);
      return guessPos(toks, i, d.posOf(w), posOf: d.posOf, breaks: clauseBreaks(s, toks));
    }

    test('clause marks are found between the words', () {
      const s = 'They defend rights, the state said (again).';
      final b = clauseBreaks(s, tokenize(s))!;
      // They defend rights | the state said | again |
      expect(b, [true, false, false, true, false, false, true, true]);
    });
    test('tokens of a paragraph are placed in their sentence', () {
      const p = 'One came. They defend rights, the state said.';
      final toks = tokenize(p);
      final s = sentenceAt(p, toks, 4);
      expect(clauseBreaks(s.text, s.tokens), [true, false, false, true, false, false, true]);
    });
    final cases = <(String, String, String)>[
      ('The fans were loud.', 'fans', 'n'),
      ('He walks home.', 'walks', 'v'),
      ('He wrote studies of art.', 'studies', 'n'),
      ('The rules that benefit the rich stay.', 'benefit', 'v'),
      ('She likes the complex one.', 'complex', 'a'),
      ('Further, the plan failed.', 'further', 'r'),
      ('We will do it later.', 'later', 'r'),
      ('They defend property rights, the state said.', 'rights', 'n'),
    ];
    for (final (s, w, p) in cases) {
      test('$w in "$s" is $p', () => expect(pos(s, w), p));
    }
  });

  group('an expression or its plain words', () {
    ContextSense phrase(String s, String p) => engine.resolve(SenseQuery.find(d, s, p));
    test('clear uses are still told apart', () {
      expect(phrase('He finally kicked the bucket last winter.', 'kick the bucket').cat, 'idioms');
      expect(phrase('The boy kicked the bucket across the yard.', 'kick the bucket').literalPhrase, 'kick the bucket');
      expect(phrase('A joke helped to break the ice at the meeting.', 'break the ice').cat, 'idioms');
    });
    test('the head start of an expression is not counted as proof', () {
      // Shown as the idiom, but the sentence is about eating: not "sure".
      final r = phrase('She ate a piece of cake after dinner.', 'piece of cake');
      expect(r.confidence, isNot(SenseConfidence.sure));
      // And the plain reading is not "sure" either when the idiom is as near.
      final l = phrase('The plan was a piece of cake for her team.', 'piece of cake');
      expect(l.confidence, isNot(SenseConfidence.sure));
    });
  });

  group('the reader and the panel look at the same sentence', () {
    late AppState app;
    setUpAll(() {
      app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('storilex_sa')))..enabledCats = {'phrasal_verbs'};
    });

    test('expressions of a later sentence are counted inside that sentence', () {
      const text = 'He came home late. She looked up the word in a book.';
      final a = analyze(app, text);
      final ti = a.tokens.indexWhere((t) => t.lower == 'looked');
      final ctx = buildContext(app, Para(1, 0, 'p', text), a, ti);
      expect(ctx.sentence, 'She looked up the word in a book.');
      expect(ctx.sentenceTokens[ctx.indexInSentence].lower, 'looked');
      expect(ctx.prevSentence, 'He came home late.');
      final m = ctx.matches.firstWhere((m) => m.expr.phrase == 'look up');
      expect([for (final i in m.tokens) ctx.sentenceTokens[i].lower], ['looked', 'up']);
    });

    test('the underline and the panel agree on a literal phrasal verb', () {
      for (final text in ['It was late. Dorothy lived in Kansas.', 'It was late. She looked up the word in a book.']) {
        final a = analyze(app, text);
        for (final m in a.matches.where((m) => m.expr.cat == 'phrasal_verbs')) {
          final ti = m.tokens.first;
          final ctx = buildContext(app, Para(1, 0, 'p', text), a, ti);
          final cm = ctx.matches.firstWhere((x) => x.expr == m.expr);
          final r = app.senses.resolve(SenseQuery(
              sentence: ctx.sentence, tokens: ctx.sentenceTokens, index: cm.tokens.first, expr: cm.expr, exprTokens: cm.tokens,
              prevSentence: ctx.prevSentence, nextSentence: ctx.nextSentence));
          final underlined = a.expressionsAt(app, ti).any((x) => x.expr == m.expr);
          expect(underlined, r.literalPhrase == null, reason: '${m.expr.phrase} in "$text"');
        }
      }
    });
  });
}

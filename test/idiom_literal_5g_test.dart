// Task 5G regressions: idiom or word-by-word use, and safe matching.
//
// Every sentence in this file was WRITTEN BY CLAUDE (an AI) for these tests;
// none is corpus data and none was checked by a human annotator. Each case
// stands for a general rule; no rule lists particular idioms.
//
// What is checked:
//  * SenseEngine.literalCues is on by default; off means the 5F engine.
//  * With it on, a prepositional idiom whose determiner or number changed is
//    read word by word ("on the roll" for "on a roll", "for the songs"), and
//    the idiom used in its own form is still shown.
//  * Nothing is made sure by the cues, and a review card is never graded on
//    a cue (panel and card agree).
//  * Sentence boundary, quotes, negation, a proper name, a split phrasal verb,
//    the order of queries.
//  * The experimental wider matcher (possessive "someone's", one inserted
//    modifier) is off by default and finds those forms only when asked.
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/literal_cues.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();

  Match? find(String sentence, String phrase, {bool variants = false}) => d.matcher
      .match(tokenize(sentence), text: sentence, variants: variants)
      .where((m) => m.expr.phrase == phrase)
      .firstOrNull;

  // The reader's path: the expression matched inside one sentence.
  ContextSense? panel(SenseEngine engine, String sentence, String phrase) {
    final toks = tokenize(sentence);
    final m = find(sentence, phrase);
    if (m == null) return null;
    return engine.resolve(SenseQuery(sentence: sentence, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
  }

  bool asIdiom(ContextSense c) => c.cat != null && c.literalPhrase == null && c.shown;

  test('the cues are on by default (switch: SenseEngine.defaultLiteralCues)', () {
    expect(SenseEngine(d).literalCues, isTrue);
  });

  group('prepositional idiom with another determiner or number (cues on)', () {
    // (phrase, word by word: the form changed, as an idiom: its own form)
    const pairs = [
      ('on a roll', 'The baker spread the butter on the roll.', 'After three wins in a row the team is on a roll.'),
      ('for a song', 'She wrote new lyrics for the songs on the album.', 'They bought the old farmhouse for a song.'),
      ('under a cloud', 'We had our picnic under the cloud that hid the sun.', 'He left the company under a cloud.'),
    ];
    for (final (phrase, literal, idiom) in pairs) {
      test('$phrase: "$literal"', () {
        final on = SenseEngine(d, literalCues: true), off = SenseEngine(d, literalCues: false);
        final m = find(literal, phrase);
        expect(m, isNotNull, reason: 'the matcher finds $phrase');
        final cues = literalCuesOf(d, m!.expr, tokenize(literal), m.tokens, literal);
        expect(cues.determiner || cues.number, isTrue, reason: '${cues.toJson()}');
        final c = panel(on, literal, phrase)!;
        expect(asIdiom(c), isFalse, reason: c.reason);
        expect(c.literalPhrase, phrase, reason: c.reason);
        // Off: the 5F engine is unchanged (it shows the idiom, as a guess).
        final b = panel(off, literal, phrase)!;
        expect(asIdiom(b), isTrue, reason: 'premise: the 5F engine shows the idiom here; ${b.reason}');
        expect(b.confidence, isNot(SenseConfidence.sure), reason: b.reason);
        // The card agrees with the panel: nothing to grade.
        final e = m.expr;
        if (e.tr != null) expect(on.fit(phrase, literal, e.tr!).confirmed, isFalse);
      });
      test('$phrase: "$idiom" (own form) is still shown as the idiom', () {
        final on = SenseEngine(d, literalCues: true), off = SenseEngine(d, literalCues: false);
        final c = panel(on, idiom, phrase)!, b = panel(off, idiom, phrase)!;
        expect(literalCuesOf(d, find(idiom, phrase)!.expr, tokenize(idiom), find(idiom, phrase)!.tokens, idiom).determiner, isFalse);
        expect(c.best?.id, b.best?.id, reason: '${c.reason} / ${b.reason}');
        expect(c.confidence, b.confidence);
        expect(asIdiom(c), asIdiom(b));
      });
    }
  });

  test('negation does not change the form: the idiom stays', () {
    const s = 'They did not buy the farmhouse for a song.';
    final on = SenseEngine(d, literalCues: true), off = SenseEngine(d, literalCues: false);
    final c = panel(on, s, 'for a song')!, b = panel(off, s, 'for a song')!;
    expect(c.best?.id, b.best?.id);
    expect(c.literalPhrase, b.literalPhrase);
  });

  test('a verb idiom is not judged by its form (possessives and articles vary in idioms)', () {
    // "stake his claim" is an idiom; the cue is read only for prepositional idioms.
    const s = 'Each new player wanted to break the ice with a joke.';
    final on = SenseEngine(d, literalCues: true), off = SenseEngine(d, literalCues: false);
    final c = panel(on, s, 'break the ice')!, b = panel(off, s, 'break the ice')!;
    expect(c.best?.id, b.best?.id);
    expect(c.confidence, b.confidence);
  });

  test('sentence boundary: an expression is not matched across two sentences', () {
    const s = 'The butter was left on. The roll went cold.';
    expect(find(s, 'on a roll'), isNull);
    expect(find(s, 'on a roll', variants: true), isNull);
    expect(SenseEngine(d, literalCues: true).fit('on a roll', s, 'başarı serisi').confirmed, isFalse);
  });

  test('quotes and "the idiom …": a mention is never sure and grades no card', () {
    for (final s in const [
      'The phrase "spill the beans" is hard to translate.',
      'The idiom spill the beans means to tell a secret.',
    ]) {
      final m = find(s, 'spill the beans');
      expect(m, isNotNull, reason: s);
      expect(literalCuesOf(d, m!.expr, tokenize(s), m.tokens, s).mention, isTrue, reason: s);
      final on = SenseEngine(d, literalCues: true);
      final c = panel(on, s, 'spill the beans')!;
      expect(c.confidence, isNot(SenseConfidence.sure), reason: c.reason);
      expect(on.fit('spill the beans', s, m.expr.tr!).confirmed, isFalse);
    }
  });

  test('a proper name made of the idiom\'s words is never sure and grades no card', () {
    const s = 'We had lunch at a small café called On A Roll near the station.';
    final on = SenseEngine(d, literalCues: true);
    final c = panel(on, s, 'on a roll');
    if (c != null) expect(c.confidence, isNot(SenseConfidence.sure), reason: c.reason);
    expect(on.fit('on a roll', s, 'başarı serisi').confirmed, isFalse);
  });

  test('a split phrasal verb is the same with and without the cues', () {
    const s = 'Look the word up in a dictionary.';
    final m = find(s, 'look up');
    expect(m, isNotNull);
    expect(literalCuesOf(d, m!.expr, tokenize(s), m.tokens, s).toJson().values.any((v) => v), isFalse);
    final c = panel(SenseEngine(d, literalCues: true), s, 'look up')!, b = panel(SenseEngine(d, literalCues: false), s, 'look up')!;
    expect(c.best?.id, b.best?.id);
    expect(c.confidence, b.confidence);
  });

  test('the order of the queries does not change an answer (cues on)', () {
    const a = 'The baker spread the butter on the roll.', b = 'She wrote new lyrics for the songs on the album.';
    final first = panel(SenseEngine(d, literalCues: true), b, 'for a song')!;
    final engine = SenseEngine(d, literalCues: true);
    panel(engine, a, 'on a roll');
    final after = panel(engine, b, 'for a song')!;
    expect(after.best?.id, first.best?.id);
    expect(after.confidence, first.confidence);
    expect(after.literalPhrase, first.literalPhrase);
  });

  test('a cache entry of the cues-off engine is not reused by the cues-on engine', () {
    const s = 'The baker spread the butter on the roll.';
    final toks = tokenize(s);
    final m = find(s, 'on a roll')!;
    final q = SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens);
    expect(SenseEngine(d, literalCues: false).cacheKey(q), isNot(SenseEngine(d, literalCues: true).cacheKey(q)));
  });

  group('experimental wider matching (off by default)', () {
    test('"someone\'s" takes a possessive only when asked', () {
      const s = 'I did not want to burst his bubble so soon.';
      expect(find(s, "burst someone's bubble"), isNull);
      final m = find(s, "burst someone's bubble", variants: true);
      expect(m, isNotNull);
      expect(m!.variant, 'possessive');
      const t = "She did not want to burst Oliver's bubble.";
      expect(find(t, "burst someone's bubble", variants: true)?.variant, 'possessive');
    });

    test('one modifier inside an expression of three or more words, only when asked', () {
      const s = 'The new exhibition runs the whole gamut of modern styles.';
      expect(find(s, 'run the gamut'), isNull);
      expect(find(s, 'run the gamut', variants: true)?.variant, 'insertion');
      // Not two modifiers, and not in a two-word expression.
      expect(find('It runs the whole long gamut.', 'run the gamut', variants: true), isNull);
    });

    test('an ordinary match is the same with or without variants', () {
      const s = 'They bought the old farmhouse for a song.';
      final a = find(s, 'for a song')!, b = find(s, 'for a song', variants: true)!;
      expect(b.tokens, a.tokens);
      expect(b.variant, isNull);
    });
  });
}

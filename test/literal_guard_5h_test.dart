// Task 5H regressions: how an expression read word by word is shown, the
// "cannot tell" state, and the safety of the (still off) wider matcher.
//
// Every sentence in this file was WRITTEN BY CLAUDE (an AI) for these tests;
// none is corpus data and none was checked by a human annotator. The engine's
// answers on them were read off the dictionary as it is; the tests pin the
// rules, not a claim that the sentences are representative.
//
// What is checked:
//  * SenseEngine.literalGuard is on by default; off means the 5G engine.
//  * A matched expression read word by word is never "sure" (it was, on
//    MAGPIE, wrong for about 4 in 5 such "sure" answers); phrasal verbs are
//    judged as before.
//  * When that reading has no Turkish and no form cue says "literal", the
//    panel claims neither reading: SenseGap.idiomOrWords, no meaning, no
//    English definition in the Turkish slot, and no card is graded.
//  * The word panel (resolveTap) gives the same "cannot tell" answer for a
//    word of such an expression, and otherwise what it gave before.
//  * Cache key, query order, apostrophes, sentence boundaries, and that the
//    wider matcher (PhraseMatcher.match variants) never confirms a card.
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();

  Match? find(String sentence, String phrase, {bool variants = false}) => d.matcher
      .match(tokenize(sentence), text: sentence, variants: variants)
      .where((m) => m.expr.phrase == phrase)
      .firstOrNull;

  ContextSense panel(SenseEngine e, String sentence, String phrase) {
    final m = find(sentence, phrase);
    expect(m, isNotNull, reason: '$phrase is found in "$sentence"');
    return e.resolve(SenseQuery(sentence: sentence, tokens: tokenize(sentence), index: m!.tokens.first, expr: m.expr, exprTokens: m.tokens));
  }

  ContextSense tap(SenseEngine e, String sentence, String word) {
    final toks = tokenize(sentence);
    final i = toks.indexWhere((t) => t.lower == word);
    expect(i, greaterThanOrEqualTo(0));
    return e.resolveTap(SenseQuery(sentence: sentence, tokens: toks, index: i), d.matcher.match(toks, text: sentence));
  }

  // The expression's checked Turkish, or the first Turkish of its own senses.
  String trOf(String phrase) {
    final e = d.exprs.firstWhere((x) => x.phrase == phrase);
    if (e.tr != null) return e.tr!;
    final s = 'x $phrase x';
    final m = find(s, phrase)!;
    final c = SenseEngine(d).resolve(SenseQuery(sentence: s, tokens: tokenize(s), index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
    return c.ranked.firstWhere((x) => !x.literal && x.tr.isNotEmpty).tr.first;
  }

  SenseEngine on() => SenseEngine(d, literalGuard: true);
  SenseEngine off() => SenseEngine(d, literalGuard: false);

  test('the guard is on by default (switch: SenseEngine.defaultLiteralGuard)', () {
    expect(SenseEngine(d).literalGuard, isTrue);
    expect(SenseEngine(d).literalCues, isTrue);
  });

  test('a word-by-word reading of an expression is a guess, never sure', () {
    const s = 'Hot air rises and cold air sinks.';
    final before = panel(off(), s, 'hot air');
    expect(before.literalPhrase, 'hot air', reason: 'precondition: read word by word');
    expect(before.confidence, SenseConfidence.sure, reason: 'precondition: the 5G engine calls it sure');
    final after = panel(on(), s, 'hot air');
    expect(after.literalPhrase, 'hot air');
    expect(after.confidence, SenseConfidence.likely);
    expect(after.tr, before.tr, reason: 'the same meaning, only not sure');
    expect(on().fit('hot air', s, trOf('hot air')).confirmed, isFalse);
  });

  group('no Turkish for the word-by-word reading, no form cue: "cannot tell"', () {
    const cases = [
      ('on the run', 'The prisoner was on the run for three weeks.'),
      ('in the offing', 'A change of government is in the offing.'),
      ('in the hole', 'Pour the water back in the hole and press the soil down.'),
      ('on the game', 'Everyone was focused on the game last night.'),
    ];
    for (final (phrase, s) in cases) {
      test('$phrase: "$s"', () {
        final before = panel(off(), s, phrase);
        expect(before.literalPhrase, isNotNull, reason: 'precondition: the 5G engine says "word by word"');
        expect(before.gap, SenseGap.noTurkish, reason: 'precondition: with no Turkish');
        final c = panel(on(), s, phrase);
        expect(c.gap, SenseGap.idiomOrWords);
        expect(c.literalPhrase, isNull, reason: 'no "used word by word" claim');
        expect(c.cat, isNotNull);
        expect(c.shown, isFalse);
        expect(c.tr, isNull);
        expect(c.best, isNull, reason: 'no English definition offered in place of a Turkish meaning');
        final f = on().fit(phrase, s, trOf(phrase));
        expect(f.confirmed, isFalse, reason: 'no card is graded');
      });
    }
  });

  test('the word panel of a word in such an expression says "cannot tell" too', () {
    const s = 'The prisoner was on the run for three weeks.';
    final before = tap(off(), s, 'run');
    expect(before.literalPhrase, isNotNull, reason: 'precondition: 5G gave the empty word-by-word answer');
    final c = tap(on(), s, 'run');
    expect(c.gap, SenseGap.idiomOrWords);
    expect(c.shown, isFalse);
  });

  test('the word panel is unchanged where no expression is in doubt', () {
    for (final (s, w) in const [
      ('The cat slept on the warm blanket.', 'cat'),
      ('Cracks run through the wall.', 'run'),
      ('Dorothy lived in Kansas.', 'lived'),
      ('Hot air rises and cold air sinks.', 'cold'),
    ]) {
      final a = tap(off(), s, w), b = tap(on(), s, w);
      expect(b.best?.id, a.best?.id, reason: s);
      expect(b.tr, a.tr, reason: s);
      expect(b.literalPhrase, a.literalPhrase, reason: s);
    }
  });

  test('phrasal verbs are judged as before', () {
    for (final (s, p) in const [
      ('Dorothy lived in Kansas.', 'live in'),
      ('Cracks run through the wall.', 'run through'),
      ('She looked up at the sky.', 'look up'),
      ('Please look the word up in the dictionary.', 'look up'),
    ]) {
      final m = find(s, p);
      if (m == null) {
        final a = tap(off(), s, s.split(' ').first.toLowerCase()), b = tap(on(), s, s.split(' ').first.toLowerCase());
        expect(b.tr, a.tr, reason: s);
        continue;
      }
      final a = panel(off(), s, p), b = panel(on(), s, p);
      expect(b.confidence, a.confidence, reason: s);
      expect(b.tr, a.tr, reason: s);
      expect(b.literalPhrase, a.literalPhrase, reason: s);
    }
  });

  test('an idiom in its own form is shown as before', () {
    for (final (p, s) in const [
      ('on a roll', 'After three wins in a row the team is on a roll.'),
      ('kick the habit', 'He finally managed to kick the habit last year.'),
      ('hot air', 'His speech was just a lot of hot air.'),
    ]) {
      final a = panel(off(), s, p), b = panel(on(), s, p);
      expect(b.cat, a.cat, reason: s);
      expect(b.tr, a.tr, reason: s);
      expect(b.confidence, a.confidence, reason: s);
    }
  });

  test('a cache entry of the guard-off engine is not reused by the guard-on engine', () {
    const s = 'The prisoner was on the run for three weeks.';
    final m = find(s, 'on the run')!;
    final q = SenseQuery(sentence: s, tokens: tokenize(s), index: m.tokens.first, expr: m.expr, exprTokens: m.tokens);
    expect(on().cacheKey(q), isNot(off().cacheKey(q)));
  });

  test('the order of queries does not change an answer (guard on)', () {
    const a = 'The prisoner was on the run for three weeks.', b = 'Hot air rises and cold air sinks.';
    final e1 = on(), e2 = on();
    final x1 = panel(e1, a, 'on the run'), y1 = panel(e1, b, 'hot air'), t1 = tap(e1, a, 'run');
    final t2 = tap(e2, a, 'run'), y2 = panel(e2, b, 'hot air'), x2 = panel(e2, a, 'on the run');
    expect('$x1 $y1 $t1', '$x2 $y2 $t2');
  });

  test('gap: grammar word, word not in the sentence, a shown meaning', () {
    final e = on();
    const s = 'The bank approved the loan.';
    final toks = tokenize(s);
    expect(e.resolve(SenseQuery(sentence: s, tokens: toks, index: 0)).gap, SenseGap.grammarWord);
    expect(e.resolve(SenseQuery(sentence: s, tokens: toks, index: 99)).gap, SenseGap.notInSentence);
    final bank = e.resolve(SenseQuery(sentence: s, tokens: toks, index: 1));
    expect(bank.shown, isTrue);
    expect(bank.gap, isNull);
  });

  group('matching (the wider matcher stays off)', () {
    test('both apostrophes: "someone\'s" takes "Oliver’s" and "Oliver\'s" only when asked', () {
      for (final s in const ['She did not want to burst Oliver’s bubble.', "She did not want to burst Oliver's bubble."]) {
        expect(find(s, "burst someone's bubble"), isNull, reason: s);
        final m = find(s, "burst someone's bubble", variants: true);
        expect(m, isNotNull, reason: s);
        expect(m!.variant, 'possessive');
      }
    });

    test('a variant match never crosses a sentence boundary', () {
      const s = 'He wanted to burst. His bubble was already gone.';
      expect(find(s, "burst someone's bubble", variants: true), isNull);
    });

    test('a variant match grades no card: the card path uses the ordinary matcher', () {
      const s = 'She did not want to burst his bubble.';
      expect(find(s, "burst someone's bubble", variants: true), isNotNull, reason: 'precondition');
      final f = on().fit("burst someone's bubble", s, trOf("burst someone's bubble"));
      expect(f.confirmed, isFalse);
      expect(f.why, 'not in sentence');
    });

    test('ordinary matches are the same with and without the guard and variants', () {
      for (final s in const [
        'After three wins in a row the team is on a roll.',
        'Please look the word up in the dictionary.',
        'Take care. For now we wait.',
        'He finally managed to kick the habit last year.',
      ]) {
        final toks = tokenize(s);
        final plain = d.matcher.match(toks, text: s).map((m) => '${m.expr.phrase}${m.tokens}').toList();
        final wide = d.matcher.match(toks, text: s, variants: true).where((m) => m.variant == null).map((m) => '${m.expr.phrase}${m.tokens}').toList();
        expect(wide, plain, reason: s);
      }
    });
  });
}

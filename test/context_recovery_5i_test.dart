// Task 5I regressions: recovering an idiom's checked meaning when the
// word-by-word reading that leads by a hair has no Turkish at all, and what
// must NOT change.
//
// Every sentence in this file was WRITTEN BY CLAUDE (an AI) for these tests;
// none is corpus data and none was checked by a human annotator. The tests pin
// the rule (SenseEngine.idiomRecovery), not a claim that the sentences are
// representative. The rule has no phrase list: each case is decided by the
// scores of the candidates the dictionary gives (see the "general" test).
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();

  Match? find(String sentence, String phrase) =>
      d.matcher.match(tokenize(sentence), text: sentence).where((m) => m.expr.phrase == phrase).firstOrNull;

  SenseQuery q(String sentence, String phrase) {
    final m = find(sentence, phrase);
    expect(m, isNotNull, reason: '$phrase is found in "$sentence"');
    return SenseQuery(sentence: sentence, tokens: tokenize(sentence), index: m!.tokens.first, expr: m.expr, exprTokens: m.tokens);
  }

  ContextSense tap(SenseEngine e, String sentence, String word) {
    final toks = tokenize(sentence);
    final i = toks.indexWhere((t) => t.lower == word);
    expect(i, greaterThanOrEqualTo(0));
    return e.resolveTap(SenseQuery(sentence: sentence, tokens: toks, index: i), d.matcher.match(toks, text: sentence));
  }

  SenseEngine on() => SenseEngine(d, idiomRecovery: true);
  SenseEngine off() => SenseEngine(d, idiomRecovery: false);

  test('defaults: recovery on, 5H guard and 5G cues still on, head-word research switch off', () {
    final e = SenseEngine(d);
    expect(e.idiomRecovery, isTrue);
    expect(e.literalGuard, isTrue);
    expect(e.literalCues, isTrue);
    expect(e.headFromPattern, isFalse);
  });

  group('on the run, idiomatic', () {
    const s = 'The prisoner was on the run for three weeks.';
    test('5H said "cannot tell"; 5I shows the checked idiom meaning as a guess', () {
      final before = off().resolve(q(s, 'on the run'));
      expect(before.gap, SenseGap.idiomOrWords, reason: 'precondition: the 5H answer');
      final c = on().resolve(q(s, 'on the run'));
      expect(c.cat, 'prepositional_phrases');
      expect(c.literalPhrase, isNull);
      expect(c.confidence, SenseConfidence.likely, reason: 'never sure');
      expect(c.tr, contains('firarda'));
      expect(c.best!.unverified, isFalse, reason: 'a checked meaning, not an AI draft');
      expect(c.best!.trDerived, isFalse);
      expect(c.gap, isNull);
    });

    test('no card is graded by the guess', () {
      expect(on().fit('on the run', s, 'firarda').confirmed, isFalse);
      // The word card ("run" = koşmak) is judged on the word alone, as before
      // 5I (a known, pre-existing risk: see the 5I report); recovery does not
      // change it.
      expect(on().fit('run', s, 'koşmak').fit, off().fit('run', s, 'koşmak').fit);
    });

    test('the word panel of "run" shows the same guess, not the word\'s own draft meaning', () {
      final t = tap(on(), s, 'run');
      expect(t.cat, 'prepositional_phrases');
      expect(t.tr, contains('firarda'));
      expect(t.confidence, SenseConfidence.likely);
      expect(tap(off(), s, 'run').gap, SenseGap.idiomOrWords, reason: 'precondition: the 5H answer');
    });
  });

  test('the rule is general: it acts only where the leading word-by-word reading has no Turkish', () {
    // For every case where recovery changes the answer, the off-engine's
    // leader was a word-by-word reading with no Turkish, and the new answer is
    // a checked expression meaning within the "close" margin.
    for (final (s, p) in const [
      ('The prisoner was on the run for three weeks.', 'on the run'),
      ('The drinks tonight are on the house.', 'on the house'),
      ('After a long day she decided to hit the sack early.', 'hit the sack'),
      ('Hot air rises and cold air sinks.', 'hot air'),
      ('His speech was just a lot of hot air.', 'hot air'),
      ('Pour the water back in the hole and press the soil down.', 'in the hole'),
      ('Cracks run through the wall.', 'run through'),
    ]) {
      final a = off().resolve(q(s, p)), b = on().resolve(q(s, p));
      if (a.toString() == b.toString()) continue;
      expect(a.ranked.first.literal && a.ranked.first.tr.isEmpty, isTrue, reason: s);
      expect(b.reason, startsWith('idiom recovered'), reason: s);
      expect(b.best!.unverified, isFalse, reason: s);
      expect(a.ranked.first.score - b.best!.score, lessThanOrEqualTo(0.06), reason: s);
    }
  });

  test('an AI-draft idiom meaning is not recovered: "in the hole" still says "cannot tell"', () {
    const s = 'Pour the water back in the hole and press the soil down.';
    final c = on().resolve(q(s, 'in the hole'));
    expect(c.gap, SenseGap.idiomOrWords);
    expect(c.shown, isFalse);
    expect(tap(on(), s, 'hole').gap, SenseGap.idiomOrWords);
  });

  test('hot air, literal: still the word "sıcak" as a guess, never the idiom', () {
    const s = 'Hot air rises and cold air sinks.';
    final c = on().resolve(q(s, 'hot air'));
    expect(c.literalPhrase, 'hot air');
    expect(c.tr, 'sıcak');
    expect(c.confidence, SenseConfidence.likely);
    expect(on().fit('hot air', s, 'boş laf').confirmed, isFalse);
  });

  test('hot air, idiomatic: the idiom as before', () {
    const s = 'His speech was just a lot of hot air.';
    final a = off().resolve(q(s, 'hot air')), b = on().resolve(q(s, 'hot air'));
    expect(b.toString(), a.toString());
    expect(b.tr, contains('boş laf'));
  });

  test('negation, a quoted mention, a short sentence: nothing changes and nothing is sure', () {
    for (final (s, p) in const [
      ('The prisoner was not on the run for long.', 'on the run'),
      ('The phrase "on the run" is in the dictionary.', 'on the run'),
      ('The prisoner was on the run.', 'on the run'),
    ]) {
      final a = off().resolve(q(s, p)), b = on().resolve(q(s, p));
      expect(b.toString(), a.toString(), reason: s);
      expect(b.confidence, isNot(SenseConfidence.sure), reason: s);
    }
  });

  test('a form cue for "literal" wins: no recovery when the determiner changed', () {
    // "on a run" is not the idiom's form; the 5G cue keeps the words.
    const s = 'The prisoner went on a run every morning.';
    final m = find(s, 'on the run');
    if (m == null) return; // not matched at all: nothing to recover
    final b = on().resolve(SenseQuery(sentence: s, tokens: tokenize(s), index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
    expect(b.reason, isNot(startsWith('idiom recovered')));
  });

  test('a sentence boundary is not crossed', () {
    expect(find('He was on. The run was long.', 'on the run'), isNull);
  });

  test('phrasal verbs are judged as before', () {
    for (final (s, p) in const [
      ('Dorothy lived in Kansas.', 'live in'),
      ('Cracks run through the wall.', 'run through'),
      ('She looked up at the sky.', 'look up'),
      ("Let's run through the plan.", 'run through'),
    ]) {
      final m = find(s, p);
      if (m == null) continue;
      expect(on().resolve(q(s, p)).toString(), off().resolve(q(s, p)).toString(), reason: s);
    }
  });

  test('a word with several meanings and no expression is unchanged', () {
    for (final (s, w) in const [
      ('The bank approved the loan.', 'bank'),
      ('They sat on the river bank.', 'bank'),
      ('I know her very well.', 'know'),
    ]) {
      expect(tap(on(), s, w).toString(), tap(off(), s, w).toString(), reason: s);
    }
  });

  test('cache key: on and off are kept apart; the order of queries does not change an answer', () {
    final x = q('The prisoner was on the run for three weeks.', 'on the run');
    expect(on().cacheKey(x), isNot(off().cacheKey(x)));
    const a = 'The prisoner was on the run for three weeks.', b = 'Hot air rises and cold air sinks.';
    final e1 = on(), e2 = on();
    final r1 = '${e1.resolve(q(a, 'on the run'))} ${e1.resolve(q(b, 'hot air'))} ${tap(e1, a, 'run')}';
    final t2 = tap(e2, a, 'run'), h2 = e2.resolve(q(b, 'hot air')), o2 = e2.resolve(q(a, 'on the run'));
    expect(r1, '$o2 $h2 $t2');
  });

  test('head word from the pattern (research switch, off): "in the hole" reads "hole", not "in"', () {
    const s = 'Pour the water back in the hole and press the soil down.';
    final c = SenseEngine(d, headFromPattern: true).resolve(q(s, 'in the hole'));
    expect(c.ranked.where((x) => x.literal).every((x) => x.lemma == 'hole'), isTrue);
    final def = SenseEngine(d).resolve(q(s, 'in the hole'));
    expect(def.ranked.where((x) => x.literal).any((x) => x.lemma == 'in'), isTrue, reason: 'the default keeps the 5H lemma');
  });
}

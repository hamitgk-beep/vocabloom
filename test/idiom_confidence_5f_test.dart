// Task 5F regressions: finding an expression is not proof that it is meant as
// one. An idiom whose words can be read one by one is never "sure", also when
// the dictionary has no Turkish for that word-by-word reading, so a review card
// is never graded on it. Each case stands for a general rule; none of the rules
// lists words.
//
// The three real cases of Task 5E are MAGPIE sentences (BNC text, which is not
// redistributed): they are checked only when MAGPIE_JSONL points at a local
// MAGPIE_unfiltered.jsonl. The sentences written in this file are Claude's
// (an AI), made to show the same rules; they are not corpus data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();

  // The reader's path: the expression matched inside one sentence.
  (ContextSense?, Expr?) panel(SenseEngine engine, String sentence, String phrase) {
    final toks = tokenize(sentence);
    final m = d.matcher.match(toks, text: sentence).where((m) => m.expr.phrase == phrase).firstOrNull;
    if (m == null) return (null, null);
    return (
      engine.resolve(SenseQuery(sentence: sentence, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens)),
      m.expr
    );
  }

  test('order of the queries does not change an answer (a WordNet meaning shared by two words)', () {
    // "draw" and "get" share a WordNet meaning; the reading of the meaning's
    // examples used to be kept for whichever word asked first.
    final s = 'If you walk in the snow without boots, you will get cold feet.';
    final engine = SenseEngine(d);
    // "draw" read word by word inside an expression first.
    expect(panel(engine, 'The umpires drew stumps early because of the rain.', 'draw stumps').$1, isNotNull);
    final (after, _) = panel(engine, s, 'get cold feet');
    // What the query gives on its own, in a fresh process (measured: the
    // idiom meaning as a guess, the word-by-word readings close behind). The
    // profiles are kept for the whole process, so a second engine here would
    // not show the difference.
    expect(after!.cat, isNotNull, reason: after.reason);
    expect(after.literalPhrase, isNull, reason: after.reason);
    expect(after.best?.id, 'ex:get cold feet|idioms#0', reason: after.reason);
    expect(after.confidence, SenseConfidence.likely, reason: after.reason);
  });

  group('an idiom whose word-by-word reading has no Turkish is still never sure', () {
    final engine = SenseEngine(d);
    // (phrase, sentence meant word by word), written for this test.
    const literal = [
      ('poacher turned gamekeeper', 'The poacher turned, gamekeeper close behind him.'),
      ("she'll be right", "Tell her the books are here and she'll be right over."),
      ('circle the wagons', 'By nightfall the drivers were circling the wagons near the river.'),
    ];
    for (final (phrase, s) in literal) {
      test('$phrase: "$s"', () {
        final (c, e) = panel(engine, s, phrase);
        expect(c, isNotNull, reason: 'the matcher should find $phrase');
        // The mechanism of the 5E finding: no word-by-word meaning with Turkish.
        expect(c!.ranked.where((x) => x.literal && x.tr.isNotEmpty), isEmpty, reason: 'test premise');
        expect(c.confidence, isNot(SenseConfidence.sure), reason: c.reason);
        // The review card path agrees with the panel: nothing is graded.
        expect(engine.fit(phrase, s, e!.tr!).confirmed, isFalse, reason: phrase);
      });
    }

    test('the idioms are still found and shown (as a guess) when meant as idioms', () {
      for (final (phrase, s) in const [
        ('poacher turned gamekeeper', 'The former hacker, a poacher turned gamekeeper, now protects the bank.'),
        ("she'll be right", "Don't worry about the car, she'll be right."),
        ('circle the wagons', 'When the scandal broke, the party chose to circle the wagons.'),
      ]) {
        final (c, _) = panel(engine, s, phrase);
        expect(c, isNotNull, reason: phrase);
        expect(c!.cat, isNotNull, reason: c.reason);
        expect(c.shown, isTrue, reason: c.reason);
        expect(c.literalPhrase, isNull, reason: c.reason);
        expect(c.confidence, SenseConfidence.likely, reason: c.reason);
      }
    });
  });

  group('the expression must be complete inside one sentence', () {
    final engine = SenseEngine(d);
    test('a review card\'s stored context of two sentences does not hold the expression', () {
      const s = 'We could not break. The ice was too thick for the boat.';
      final e = d.exprs.firstWhere((x) => x.phrase == 'break the ice');
      final f = engine.fit('break the ice', s, e.tr!);
      expect(f.confirmed, isFalse);
      expect(f.why, 'not in sentence');
      expect(SenseQuery.find(d, s, 'break the ice').expr, isNull);
      // The reader never matched it there either.
      expect(panel(engine, s, 'break the ice').$1, isNull);
    });

    test('part of an idiom is not the idiom', () {
      expect(panel(engine, 'The ice was thin, so nobody went on it.', 'on thin ice').$1, isNull);
      expect(panel(engine, 'Nobody wanted to break anything.', 'break the ice').$1, isNull);
    });
  });

  group('idioms that stay as they were', () {
    final engine = SenseEngine(d);
    test('a real idiom is shown, never sure, never graded', () {
      for (final (phrase, s) in const [
        ('break the ice', 'The host told a joke to break the ice at the start of the meeting.'),
        ('spill the beans', 'Who spilled the beans about the surprise party?'),
        ('kick the bucket', '"I\'m not ready to kick the bucket yet," he laughed.'),
      ]) {
        final (c, e) = panel(engine, s, phrase);
        expect(c, isNotNull, reason: phrase);
        expect(c!.cat, isNotNull, reason: c.reason);
        expect(c.shown, isTrue, reason: c.reason);
        expect(c.confidence, isNot(SenseConfidence.sure), reason: c.reason);
        expect(engine.fit(phrase, s, e!.tr!).confirmed, isFalse, reason: phrase);
      }
    });

    test('phrasal verbs keep their own checks (split and plain)', () {
      final (a, _) = panel(engine, 'She looked up at the sky.', 'look up');
      expect(a!.tr, contains('yukarı bakmak'));
      final (b, _) = panel(engine, 'Please turn the light off.', 'turn off');
      expect(b, isNotNull);
      expect(b!.cat, 'phrasal_verbs');
    });
  });

  // The three sentences of the Task 5E finding, from MAGPIE itself (local only).
  final magpie = Platform.environment['MAGPIE_JSONL'];
  test('Task 5E finding: the three literal MAGPIE sentences are not sure and grade no card', () {
    const ids = {51620: 'poacher turned gamekeeper', 32520: 'circle the wagons', 50299: "she'll be right"};
    final engine = SenseEngine(d);
    var n = 0;
    for (final l in File(magpie!).readAsLinesSync()) {
      final j = jsonDecode(l) as Map<String, dynamic>;
      final idiom = ids[j['id']];
      if (idiom == null) continue;
      expect(j['idiom'], idiom);
      expect(j['label'], 'l');
      expect(j['confidence'], 1.0);
      final s = _detok((j['context'] as List)[2] as String);
      final (c, e) = panel(engine, s, idiom);
      expect(c, isNotNull, reason: s);
      expect(c!.confidence, isNot(SenseConfidence.sure), reason: '$idiom: ${c.reason}');
      expect(engine.fit(idiom, s, e!.tr!).confirmed, isFalse, reason: idiom);
      n++;
    }
    expect(n, 3);
  }, skip: magpie == null ? 'MAGPIE_JSONL not set (BNC text is local only)' : false);
}

/// MAGPIE's tokenized text back to running text (as tools/eval/build_*.py do).
String _detok(String s) {
  var t = s.split(' ').join(' ');
  t = t.replaceAllMapped(RegExp(r" ([,.;:!?%)])"), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r"([(]) "), (m) => m[1]!);
  t = t.replaceAllMapped(RegExp(r" (n't|'s|'re|'ve|'ll|'d|'m)\b"), (m) => m[1]!);
  t = t.replaceAll('`` ', '"').replaceAll(" ''", '"').replaceAll('``', '"').replaceAll("''", '"');
  return t.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).join(' ');
}

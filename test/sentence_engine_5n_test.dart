// Task 5N: the sentence engine with its two small context models (assets/models/*.bin, plain Dart).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/construction.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/cross_encoder.dart';
import 'package:kelime_okur/nlp/sentence_engine.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/nlp/unit_weights_5m.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final expr = CrossEncoder.fromBytes(File('assets/models/expr_context_5n.bin').readAsBytesSync());
  final sense = CrossEncoder.fromBytes(File('assets/models/word_sense_5n.bin').readAsBytesSync());

  for (final (name, model, ref) in [
    ('expression model', expr, 'tools/sentence_engine_5n/data/ref_expr_context_5n.jsonl'),
    ('word-sense model', sense, 'tools/sentence_engine_5n/data/ref_word_sense_5n.jsonl'),
  ]) {
    test('$name: Dart gives the exported Python model\'s token ids and probabilities', () {
      for (final l in File(ref).readAsLinesSync()) {
        final r = jsonDecode(l) as Map<String, dynamic>;
        expect(model.encode(r['a'] as String, r['b'] as String).ids, r['ids']);
        expect(model.probability(r['a'] as String, r['b'] as String), closeTo((r['p'] as num).toDouble(), 0.005));
      }
    });
  }

  test('marked: brackets each piece, cuts six words either side', () {
    const s = 'One two three four five six seven turn the radio off now eight nine ten eleven twelve thirteen.';
    final t = tokenize(s);
    final i = t.indexWhere((x) => x.text == 'turn'), k = t.indexWhere((x) => x.text == 'off');
    expect(SentenceEngine.marked(s, t, [i, k]),
        'two three four five six seven [ turn ] the radio [ off ] now eight nine ten eleven twelve');
  });

  group('breakdown', () {
    late SentenceEngine eng;
    setUpAll(() {
      final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
      d.load();
      eng = SentenceEngine(d, SenseEngine(d), SentenceAnalyzer(d, unitScorer5m), null,
          categories: categories.map((c) => c.id).toSet(), classifier: expr, senseModel: sense);
    });
    List<String> exprs(String s) => [for (final u in eng.analyze(s).units) if (u.isExpression) u.headword];

    test('idiom or literal, decided by the sentence', () {
      expect(exprs('He kicked the bucket last winter.'), contains('kick the bucket'));
      expect(exprs('The boy kicked the bucket across the yard.'), isNot(contains('kick the bucket')));
      expect(exprs('His speech was just hot air.'), contains('hot air'));
      expect(exprs('Hot air rises and cold air sinks.'), isNot(contains('hot air')));
      expect(exprs('He broke the ice with a joke.'), contains('break the ice'));
      expect(exprs('The prisoner was on the run for three weeks.'), contains('on the run'));
    });

    test('every token is in exactly one unit', () {
      final b = eng.analyze('She ran into an old friend at the market.');
      final seen = [for (final u in b.units) ...u.tokens]..sort();
      expect(seen, List.generate(b.tokens.length, (i) => i));
    });

    test('a word meaning chosen by the sentence', () {
      final b = eng.analyze('The car ran into a tree.');
      expect(b.unitAt(1).tr, contains('araba'));
    });
  });
}

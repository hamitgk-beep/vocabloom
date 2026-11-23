// Task 5N: the pure-Dart idiom classifier gives the same token ids and probabilities as the Python model it was
// exported from (export_idiom_cls.py writes REF.jsonl).
//   NLP_5N_MODEL=model.bin NLP_5N_REF=ref.jsonl flutter test tools/sentence_engine_5n/check_cls_5n_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/nlp/cross_encoder.dart';

void main() {
  final model = Platform.environment['NLP_5N_MODEL'];
  final ref = Platform.environment['NLP_5N_REF'];
  if (model == null || ref == null) return;
  test('Dart forward pass = Python', () {
    final c = CrossEncoder.fromBytes(File(model).readAsBytesSync());
    var worst = 0.0;
    final sw = Stopwatch()..start();
    var n = 0;
    for (final l in File(ref).readAsLinesSync()) {
      final r = jsonDecode(l) as Map<String, dynamic>;
      final e = c.encode(r['a'] as String, r['b'] as String);
      expect(e.ids, r['ids'], reason: r['b'] as String);
      final p = c.probability(r['a'] as String, r['b'] as String);
      final d = (p - (r['p'] as num)).abs();
      if (d > worst) worst = d;
      n++;
    }
    stdout.writeln('NLP5N check: $n pairs, worst |p diff| ${worst.toStringAsFixed(5)}, ${(sw.elapsedMilliseconds / n).toStringAsFixed(1)} ms/pair');
    expect(worst, lessThan(0.01));
  });
}

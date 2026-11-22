// Task 5E: the Dart PosTagger gives the same tags as the Python tagger it was trained with (pos_perceptron.py).
//   TAGGER=<ewt_perceptron.json.gz> TAGGER_IN=<one sentence a line, words split by spaces> TAGGER_OUT=<file>
//   flutter test tools/nlp_research/tagger_parity_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/nlp/pos_tagger.dart';

void main() {
  final p = Platform.environment['TAGGER'];
  if (p == null) return;
  test('tag', () {
    final t = PosTagger.load(p)!;
    final sw = Stopwatch()..start();
    final lines = File(Platform.environment['TAGGER_IN']!).readAsLinesSync();
    final out = [for (final l in lines) t.tag(l.split(' ')).join(' ')];
    // ignore: avoid_print
    print('${lines.length} sentences in ${sw.elapsedMilliseconds} ms');
    File(Platform.environment['TAGGER_OUT']!).writeAsStringSync('${out.join('\n')}\n');
  });
}

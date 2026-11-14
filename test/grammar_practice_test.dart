import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';

void main() {
  final topics = parseGrammarTopics(File('assets/grammar/lessons.json').readAsStringSync());

  test('lessons are complete', () {
    expect(topics.length, greaterThanOrEqualTo(20));
    final ids = <String>{};
    for (final t in topics) {
      expect(grammarCategories.keys, contains(t.category), reason: t.id);
      expect(t.explanationTr, isNotEmpty);
      expect(t.structureTr, isNotEmpty);
      expect(t.exercises.length, greaterThanOrEqualTo(5), reason: t.id);
      for (final e in t.exercises) {
        expect(ids.add(e.id), isTrue, reason: 'duplicate ${e.id}');
        expect(e.answers, isNotEmpty);
        expect(e.tr.trim(), isNotEmpty);
      }
    }
  });

  test('answers match regardless of case, punctuation and contractions', () {
    final e = topics.firstWhere((t) => t.id == 'third_conditional').exercises.first;
    expect(matchesReference(e, "if you had made the decision earlier we would not have lost so much time"), isTrue);
    expect(matchesReference(e, "If you’d made the decision earlier, we wouldn't have lost so much time!"), isTrue);
    expect(matchesReference(e, 'If you made the decision earlier, we would not lose so much time.'), isFalse);
    expect(normalizeAnswer("I'm   here. Don't go!"), 'i am here do not go');
  });
}

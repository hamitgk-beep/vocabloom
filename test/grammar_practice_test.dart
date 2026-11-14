import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/data/user_db.dart';

void main() {
  final topics = parseGrammarTopics(File('assets/grammar/lessons.json').readAsStringSync());

  test('lessons are complete', () {
    expect(topics.length, greaterThanOrEqualTo(50));
    final ids = <String>{};
    for (final t in topics) {
      expect(grammarCategories.keys, contains(t.category), reason: t.id);
      expect(t.explanationTr, isNotEmpty);
      expect(t.structureTr, isNotEmpty);
      expect(t.exercises.length, greaterThanOrEqualTo(6), reason: t.id);
      expect(cefrLevels, contains(t.level), reason: t.id);
      expect(t.aliases, isNotEmpty, reason: t.id);
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

  test('every CEFR level has topics', () {
    for (final l in cefrLevels) {
      expect(topics.where((t) => t.level == l), isNotEmpty, reason: l);
    }
    final by = topicsByLevel(topics);
    expect(by.first.level, 'A1');
    expect(by.last.level, 'C2');
  });

  test('the next topic is the lowest unfinished one, started ones first', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_gr'));
    final p = GrammarProgress(u);
    final a1 = topicsByLevel(topics).where((t) => t.level == 'A1').toList();
    expect(nextGrammarTopic(topics, p)!.id, a1.first.id);
    p.markDone(a1[2].id, a1[2].exercises.first.id);
    expect(nextGrammarTopic(topics, p)!.id, a1[2].id);
    for (final t in a1) {
      for (final e in t.exercises) {
        p.markDone(t.id, e.id);
      }
    }
    expect(nextGrammarTopic(topics, p)!.level, 'A2');
    expect(nextGrammarTopic(topics, p, level: 'C1')!.level, 'C1');
  });
}

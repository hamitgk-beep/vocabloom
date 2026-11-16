import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/app_state.dart';
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

  test('every expression group of the reader filters has a lesson', () {
    final linked = {for (final t in topics) if (t.dictCategory != null) t.dictCategory!: t};
    for (final c in categories) {
      expect(linked[c.id], isNotNull, reason: c.id);
    }
    expect(linked.keys.toSet().difference(categoryById.keys.toSet()), isEmpty);
    expect(linked['phrasal_verbs']!.category, 'phrases');
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

  test('every topic has many translations and gap sentences, with English notes', () {
    final en = (jsonDecode(File('assets/grammar/lessons_en.json').readAsStringSync()) as Map)['topics'] as Map;
    for (final t in topics) {
      expect(t.exercises.where((e) => !e.isGap).length, greaterThanOrEqualTo(16), reason: t.id);
      expect(t.exercises.where((e) => e.isGap).length, greaterThanOrEqualTo(12), reason: t.id);
      final notes = (en[t.id] as Map)['notes'] as Map;
      for (final e in t.exercises) {
        expect(notes[e.id], isA<String>(), reason: 'English note of ${e.id}');
        if (e.isGap) {
          expect(GrammarExercise.gapMark.allMatches(e.gap!), hasLength(1), reason: e.id);
          expect(e.gapSolved, isNot(contains(GrammarExercise.gapMark)), reason: e.id);
          expect(matchesReference(e, e.answers.first), isTrue, reason: e.id);
        }
      }
    }
  });

  test('a round is ten sentences, wrong ones first, and a right answer clears them', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_round'));
    final p = GrammarProgress(u);
    final t = topics.firstWhere((t) => t.id == 'present_perfect');
    expect(grammarRound(t, p, random: Random(1)), hasLength(grammarRoundSize));
    final w = t.exercises[5];
    p.record(t.id, w.id, right: false);
    expect(p.wrong(t.id), {w.id});
    expect(p.done(t.id), contains(w.id));
    expect(grammarRound(t, p, random: Random(2)).first, w);
    p.record(t.id, w.id, right: true);
    expect(p.wrong(t.id), isEmpty);
    // Done sentences come after new ones.
    expect(grammarRound(t, p, random: Random(3)), isNot(contains(w)));
    p.record(t.id, t.exercises[1].id, right: false);
    p.reset(t.id);
    expect(p.wrong(t.id), isEmpty);
    expect(p.done(t.id), isEmpty);
  });

  test('a hint shows the answer words in another order, or a gap word letter by letter', () {
    const e = GrammarExercise('x', 'Bunu biliyorum.', ['I know this, really.'], '');
    final h = hintWords(e, random: Random(4));
    expect(h.toSet(), {'I', 'know', 'this', 'really'});
    expect(h.join(' '), isNot('I know this really'));
    const g = GrammarExercise('y', 'O gitti.', ['went'], '', '', 'She ___ home.');
    expect(hintWords(g), ['w…', 'we…', 'wen…']);
    expect(g.gapSolved, 'She went home.');
    expect(matchesReference(g, ' Went '), isTrue);
  });
}

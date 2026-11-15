import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_chat.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';

void main() {
  final topics = parseGrammarTopics(File('assets/grammar/lessons.json').readAsStringSync());
  GrammarIntent? p(String s, {GrammarIntent? last}) => parseGrammarIntent(s, topics, last: last);

  test('every topic in the learner list is there', () {
    const asked = [
      'adverb clause',
      'adverbs of frequency',
      'articles',
      'causative verbs',
      'comparative-superlative',
      'conditionals',
      'conjunctions',
      'countable-uncountable',
      'demonstratives',
      'gerund-infinitives',
      'mixed',
      'modals',
      'neither-either-so-too',
      'noun clause',
      'possessive adjectives-pronouns',
      'preposition',
      'quantifiers',
      'question tag',
      'relative (adjective) clause',
      'reported speech',
      'tenses',
      'there is-there are',
      'time clauses',
      'too-enough',
      'transition words',
      'verb list',
    ];
    for (final a in asked) {
      final i = p('$a anlat');
      expect(i, isNotNull, reason: a);
      expect(i!.mode, GrammarMode.explain, reason: a);
      expect(i.topic != null || i.category != null, isTrue, reason: a);
    }
  });

  test('requests in Turkish and English', () {
    var i = p('Bugün modals çalışalım, bana çeviri cümlesi sor')!;
    expect(i.category, 'modals');
    expect(i.mode, GrammarMode.drill);
    i = p("Modals'ı anlatır mısın?")!;
    expect((i.category, i.mode), ('modals', GrammarMode.explain));
    i = p('bugün modals çalışalım')!;
    expect((i.category, i.mode), ('modals', GrammarMode.study));
    i = p('present perfect continuous anlat')!;
    expect(i.topic!.id, 'present_perfect_continuous');
    i = p('edilgen yapıyı açıkla')!;
    expect(i.topic!.id, 'passive');
    i = p('Quiz me on the passive')!;
    expect((i.topic!.id, i.mode), ('passive', GrammarMode.drill));
    i = p("Let's study relative clauses")!;
    expect((i.topic!.id, i.mode), ('relative_clauses', GrammarMode.study));
    expect(p('hangi gramer konuları var?')!.mode, GrammarMode.list);
    expect(p('cümle sor', last: i)!.topic!.id, 'relative_clauses');
  });

  test('ordinary chat is not taken for a request', () {
    for (final s in [
      'I will study tonight.',
      'Sorry, I must go now.',
      'What are you going to do this weekend?',
      'I used to play football.',
      'I have a test tomorrow.',
      'I practice the piano every day.',
      'Merhaba, nasılsın?',
    ]) {
      expect(p(s), isNull, reason: s);
    }
  });

  test('a drill asks every sentence once, new ones first', () {
    final i = p('modals cümle sor')!;
    final first = topics.firstWhere((t) => t.id == 'obligation').exercises.first.id;
    final d = startDrill(i, topics, done: {first}, count: 1000, random: Random(1));
    expect(d.items.map((x) => x.$2.id).toSet(), hasLength(d.items.length));
    expect(d.items.every((x) => x.$1.category == 'modals'), isTrue);
    expect(d.items.last.$2.id, first);
    // Gap sentences are for the practice page; the chat asks translations.
    expect(d.items.any((x) => x.$2.isGap), isFalse);
    // A sentence answered wrong before comes first, and a drill is ten long.
    final wrong = topics.firstWhere((t) => t.id == 'deduction').exercises.first.id;
    final d2 = startDrill(i, topics, done: {first, wrong}, wrong: {wrong}, random: Random(2));
    expect(d2.items.first.$2.id, wrong);
    expect(d2.items, hasLength(10));
    expect(drillQuestion(d), contains(d.items.first.$2.tr));
    expect(isDrillStop('bitir'), isTrue);
    expect(isDrillSkip('geç'), isTrue);
    expect(isDrillSkip('I went to the shop yesterday.'), isFalse);
  });
}

/// "Gramer pratiği": topic lessons with Turkish sentences to translate.
///
/// Lessons, Turkish sentences and their correct English versions are written
/// in advance and checked (assets/grammar/lessons.json), so they are always
/// right. The on-device model only grades the learner's answer against them.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../data/user_db.dart';
import '../l10n.dart';

class GrammarExercise {
  final String id;

  /// The Turkish sentence to translate.
  final String tr;

  /// Correct English versions; the first is the main one.
  final List<String> answers;

  /// The rule this sentence practises, in Turkish.
  final String noteTr;
  const GrammarExercise(this.id, this.tr, this.answers, this.noteTr);

  factory GrammarExercise.fromJson(Map<String, dynamic> j) => GrammarExercise(
      j['id'] as String, j['tr'] as String, (j['answers'] as List).cast<String>(), (j['note'] ?? '') as String);
}

class GrammarTopic {
  final String id;
  final String titleTr, titleEn;
  final String level;
  final String category;

  /// Markdown: **bold** and "- " bullets.
  final String explanationTr;

  /// Sentence formulas, e.g. "Although + özne + fiil, ana cümle".
  final List<String> structureTr;
  final List<(String, String)> examples;
  final List<GrammarExercise> exercises;
  const GrammarTopic({
    required this.id,
    required this.titleTr,
    required this.titleEn,
    required this.level,
    required this.category,
    required this.explanationTr,
    required this.structureTr,
    required this.examples,
    required this.exercises,
  });

  String get title => uiEnglish ? titleEn : titleTr;

  factory GrammarTopic.fromJson(Map<String, dynamic> j) => GrammarTopic(
        id: j['id'] as String,
        titleTr: j['title_tr'] as String,
        titleEn: j['title_en'] as String,
        level: j['level'] as String,
        category: j['category'] as String,
        explanationTr: j['explanation'] as String,
        structureTr: (j['structure'] as List).cast<String>(),
        examples: [for (final e in j['examples'] as List) ((e as List)[0] as String, e[1] as String)],
        exercises: [for (final e in j['exercises'] as List) GrammarExercise.fromJson(e as Map<String, dynamic>)],
      );
}

/// Category names in display order.
const grammarCategories = <String, (String, String)>{
  'tenses': ('Zamanlar', 'Tenses'),
  'conjunctions': ('Bağlaçlar', 'Conjunctions'),
  'conditionals': ('Koşul cümleleri', 'Conditionals'),
  'modals': ('Kip fiilleri', 'Modal verbs'),
  'passive': ('Edilgen yapı', 'Passive voice'),
  'reported': ('Dolaylı anlatım', 'Reported speech'),
  'clauses': ('Yan cümleler', 'Clauses'),
  'forms': ('Fiil biçimleri', 'Verb forms'),
  'comparison': ('Karşılaştırma', 'Comparison'),
};

List<GrammarTopic>? _cache;

/// The bundled lessons.
Future<List<GrammarTopic>> loadGrammarTopics() async {
  if (_cache != null) return _cache!;
  final raw = await rootBundle.loadString('assets/grammar/lessons.json');
  return _cache = parseGrammarTopics(raw);
}

List<GrammarTopic> parseGrammarTopics(String raw) =>
    [for (final t in (jsonDecode(raw) as Map<String, dynamic>)['topics'] as List) GrammarTopic.fromJson(t as Map<String, dynamic>)];

/// Normalises an English sentence for comparing answers: case, apostrophes,
/// contractions, spaces and punctuation do not matter.
String normalizeAnswer(String s) {
  var t = s.toLowerCase().replaceAll(RegExp('[’‘`´]'), "'").replaceAll(RegExp(r'["“”]'), '');
  const contractions = {
    "won't": 'will not', "can't": 'cannot', "shan't": 'shall not', "n't": ' not', "'re": ' are', "'ve": ' have',
    "'ll": ' will', "'m": ' am', "it's": 'it is', "that's": 'that is', "there's": 'there is',
    "he's": 'he is', "she's": 'she is', "what's": 'what is', "let's": 'let us',
  };
  for (final e in contractions.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  t = t.replaceAll('can not', 'cannot');
  return t.replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// [normalizeAnswer] of [s] with every "'d" read both as "had" and "would".
Set<String> answerVariants(String s) {
  var out = {normalizeAnswer(s)};
  while (out.any((x) => x.contains("'d"))) {
    out = {
      for (final x in out)
        if (x.contains("'d")) ...[x.replaceFirst("'d", ' had'), x.replaceFirst("'d", ' would')] else x
    }.map((x) => x.replaceAll(RegExp(r'\s+'), ' ')).toSet();
  }
  return out;
}

/// Whether [answer] is one of the exercise's correct versions.
bool matchesReference(GrammarExercise e, String answer) {
  final a = answerVariants(answer);
  if (a.every((x) => x.isEmpty)) return false;
  return e.answers.any((r) => answerVariants(r).any(a.contains));
}

/// Done exercises per topic, kept in the user database.
class GrammarProgress {
  final UserDb db;
  GrammarProgress(this.db);
  static const _key = 'grammar_progress';

  Map<String, dynamic> _all() {
    try {
      final s = db.getSetting(_key);
      return s == null ? {} : jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Set<String> done(String topicId) => {...?(_all()[topicId] as List?)?.cast<String>()};

  void markDone(String topicId, String exerciseId) {
    final all = _all();
    final s = done(topicId)..add(exerciseId);
    all[topicId] = s.toList();
    db.setSetting(_key, jsonEncode(all));
  }

  void reset(String topicId) {
    final all = _all()..remove(topicId);
    db.setSetting(_key, jsonEncode(all));
  }
}

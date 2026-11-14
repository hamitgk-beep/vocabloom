/// "Gramer pratiği": topic lessons with Turkish sentences to translate.
///
/// Lessons, Turkish sentences and their correct English versions are written
/// in advance and checked (assets/grammar/lessons.json), so they are always
/// right. The on-device model only grades the learner's answer against them.
library;

import 'dart:convert';
import 'dart:math';

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

  /// Names a learner may use for this topic in the chat, lower case.
  final List<String> aliases;
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
    this.aliases = const [],
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
        aliases: ((j['aliases'] ?? const []) as List).cast<String>(),
      );
}

/// Category names in display order.
const grammarCategories = <String, (String, String)>{
  'tenses': ('Zamanlar', 'Tenses'),
  'nouns': ('İsimler ve belirleyiciler', 'Nouns and determiners'),
  'prepositions': ('Edatlar', 'Prepositions'),
  'sentence': ('Temel cümle kalıpları', 'Sentence patterns'),
  'conjunctions': ('Bağlaçlar ve geçiş sözcükleri', 'Conjunctions and transitions'),
  'conditionals': ('Koşul cümleleri', 'Conditionals'),
  'modals': ('Kip fiilleri', 'Modal verbs'),
  'passive': ('Edilgen yapı', 'Passive voice'),
  'reported': ('Dolaylı anlatım', 'Reported speech'),
  'clauses': ('Yan cümleler', 'Clauses'),
  'forms': ('Fiil biçimleri', 'Verb forms'),
  'comparison': ('Karşılaştırma', 'Comparison'),
  'advanced': ('İleri yapılar', 'Advanced structures'),
  'mixed': ('Karışık tekrar', 'Mixed review'),
};

/// CEFR levels in order.
const cefrLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

/// Topics sorted by CEFR level, keeping the lesson order inside a level.
List<GrammarTopic> topicsByLevel(List<GrammarTopic> topics) {
  final order = {for (final (i, t) in topics.indexed) t.id: i};
  return [...topics]..sort((a, b) {
      final c = cefrLevels.indexOf(a.level).compareTo(cefrLevels.indexOf(b.level));
      return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
    });
}

/// The topic to study next: the first unfinished one at the lowest level,
/// starting from [level] when the learner's level is known. Topics already
/// started come before new ones at the same level.
GrammarTopic? nextGrammarTopic(List<GrammarTopic> topics, GrammarProgress progress, {String? level}) {
  final from = level == null ? 0 : max(0, cefrLevels.indexOf(level));
  final open = [
    for (final t in topicsByLevel(topics))
      if (cefrLevels.indexOf(t.level) >= from && t.category != 'mixed' && progress.done(t.id).length < t.exercises.length) t
  ];
  if (open.isEmpty) return null;
  final lowest = open.first.level;
  return open.firstWhere((t) => t.level == lowest && progress.done(t.id).isNotEmpty, orElse: () => open.first);
}

/// Names a learner may use for a whole category in the chat ("modals çalışalım").
const grammarCategoryAliases = <String, List<String>>{
  'tenses': ['tense', 'tenses', 'zamanlar', 'zamanları', 'fiil zamanları'],
  'nouns': ['nouns', 'determiners', 'isimler', 'belirleyiciler'],
  'prepositions': ['preposition', 'prepositions', 'edat', 'edatlar'],
  'sentence': ['sentence patterns', 'cümle kalıpları'],
  'conjunctions': ['conjunction', 'conjunctions', 'bağlaç', 'bağlaçlar', 'baglac', 'baglaclar'],
  'conditionals': ['conditional', 'conditionals', 'if clause', 'if clauses', 'koşul', 'koşul cümleleri', 'kosul'],
  'modals': ['modal', 'modals', 'modal verbs', 'modal verb', 'kip', 'kipler', 'kip fiilleri'],
  'passive': ['pasif'],
  'reported': ['reported'],
  'clauses': ['clause', 'clauses', 'cümlecik', 'cümlecikler', 'yan cümle', 'yan cümleler'],
  'forms': ['verb forms', 'fiil biçimleri'],
  'comparison': ['comparison', 'comparisons'],
  'advanced': ['advanced structures', 'advanced grammar', 'ileri yapılar', 'ileri gramer'],
  'mixed': [],
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

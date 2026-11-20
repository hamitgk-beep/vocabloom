/// "Gramer pratiği": topic lessons with Turkish sentences to translate.
///
/// Lessons, Turkish sentences and their correct English versions are written
/// in advance and checked (assets/grammar/lessons.json), so they are always
/// right. The on-device model only grades the learner's answer against them.
///
/// Learners of Turkish get Turkish grammar instead (assets/grammar/
/// lessons_tr.json, ids starting with "tr_"): the explanation is in English,
/// [GrammarExercise.tr] holds the English sentence to translate and
/// [GrammarExercise.answers] its Turkish versions.
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

import '../data/stats.dart';
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

  /// The same rule in English, for the English interface (from lessons_en.json).
  final String noteEn;

  /// For a fill-in-the-gap exercise: the English sentence with [gapMark]
  /// where the answer goes ([tr] is then its meaning). Null for a translation.
  final String? gap;
  const GrammarExercise(this.id, this.tr, this.answers, this.noteTr, [this.noteEn = '', this.gap]);

  static const gapMark = '___';

  bool get isGap => gap != null;

  /// The language the answer is written in: 'tr' for the Turkish lessons.
  String get target => grammarTarget(id);

  /// The gap sentence with the main answer filled in.
  String get gapSolved => gap?.replaceFirst(gapMark, answers.first) ?? answers.first;

  /// The rule in the interface language.
  String get note => uiEnglish && noteEn.isNotEmpty ? noteEn : noteTr;

  GrammarExercise withEnglish(String? en) => en == null ? this : GrammarExercise(id, tr, answers, noteTr, en, gap);

  factory GrammarExercise.fromJson(Map<String, dynamic> j) => GrammarExercise(
    j['id'] as String,
    j['tr'] as String,
    (j['answers'] as List).cast<String>(),
    (j['note'] ?? '') as String,
    '',
    j['gap'] as String?,
  );
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

  /// The explanation and patterns in English, for the English interface.
  final String explanationEn;
  final List<String> structureEn;

  /// The dictionary expression group this lesson explains ("phrasal_verbs"),
  /// whose full list the lesson page opens. Null for most lessons.
  final String? dictCategory;
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
    this.explanationEn = '',
    this.structureEn = const [],
    this.dictCategory,
  });

  String get title => uiEnglish ? titleEn : titleTr;

  /// The language the lesson teaches: 'tr' for the Turkish lessons.
  String get target => grammarTarget(id);

  /// The other language's title, shown small under [title] on the Turkish
  /// interface (the English name of the structure is worth learning).
  String? get subtitle => uiEnglish ? null : titleEn;

  String get explanation => uiEnglish && explanationEn.isNotEmpty ? explanationEn : explanationTr;
  List<String> get structure => uiEnglish && structureEn.isNotEmpty ? structureEn : structureTr;

  /// Adds the English texts from lessons_en.json ({"explanation", "structure", "notes": {id: note}}).
  GrammarTopic withEnglish(Map<String, dynamic>? en) {
    if (en == null) return this;
    final notes = (en['notes'] as Map<String, dynamic>?) ?? const {};
    return GrammarTopic(
      id: id,
      titleTr: titleTr,
      titleEn: titleEn,
      level: level,
      category: category,
      explanationTr: explanationTr,
      structureTr: structureTr,
      examples: examples,
      exercises: [for (final e in exercises) e.withEnglish(notes[e.id] as String?)],
      aliases: aliases,
      explanationEn: (en['explanation'] as String?) ?? '',
      structureEn: ((en['structure'] as List?) ?? const []).cast<String>(),
      dictCategory: dictCategory,
    );
  }

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
    dictCategory: j['dict_category'] as String?,
  );
}

/// 'tr' for a Turkish lesson or exercise id, otherwise 'en'.
String grammarTarget(String id) => id.startsWith('tr_') ? 'tr' : 'en';

/// Category names in display order.
const grammarCategories = <String, (String, String)>{
  'tr_sounds': ('Ses uyumu ve "olmak"', 'Vowel harmony and "to be"'),
  'tr_sentence': ('Cümle kuruluşu', 'Building sentences'),
  'tr_cases': ('Hâl ekleri', 'Case endings'),
  'tr_verbs': ('Fiil zamanları', 'Verb tenses'),
  'tr_moods': ('Kipler', 'Moods: can, must, if'),
  'tr_clauses': ('Yan cümleler', 'Clauses'),
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
  'phrases': ('Kalıplar ve sözcük öbekleri', 'Phrases and word combinations'),
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
      if (cefrLevels.indexOf(t.level) >= from && t.category != 'mixed' && progress.done(t.id).length < t.exercises.length) t,
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
  'phrases': ['expressions', 'word combinations', 'kalıplar', 'sözcük öbekleri', 'kelime öbekleri', 'kelime kalıpları'],
  'advanced': ['advanced structures', 'advanced grammar', 'ileri yapılar', 'ileri gramer'],
  'mixed': [],
};

final _cache = <String, List<GrammarTopic>>{};

/// The bundled lessons for learners of [lang]: English grammar for 'en',
/// Turkish grammar for 'tr'.
Future<List<GrammarTopic>> loadGrammarTopics({String lang = 'en'}) async {
  if (lang != 'tr') lang = 'en';
  if (_cache[lang] case final c?) return c;
  if (lang == 'tr') {
    return _cache[lang] = parseGrammarTopics(await rootBundle.loadString('assets/grammar/lessons_tr.json'));
  }
  final raw = await rootBundle.loadString('assets/grammar/lessons.json');
  String? en;
  try {
    en = await rootBundle.loadString('assets/grammar/lessons_en.json');
  } catch (_) {}
  return _cache[lang] = parseGrammarTopics(raw, en);
}

/// The lessons of both languages, for progress pages.
Future<List<GrammarTopic>> loadAllGrammarTopics() async => [
  ...await loadGrammarTopics(),
  ...await loadGrammarTopics(lang: 'tr').catchError((_) => const <GrammarTopic>[]),
];

/// Parses lessons.json; [rawEn] (lessons_en.json) adds the English
/// explanations, patterns and notes by topic and exercise id.
List<GrammarTopic> parseGrammarTopics(String raw, [String? rawEn]) {
  final en = rawEn == null ? const <String, dynamic>{} : (jsonDecode(rawEn) as Map<String, dynamic>)['topics'] as Map<String, dynamic>;
  return [
    for (final t in (jsonDecode(raw) as Map<String, dynamic>)['topics'] as List)
      GrammarTopic.fromJson(t as Map<String, dynamic>).withEnglish(en[t['id']] as Map<String, dynamic>?),
  ];
}

/// Normalises an English sentence for comparing answers: case, apostrophes,
/// contractions, spaces and punctuation do not matter.
String normalizeAnswer(String s) {
  var t = s.toLowerCase().replaceAll(RegExp('[’‘`´]'), "'").replaceAll(RegExp(r'["“”]'), '');
  const contractions = {
    "won't": 'will not',
    "can't": 'cannot',
    "shan't": 'shall not',
    "n't": ' not',
    "'re": ' are',
    "'ve": ' have',
    "'ll": ' will',
    "'m": ' am',
    "it's": 'it is',
    "that's": 'that is',
    "there's": 'there is',
    "he's": 'he is',
    "she's": 'she is',
    "what's": 'what is',
    "let's": 'let us',
  };
  for (final e in contractions.entries) {
    t = t.replaceAll(e.key, e.value);
  }
  t = t.replaceAll('can not', 'cannot');
  return t.replaceAll(RegExp(r"[^a-z0-9' ]+"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Turkish lower case: I -> ı, İ -> i.
String turkishLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Normalises a Turkish sentence for comparing answers: case, punctuation,
/// circumflexes (â, î, û), a question particle written joined ("geliyormusun")
/// and a leading subject pronoun ("Ben geldim" = "Geldim") do not matter.
String normalizeTurkishAnswer(String s) {
  var t = turkishLower(s.replaceAll(RegExp('[’‘`´]'), "'"))
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('û', 'u')
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^\p{L}\p{N} ]+', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // "geliyor musun" and "geliyormusun" are the same answer.
  t = t.replaceAllMapped(RegExp(r' (m[ıiuü](?:y[ıiuü]m|s[ıiuü]n(?:[ıiuü]z)?|y[ıiuü]z|d[ıiuü]r|ydı|ydi|ydu|ydü)?)(?= |$)', unicode: true),
      (m) => m[1]!);
  return t.replaceFirst(RegExp(r'^(ben|sen|o|biz|siz|onlar) (?=\S)'), '');
}

/// [normalizeAnswer] of [s] with every "'d" read both as "had" and "would".
Set<String> answerVariants(String s) {
  var out = {normalizeAnswer(s)};
  while (out.any((x) => x.contains("'d"))) {
    out = {
      for (final x in out)
        if (x.contains("'d")) ...[x.replaceFirst("'d", ' had'), x.replaceFirst("'d", ' would')] else x,
    }.map((x) => x.replaceAll(RegExp(r'\s+'), ' ')).toSet();
  }
  return out;
}

/// Whether [answer] is one of the exercise's correct versions.
bool matchesReference(GrammarExercise e, String answer) {
  if (e.target == 'tr') {
    final a = normalizeTurkishAnswer(answer);
    return a.isNotEmpty && e.answers.any((r) => normalizeTurkishAnswer(r) == a);
  }
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
    final w = _wrongAll()..remove(topicId);
    db.setSetting(_wrongKey, jsonEncode(w));
  }

  // Sentences answered wrong, asked again first in later rounds until right.
  static const _wrongKey = 'grammar_wrong';

  Map<String, dynamic> _wrongAll() {
    try {
      final s = db.getSetting(_wrongKey);
      return s == null ? {} : jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Exercises of [topicId] answered wrong and not yet answered right.
  Set<String> wrong(String topicId) => {...?(_wrongAll()[topicId] as List?)?.cast<String>()};

  /// Records an answer: done either way; a wrong one is asked again later,
  /// a right one is taken off that list.
  void record(String topicId, String exerciseId, {required bool right}) {
    markDone(topicId, exerciseId);
    StatsStore(db).logGrammar(topicId, exerciseId, right);
    final all = _wrongAll();
    final s = wrong(topicId);
    right ? s.remove(exerciseId) : s.add(exerciseId);
    if (s.isEmpty) {
      all.remove(topicId);
    } else {
      all[topicId] = s.toList();
    }
    db.setSetting(_wrongKey, jsonEncode(all));
  }
}

/// Sentences in one scored practice round.
const grammarRoundSize = 10;

/// The next round for [t]: sentences answered wrong before come first, then
/// new ones, then ones already done, up to [size].
List<GrammarExercise> grammarRound(GrammarTopic t, GrammarProgress p, {int size = grammarRoundSize, Random? random}) {
  final rnd = random ?? Random();
  final done = p.done(t.id), wrong = p.wrong(t.id);
  List<GrammarExercise> pick(bool Function(GrammarExercise) f) => t.exercises.where(f).toList()..shuffle(rnd);
  return [
    ...pick((e) => wrong.contains(e.id)),
    ...pick((e) => !done.contains(e.id)),
    ...pick((e) => done.contains(e.id) && !wrong.contains(e.id)),
  ].take(size).toList();
}

final _edgePunct = RegExp(r"^[^\p{L}\p{N}']+|[^\p{L}\p{N}']+$", unicode: true);

/// The words of the main answer in a random order, for the hint button that
/// shows one more word each time it is pressed. A one-word gap answer is
/// shown a letter at a time instead ("w…", "wo…").
List<String> hintWords(GrammarExercise e, {Random? random}) {
  final one = e.answers.first.trim();
  if (e.isGap && !one.contains(' ')) {
    return [for (var i = 1; i < one.length; i++) '${one.substring(0, i)}…'];
  }
  final words = [
    for (final w in e.answers.first.split(RegExp(r'\s+')))
      if (w.replaceAll(_edgePunct, '') case final x when x.isNotEmpty) x,
  ];
  final shuffled = [...words]..shuffle(random ?? Random());
  // Never in the answer's own order when another order exists.
  if (words.toSet().length > 1 && shuffled.join(' ') == words.join(' ')) shuffled.add(shuffled.removeAt(0));
  return shuffled;
}

/// Whether model feedback on a non-matching answer still found mistakes (the
/// grading prompt writes a corrections section only then).
bool feedbackHasCorrections(String feedback) => RegExp(r'Düzeltmeler|Corrections', caseSensitive: false).hasMatch(feedback);

/// Grammar study inside the AI chat: "bugün modals çalışalım", "relative
/// clause anlat", "bana passive cümleleri sor".
///
/// The topic, its explanation and the sentences come from the checked
/// lessons (assets/grammar/lessons.json), so they are always right; the model
/// is only asked to grade a wrong translation.
library;

import 'dart:math';

import '../l10n.dart';
import 'grammar_practice.dart';

enum GrammarMode {
  /// Explain the rule only.
  explain,

  /// Ask translation sentences only.
  drill,

  /// A short explanation, then sentences.
  study,

  /// List the topics there are.
  list,
}

/// What the learner asked for: a topic or a whole category, and a mode.
class GrammarIntent {
  final GrammarTopic? topic;
  final String? category;
  final GrammarMode mode;
  const GrammarIntent(this.mode, {this.topic, this.category});

  @override
  String toString() => 'GrammarIntent($mode, ${topic?.id ?? category})';
}

/// One translation sentence of a drill.
typedef DrillItem = (GrammarTopic, GrammarExercise);

/// A running translation drill in the chat.
class GrammarDrill {
  final String title;
  final List<DrillItem> items;
  int index = 0;
  int right = 0;
  GrammarDrill(this.title, this.items);

  DrillItem get current => items[index];
  bool get finished => index >= items.length;
}

/// What the chat remembers between turns.
class TutorChatSession {
  GrammarDrill? drill;

  /// The last topic or category the learner studied, so that "cümle sor"
  /// alone continues with it.
  GrammarIntent? last;
}

/// Lower case, Turkish letters folded to ASCII, apostrophes ("modals'ı",
/// "let's") and punctuation turned into spaces.
String foldGrammarText(String s) {
  var t = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  const map = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'};
  map.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll(RegExp("['’‘`´]"), ' ');
  return ' ${t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
}

bool _has(String folded, String alias) {
  final a = foldGrammarText(alias).trim();
  if (a.isEmpty) return false;
  if (folded.contains(' $a ')) return true;
  // Turkish suffixes without an apostrophe ("edilgen yapıyı", "modalsi") on
  // longer names.
  return a.length >= 6 && folded.contains(' $a');
}

// Words that turn a topic name into a request. A trailing * matches any
// ending (Turkish suffixes); the rest are whole words, so English chat ("I
// will study tonight", "Sorry, I must go") is not taken for a request.
const _drillWords = [
  'sor', 'sorar', 'sorsana', 'sorabilir*', 'soru*', 'cumle*', 'ceviri*', 'cevir*', 'alistirma*', 'pratik*', 'test*',
  'quiz*', 'sinav*', 'drill', 'exercise*', 'ask me', 'quiz me', 'test me', 'practice with me', 'practise with me',
  'give me sentences', 'translation exercise*'
];
const _explainWords = [
  'anlat*', 'acikla*', 'nedir', 'ne demek', 'ogret*', 'kural*', 'konu anlatimi', 'explain', 'teach me', 'how do i use',
  'how to use', 'when do we use', 'when do i use', 'what is the difference', 'the rule*'
];
const _studyWords = [
  'calis*', 'ogren*', 'tekrar*', "let s study", "let s practice", "let s practise", "let s learn", "let s review",
  'i want to study', 'i want to learn', 'i want to practice', 'i want to practise', 'help me with'
];
const _listWords = ['konular*', 'hangi konu*', 'konu listesi', 'topics', 'which topics', 'what topics'];
const _grammarWords = ['gramer*', 'grammar', 'dilbilgisi*', 'dil bilgisi*'];

const _stopWords = ['bitir*', 'dur', 'durdur', 'yeter', 'bu kadar', 'stop', 'quit', 'cik', 'cikis', 'enough', 'that s enough'];
const _skipWords = [
  'gec', 'pas', 'skip', 'next', 'bilmiyorum', 'cevabi goster', 'cevap ne', 'cevabi ne', 'i don t know', 'i dont know',
  'dont know', 'sonraki', 'show the answer', 'show me the answer'
];

bool _any(String folded, List<String> words) => words.any((w) {
      final prefix = w.endsWith('*');
      final x = foldGrammarText(prefix ? w.substring(0, w.length - 1) : w).trim();
      return folded.contains(prefix ? ' $x' : ' $x ');
    });

/// The grammar request in [text], or null for ordinary chat.
///
/// A topic name alone is not enough: "I must go" is chat, "must anlat" is a
/// request. [last] lets "cümle sor" continue the topic studied before.
GrammarIntent? parseGrammarIntent(String text, List<GrammarTopic> topics, {GrammarIntent? last}) {
  final f = foldGrammarText(text);
  if (f.trim().isEmpty || f.trim().split(' ').length > 25) return null;
  final drill = _any(f, _drillWords), explain = _any(f, _explainWords), study = _any(f, _studyWords);
  final grammar = _any(f, _grammarWords);
  if (_any(f, _listWords) && (grammar || f.contains(' konu'))) return const GrammarIntent(GrammarMode.list);

  // The longest matching name wins: "present perfect continuous" over
  // "present perfect".
  GrammarTopic? topic;
  var best = 0;
  for (final t in topics) {
    for (final a in [t.titleEn.toLowerCase(), ...t.aliases]) {
      final n = foldGrammarText(a).trim().length;
      if (n > best && _has(f, a)) {
        topic = t;
        best = n;
      }
    }
  }
  String? category;
  var bestCat = 0;
  for (final e in grammarCategoryAliases.entries) {
    for (final a in [...e.value, grammarCategories[e.key]!.$2.toLowerCase(), grammarCategories[e.key]!.$1.toLowerCase()]) {
      final n = foldGrammarText(a).trim().length;
      if (n > bestCat && _has(f, a)) {
        category = e.key;
        bestCat = n;
      }
    }
  }
  // A category name that is longer than the topic match ("modals" vs the
  // single word "must") means the whole category.
  if (category != null && bestCat > best) {
    final only = topics.where((t) => t.category == category).toList();
    topic = only.length == 1 ? only.single : null;
  }
  if (topic != null) category = null;

  GrammarMode? mode;
  if (drill && !explain) {
    mode = GrammarMode.drill;
  } else if (explain && !drill && !study) {
    mode = GrammarMode.explain;
  } else if (drill || explain || study) {
    mode = GrammarMode.study;
  }
  if (mode == null) return null;
  if (topic == null && category == null) {
    // "Bana cümle sor" right after a topic was studied.
    if (last != null && (last.topic != null || last.category != null) && (drill || study) && f.trim().split(' ').length <= 8) {
      return GrammarIntent(GrammarMode.drill, topic: last.topic, category: last.category);
    }
    if (grammar && (study || drill || explain)) return const GrammarIntent(GrammarMode.list);
    return null;
  }
  return GrammarIntent(mode, topic: topic, category: category);
}

/// Whether [text], typed during a drill, asks to end it.
bool isDrillStop(String text) {
  final f = foldGrammarText(text);
  return f.trim().split(' ').length <= 4 && _any(f, _stopWords);
}

/// Whether [text], typed during a drill, asks to see the answer and go on.
bool isDrillSkip(String text) {
  final f = foldGrammarText(text);
  return f.trim().split(' ').length <= 5 && _any(f, _skipWords);
}

/// Up to [count] sentences for [intent], those not done yet first.
GrammarDrill startDrill(GrammarIntent intent, List<GrammarTopic> topics, {Set<String> done = const {}, int count = 8, Random? random}) {
  final rnd = random ?? Random();
  final pool = intent.topic != null ? [intent.topic!] : topics.where((t) => t.category == intent.category).toList();
  final items = [for (final t in pool) for (final e in t.exercises) (t, e)]..shuffle(rnd);
  items.sort((a, b) => (done.contains(a.$2.id) ? 1 : 0).compareTo(done.contains(b.$2.id) ? 1 : 0));
  return GrammarDrill(intentTitle(intent), items.take(count).toList());
}

String intentTitle(GrammarIntent i) => i.topic != null
    ? (uiEnglish ? i.topic!.titleEn : i.topic!.titleTr)
    : (uiEnglish ? grammarCategories[i.category]?.$2 : grammarCategories[i.category]?.$1) ?? '';

/// The rule of a topic, written from the lesson.
String topicExplanation(GrammarTopic t, {bool short = false}) {
  final b = StringBuffer('**${t.titleTr}** (${t.titleEn}, ${t.level})\n\n');
  b.writeln(t.explanationTr.trim());
  b.writeln(L('\n**Yapı:**', '\n**Structure:**'));
  for (final s in t.structureTr) {
    b.writeln('- $s');
  }
  if (!short && t.examples.isNotEmpty) {
    b.writeln(L('\n**Örnekler:**', '\n**Examples:**'));
    for (final (en, tr) in t.examples) {
      b.writeln('- $en ($tr)');
    }
  }
  return b.toString().trim();
}

/// A whole category: each topic with its sentence patterns.
String categoryOverview(String category, List<GrammarTopic> topics) {
  final ts = topics.where((t) => t.category == category).toList();
  final c = grammarCategories[category]!;
  final b = StringBuffer(L('**${c.$1}** konusunda ${ts.length} ders var:\n\n', '**${c.$2}** has ${ts.length} lessons:\n\n'));
  for (final t in ts) {
    b.writeln('**${t.titleTr}** (${t.level})');
    for (final s in t.structureTr) {
      b.writeln('- $s');
    }
    b.writeln();
  }
  final ex = ts.isEmpty ? '' : ts.first.titleEn;
  b.write(L('Birini ayrıntılı anlatmamı istersen adını yaz (ör. "$ex anlat").', 'To learn one in detail, write its name (e.g. "Explain $ex").'));
  return b.toString().trim();
}

/// Every category with its topics.
String topicList(List<GrammarTopic> topics) {
  final b = StringBuffer(L('Çalışabileceğimiz gramer konuları:\n\n', 'Grammar topics we can study:\n\n'));
  for (final c in grammarCategories.entries) {
    final ts = topics.where((t) => t.category == c.key).toList();
    if (ts.isEmpty) continue;
    b.writeln('**${uiEnglish ? c.value.$2 : c.value.$1}:** ${ts.map((t) => t.titleEn).join(', ')}');
  }
  b.write(L('\nÖrneğin "Bugün modals çalışalım", "Relative clause anlat" ya da "Bana passive cümleleri sor" yazabilirsin.',
      '\nFor example, write "Let\'s study modals", "Explain relative clauses" or "Quiz me on the passive".'));
  return b.toString().trim();
}

/// The question for the current sentence of [d].
String drillQuestion(GrammarDrill d) {
  final (t, e) = d.current;
  return '**${d.index + 1}/${d.items.length} · ${t.titleEn}**\n'
      '${L('Şu cümleyi İngilizceye çevir:', 'Translate this sentence into English:')}\n'
      '**"${e.tr}"**';
}

String get drillHelp => L('Cevabı görmek için "geç", bitirmek için "bitir" yazabilirsin.', 'Write "skip" to see the answer or "stop" to finish.');

/// The closing line of a finished drill.
String drillSummary(GrammarDrill d) {
  final n = d.index.clamp(0, d.items.length);
  final b = StringBuffer(L('**Alıştırma bitti:** $n cümleden ${d.right} tanesi ilk denemede doğru.',
      '**Practice finished:** ${d.right} of $n sentences right at the first try.'));
  if (n > 0 && d.right == n) {
    b.write(L(' Mükemmel! 🎉', ' Perfect! 🎉'));
  } else if (n > 0 && d.right * 2 >= n) {
    b.write(L(' Çok iyi gidiyorsun.', ' You are doing very well.'));
  }
  b.write(L('\nDevam etmek için "cümle sor", başka bir konu için ör. "Bugün tenses çalışalım" yaz.',
      '\nWrite "quiz me" to go on, or e.g. "Let\'s study tenses" for another topic.'));
  return b.toString();
}

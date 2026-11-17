import 'package:flutter/material.dart';

import 'data/dict_db.dart';
import 'data/review.dart';
import 'data/user_db.dart';
import 'ai/local_ai.dart';
import 'nlp/grammar.dart';
import 'nlp/grammar_marks.dart';
import 'online/auto_analyzer.dart';
import 'nlp/text.dart';
import 'l10n.dart';

class CategoryInfo {
  final String id;
  final String name;
  final String tr;
  final Color color;
  final String description;
  final String descriptionEn;
  const CategoryInfo(this.id, this.name, this.tr, this.color, this.description, this.descriptionEn);

  /// Description in the interface language.
  String get desc => uiEnglish ? descriptionEn : description;
}

const categories = <CategoryInfo>[
  CategoryInfo(
    'conjunctions',
    'Conjunctions',
    'Bağlaçlar',
    Color(0xFF1E88E5),
    'Cümleleri ve öğeleri bağlayan sözcükler (and, although, unless).',
    'Words that join sentences and parts of sentences (and, although, unless).',
  ),
  CategoryInfo(
    'phrasal_verbs',
    'Phrasal Verbs',
    'Öbek fiiller',
    Color(0xFF8E24AA),
    'Fiil + edat/zarf; anlamı çoğu zaman tek tek kelimelerden farklıdır (give up).',
    'Verb + preposition/adverb; the meaning often differs from the single words (give up).',
  ),
  CategoryInfo(
    'collocations',
    'Collocations',
    'Eşdizimler',
    Color(0xFF00897B),
    'Doğal olarak birlikte kullanılan kelimeler (make a decision, heavy rain).',
    'Words that naturally go together (make a decision, heavy rain).',
  ),
  CategoryInfo(
    'prepositional_phrases',
    'Prepositional Phrases',
    'Edatlı öbekler',
    Color(0xFF6D4C41),
    'Edatla başlayan kalıplar (at last, in charge of).',
    'Expressions that start with a preposition (at last, in charge of).',
  ),
  CategoryInfo('proverbs', 'Proverbs & Sayings', 'Atasözleri ve deyişler', Color(0xFFD81B60), 'Kalıplaşmış öğütler ve sözler.', 'Fixed pieces of advice and sayings.'),
  CategoryInfo(
    'discourse_markers',
    'Discourse Markers / Fillers',
    'Söylem belirleyiciler / dolgu',
    Color(0xFF00ACC1),
    'Konuşmayı ve metni yönlendiren ifadeler (however, by the way, well).',
    'Expressions that guide speech and text (however, by the way).',
  ),
  CategoryInfo('idioms', 'Idioms', 'Deyimler', Color(0xFFE53935), 'Mecazi anlamlı kalıplar (break the ice).', 'Expressions with a figurative meaning (break the ice).'),
  CategoryInfo(
    'chunks',
    'Chunks',
    'Kalıp ifadeler',
    Color(0xFF3949AB),
    'Bütün olarak öğrenilen hazır ifadeler (it depends, no wonder).',
    'Ready-made expressions learned as a whole (it depends, no wonder).',
  ),
  CategoryInfo('binomials', 'Binomials', 'İkili kalıplar', Color(0xFF546E7A), 'Sabit sıralı kelime çiftleri (safe and sound).', 'Word pairs in a fixed order (safe and sound).'),
  CategoryInfo(
    'false_friends',
    'False Friends',
    'Yalancı eşdeğerler',
    Color(0xFF9E9D24),
    'Türkçedeki bir kelimeye benzeyip başka anlama gelenler (sympathetic).',
    'Words that look like a Turkish word but mean something else (sympathetic).',
  ),
  CategoryInfo('modal_verbs', 'Modal Verbs', 'Kip fiilleri', Color(0xFF0D47A1), 'Yetenek, olasılık, zorunluluk bildiren yardımcı fiiller.', 'Helping verbs for ability, possibility and obligation.'),
  CategoryInfo(
    'irregular_verbs',
    'Irregular Verbs',
    'Düzensiz fiiller',
    Color(0xFFAA00FF),
    'V2/V3 biçimleri kurala uymayan fiiller (go-went-gone).',
    'Verbs whose V2/V3 forms do not follow the rule (go-went-gone).',
  ),
];

/// Grammar highlights in the Filters menu (see nlp/grammar_marks.dart). They
/// are found by rules on each sentence, not looked up in the dictionary.
const grammarFilters = <CategoryInfo>[
  CategoryInfo(
    'g_tenses',
    'Tenses',
    'Zamanlar',
    Color(0xFF2E7D32),
    'Her fiil zamanına göre renklenir: yeşil şimdiki/geniş, kahverengi geçmiş, mavi gelecek. Dokununca zamanın adı ve kuralı çıkar.',
    'Each verb is coloured by its tense: green present, brown past, blue future. Tap it to see the name and the rule.',
  ),
  CategoryInfo(
    'g_passive',
    'Passive Voice',
    'Edilgen çatı',
    Color(0xFF00695C),
    'is done, was built, can be found: özne işi yapan değil, işten etkilenen. Varsa işi yapan ("by …") da gösterilir.',
    'is done, was built, can be found: the subject receives the action. The doer ("by …") is shown when the sentence names it.',
  ),
  CategoryInfo(
    'g_conditionals',
    'Conditionals',
    'Koşul cümleleri',
    Color(0xFFC2185B),
    '"if / unless" ile kurulan cümleler ve türleri (0, 1, 2, 3. tip, karışık).',
    'Sentences with "if / unless" and their type (zero, first, second, third, mixed).',
  ),
  CategoryInfo(
    'g_relative',
    'Relative Clauses',
    'Sıfat cümlecikleri',
    Color(0xFF5E35B1),
    'who, which, that, whose, where ile başlayıp bir ismi niteleyen yan cümleler.',
    'Clauses with who, which, that, whose or where that describe a noun.',
  ),
  CategoryInfo(
    'g_gerund_inf',
    'Gerund / Infinitive',
    'V-ing / to V1',
    Color(0xFF0277BD),
    'enjoy reading, want to read, before leaving: fiilden sonra -ing mi to mu geldiğini gösterir.',
    'enjoy reading, want to read, before leaving: whether a verb is followed by -ing or to.',
  ),
  CategoryInfo(
    'g_comparison',
    'Comparative / Superlative',
    'Karşılaştırma / üstünlük',
    Color(0xFFD84315),
    'bigger than, more beautiful, the best, as tall as gibi karşılaştırma kalıpları.',
    'Comparisons such as bigger than, more beautiful, the best, as tall as.',
  ),
  CategoryInfo(
    'g_reported',
    'Reported Speech',
    'Dolaylı anlatım',
    Color(0xFF6A1B9A),
    'he said that …, she asked if …, told him to …: tırnaksız aktarılan sözler ve sorular.',
    'he said that …, she asked if …, told him to …: words and questions reported without quotation marks.',
  ),
  CategoryInfo(
    'g_past_modals',
    'Past Modals',
    'Geçmişe yönelik kipler',
    Color(0xFF1A237E),
    'should / could / must / might have + V3: pişmanlık, eleştiri ve geçmiş hakkında tahmin.',
    'should / could / must / might have + V3: regret, criticism and guesses about the past.',
  ),
  CategoryInfo(
    'g_used_to',
    'Used to / Be used to',
    'used to / be used to',
    Color(0xFF827717),
    'used to + V1 (eskiden yapardı), be / get used to + V-ing (alışkın olmak / alışmak), be used to + V1 (-mek için kullanılmak).',
    'used to + V1 (a past habit), be / get used to + V-ing (be / become accustomed), be used to + V1 (be used for).',
  ),
  CategoryInfo(
    'g_causative',
    'Causatives',
    'Ettirgen yapılar',
    Color(0xFFBF360C),
    'have something done, get someone to do, make someone do: işi başkasına yaptırmak.',
    'have something done, get someone to do, make someone do: getting someone else to do it.',
  ),
  CategoryInfo(
    'g_emphasis',
    'Inversion & Cleft',
    'Devrik ve vurgu cümleleri',
    Color(0xFFAD1457),
    'Never have I seen …, Not only did he …, It was John who …, What I need is …: vurgu için değişen söz dizimi.',
    'Never have I seen …, Not only did he …, It was John who …, What I need is …: word order changed for emphasis.',
  ),
  CategoryInfo(
    'g_tags',
    'Question Tags',
    'Onay soruları',
    Color(0xFF37474F),
    "…, isn't it?  …, didn't they?: cümle sonundaki \"değil mi?\" soruları.",
    "…, isn't it?  …, didn't they?: short \"right?\" questions at the end of a sentence.",
  ),
  CategoryInfo(
    'g_participles',
    'Participles',
    'Ortaçlar (-ing / -ed)',
    Color(0xFF4E342E),
    'Fiilin -ing / -ed hali: Walking home, I … (eve yürürken), Having finished, … (bitirince), the man standing there (orada duran adam), bored / boring (sıkılmış / sıkıcı).',
    'Walking home, I …; Having finished, …; a letter written by him; the man standing there; bored / boring.',
  ),
];

/// The Filters menu in three groups; the colour priority still follows [allCategories].
const filterGroups = <(String, String, List<String>)>[
  ('Kalıplar ve deyimler', 'Phrases & idioms', ['phrasal_verbs', 'idioms', 'collocations', 'chunks', 'binomials', 'prepositional_phrases', 'proverbs', 'conjunctions', 'discourse_markers']),
  (
    'Gramer yapıları',
    'Grammar structures',
    [
      'g_tenses',
      'g_passive',
      'modal_verbs',
      'g_past_modals',
      'g_conditionals',
      'g_relative',
      'g_participles',
      'g_gerund_inf',
      'g_comparison',
      'g_reported',
      'g_used_to',
      'g_causative',
      'g_emphasis',
      'g_tags',
    ],
  ),
  ('Kelime türleri', 'Word types', ['false_friends', 'irregular_verbs']),
];

/// Colours of the tenses filter: present, past, future.
const tenseToneColors = [Color(0xFF2E7D32), Color(0xFF9A5B13), Color(0xFF1565C0)];

/// Every highlight type: expressions first, then grammar.
const allCategories = [...categories, ...grammarFilters];

final categoryById = {for (final c in allCategories) c.id: c};

const learningColor = Color(0xFFFF9800);
const learnedColor = Color(0xFF43A047);

/// App-wide state: databases and the reader preferences.
class AppState extends ChangeNotifier {
  final DictDb dict;
  final UserDb user;
  late final TenseDetector tenses;

  /// Grammar highlights in the reader (tenses, conditionals …).
  late final GrammarMarker grammar;
  Set<String> enabledCats = {};
  bool showTr = true;
  bool showEn = true;
  double fontSize = 19;

  /// Reader page in day mode: 'white' or 'sepia'.
  String paper = 'white';
  double lineHeight = 1.6;
  ThemeMode themeMode = ThemeMode.light;
  int _wordsVersion = 0;
  late final AutoAnalyzer analyzer = AutoAnalyzer(user, dict);
  late final ReviewStore review = ReviewStore(user);

  /// Offline AI tutor ("Yapay Zekâ" section). Set in main() before the UI starts.
  late final LocalAi localAi;

  AppState(this.dict, this.user) {
    final past = <String>{}, pp = <String>{};
    for (final r in dict.db.select("SELECT forms FROM expr WHERE cat='irregular_verbs'")) {
      final f = (r['forms'] as String).replaceAll(RegExp(r'[\[\]"]'), '').split(',');
      if (f.length >= 3) {
        past.addAll(f.sublist(1, f.length - 1));
        pp.add(f.last);
      }
    }
    for (final r in dict.db.select("SELECT form FROM exc WHERE pos='v'")) {
      final f = r['form'] as String;
      if (!f.endsWith('s')) {
        past.add(f);
        pp.add(f);
      }
    }
    tenses = TenseDetector(dict.lemmatizer, past, pp);
    // Only the curated irregular verb list: WordNet's exception list also has
    // rare forms such as "red" (rid) that would turn adjectives into verbs.
    final gPast = <String>{}, gPP = <String>{};
    for (final f in dict.irregular.values) {
      gPast.addAll(f.sublist(1, f.length - 1));
      gPP.add(f.last);
    }
    grammar = GrammarMarker(lemmas: dict.lemmatizer.lemmas, posOfLemma: dict.lemmaPos, pastForms: gPast, participles: gPP);
    final ai = user.exprAi();
    if (ai.isNotEmpty) {
      for (final e in dict.exprs) {
        final t = ai['${e.phrase}|${e.cat}'];
        if (t != null) {
          e.aiTr = t.$1;
          e.aiExp = t.$2;
        }
      }
    }
    final s = user.getJson('prefs');
    enabledCats = ((s['cats'] as List?) ?? const []).cast<String>().toSet();
    showTr = s['tr'] as bool? ?? true;
    showEn = s['en'] as bool? ?? true;
    fontSize = (s['font'] as num?)?.toDouble() ?? 19;
    paper = s['paper'] as String? ?? 'white';
    lineHeight = (s['lh'] as num?)?.toDouble() ?? 1.6;
    themeMode = ThemeMode.values.firstWhere((m) => m.name == s['theme'], orElse: () => ThemeMode.light);
    uiEnglish = s['ui'] == 'en';
  }

  bool get englishUi => uiEnglish;

  void setUiEnglish(bool v) {
    uiEnglish = v;
    _save();
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _save();
    notifyListeners();
  }

  int get wordsVersion => _wordsVersion;

  void _save() =>
      user.setJson('prefs', {'cats': enabledCats.toList(), 'tr': showTr, 'en': showEn, 'font': fontSize, 'theme': themeMode.name, 'ui': uiEnglish ? 'en' : 'tr', 'paper': paper, 'lh': lineHeight});

  void toggleCat(String id) {
    enabledCats.contains(id) ? enabledCats.remove(id) : enabledCats.add(id);
    _save();
    notifyListeners();
  }

  void setAllCats(bool on) {
    enabledCats = on ? allCategories.map((c) => c.id).toSet() : {};
    _save();
    notifyListeners();
  }

  /// Turns a group of filters on or off.
  void setCats(Iterable<String> ids, bool on) {
    on ? enabledCats.addAll(ids) : enabledCats.removeAll(ids);
    _save();
    notifyListeners();
  }

  void setLang({bool? tr, bool? en}) {
    showTr = tr ?? showTr;
    showEn = en ?? showEn;
    if (!showTr && !showEn) showTr = true;
    _save();
    notifyListeners();
  }

  void setReading({String? paper, double? lineHeight}) {
    this.paper = paper ?? this.paper;
    this.lineHeight = lineHeight ?? this.lineHeight;
    _save();
    notifyListeners();
  }

  void setFont(double v) {
    fontSize = v;
    _save();
    notifyListeners();
  }

  void setWord(String key, WordStatus st, {String? context, String? book, String? meaning}) {
    user.setWord(key, st, context: context, book: book, meaning: meaning);
    _wordsVersion++;
    notifyListeners();
  }

  /// Status of a token, looking at all its base-form candidates.
  WordStatus statusOf(Token t) {
    if (user.statuses.isEmpty) return WordStatus.none;
    var st = WordStatus.none;
    for (final l in dict.lemmatizer.lemmas(t.lower)) {
      final s = user.statuses[l];
      if (s == WordStatus.learning) return s!;
      if (s == WordStatus.learned) st = s!;
    }
    return st;
  }

  String primaryLemma(String lower) => dict.lemmatizer.lemmas(lower).first;

  /// Whether [w] is an English word the dictionary knows (used to clean OCR).
  bool isWord(String w) {
    final l = w.toLowerCase().replaceAll('’', "'");
    return dict.lemmatizer.lemmas(l).any(dict.lemmatizer.known.contains);
  }

  /// Short Turkish meaning used in lists.
  String? shortMeaning(String lemma) {
    final info = dict.lookup(lemma);
    if (info.trFreeDict.isNotEmpty) return info.trFreeDict.first;
    for (final s in info.senses) {
      if (s.tr.isNotEmpty) return s.tr.take(3).join(', ');
    }
    return info.senses.isNotEmpty ? info.senses.first.gloss : null;
  }
}

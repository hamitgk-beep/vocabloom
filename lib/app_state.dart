import 'package:flutter/material.dart';

import 'data/dict_db.dart';
import 'data/user_db.dart';
import 'nlp/grammar.dart';
import 'online/auto_analyzer.dart';
import 'nlp/text.dart';

class CategoryInfo {
  final String id;
  final String name;
  final String tr;
  final Color color;
  final String description;
  const CategoryInfo(this.id, this.name, this.tr, this.color, this.description);
}

const categories = <CategoryInfo>[
  CategoryInfo('conjunctions', 'Conjunctions', 'Bağlaçlar', Color(0xFF1E88E5), 'Cümleleri ve öğeleri bağlayan sözcükler (and, although, unless).'),
  CategoryInfo('phrasal_verbs', 'Phrasal Verbs', 'Öbek fiiller', Color(0xFF8E24AA), 'Fiil + edat/zarf; anlamı çoğu zaman tek tek kelimelerden farklıdır (give up).'),
  CategoryInfo('collocations', 'Collocations', 'Eşdizimler', Color(0xFF00897B), 'Doğal olarak birlikte kullanılan kelimeler (make a decision, heavy rain).'),
  CategoryInfo('prepositional_phrases', 'Prepositional Phrases', 'Edatlı öbekler', Color(0xFF6D4C41), 'Edatla başlayan kalıplar (at last, in charge of).'),
  CategoryInfo('proverbs', 'Proverbs & Sayings', 'Atasözleri ve deyişler', Color(0xFFD81B60), 'Kalıplaşmış öğütler ve sözler.'),
  CategoryInfo('discourse_markers', 'Discourse Markers / Fillers', 'Söylem belirleyiciler / dolgu', Color(0xFF00ACC1), 'Konuşmayı ve metni yönlendiren ifadeler (however, by the way, well).'),
  CategoryInfo('idioms', 'Idioms', 'Deyimler', Color(0xFFE53935), 'Mecazi anlamlı kalıplar (break the ice).'),
  CategoryInfo('chunks', 'Chunks', 'Kalıp ifadeler', Color(0xFF3949AB), 'Bütün olarak öğrenilen hazır ifadeler (it depends, no wonder).'),
  CategoryInfo('binomials', 'Binomials', 'İkili kalıplar', Color(0xFF546E7A), 'Sabit sıralı kelime çiftleri (safe and sound).'),
  CategoryInfo('false_friends', 'False Friends', 'Yalancı eşdeğerler', Color(0xFF9E9D24), 'Türkçedeki bir kelimeye benzeyip başka anlama gelenler (sympathetic).'),
  CategoryInfo('modal_verbs', 'Modal Verbs', 'Kip fiilleri', Color(0xFF0D47A1), 'Yetenek, olasılık, zorunluluk bildiren yardımcı fiiller.'),
  CategoryInfo('irregular_verbs', 'Irregular Verbs', 'Düzensiz fiiller', Color(0xFFAA00FF), 'V2/V3 biçimleri kurala uymayan fiiller (go-went-gone).'),
];

final categoryById = {for (final c in categories) c.id: c};

const learningColor = Color(0xFFFF9800);
const learnedColor = Color(0xFF43A047);

/// App-wide state: databases and the reader preferences.
class AppState extends ChangeNotifier {
  final DictDb dict;
  final UserDb user;
  late final TenseDetector tenses;
  Set<String> enabledCats = {};
  bool showTr = true;
  bool showEn = true;
  double fontSize = 19;
  ThemeMode themeMode = ThemeMode.light;
  int _wordsVersion = 0;
  late final AutoAnalyzer analyzer = AutoAnalyzer(user);

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
    final s = user.getJson('prefs');
    enabledCats = ((s['cats'] as List?) ?? const []).cast<String>().toSet();
    showTr = s['tr'] as bool? ?? true;
    showEn = s['en'] as bool? ?? true;
    fontSize = (s['font'] as num?)?.toDouble() ?? 19;
    themeMode = ThemeMode.values.firstWhere((m) => m.name == s['theme'], orElse: () => ThemeMode.light);
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _save();
    notifyListeners();
  }

  int get wordsVersion => _wordsVersion;

  void _save() => user.setJson('prefs', {'cats': enabledCats.toList(), 'tr': showTr, 'en': showEn, 'font': fontSize, 'theme': themeMode.name});

  void toggleCat(String id) {
    enabledCats.contains(id) ? enabledCats.remove(id) : enabledCats.add(id);
    _save();
    notifyListeners();
  }

  void setAllCats(bool on) {
    enabledCats = on ? categories.map((c) => c.id).toSet() : {};
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

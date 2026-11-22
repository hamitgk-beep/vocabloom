import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Turkish word -> English meanings, for English speakers who read Turkish
/// books. Built by tools/tr_en/build_tr_en.py from open data only:
/// Kaikki.org / English Wiktionary (CC BY-SA 4.0), FrequencyWords (CC BY-SA
/// 4.0, ranking only) and Tatoeba sentence pairs (CC BY 2.0 FR).
class TrEnDict {
  // Bump when assets/tr_en.db changes, so devices copy the new one.
  static const _version = '10';
  final Database db;
  TrEnDict(this.db);

  static Future<TrEnDict?> open(Directory dir) async {
    final file = File(p.join(dir.path, 'tr_en_v$_version.db'));
    for (final f in dir.listSync().whereType<File>()) {
      final n = p.basename(f.path);
      if (n.startsWith('tr_en_v') && n.endsWith('.db') && f.path != file.path) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    try {
      if (!file.existsSync() || file.lengthSync() < 100000) {
        final data = await rootBundle.load('assets/tr_en.db');
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
      return TrEnDict(sqlite3.open(file.path, mode: OpenMode.readOnly));
    } catch (_) {
      return null;
    }
  }

  /// Turkish lower case: "I" is "ı" and "İ" is "i".
  static String lower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase().replaceAll('̇', '').replaceAll('’', "'");

  bool _has(String w) => db.select('SELECT 1 FROM lemma WHERE word=?', [w]).isNotEmpty;

  /// Base words a tapped word can belong to, the most likely first:
  /// the word itself, then the dictionary's inflected forms (evlerimizden ->
  /// ev), then a few endings the tables do not list ("seninle", "Ankara'da").
  List<String> lemmas(String surface) => lemmasWithGuess(surface).$1;

  /// Whether [lemmas] found [surface]'s base word only by cutting endings
  /// that the dictionary does not list for it: a guess, to be shown as one.
  bool isGuess(String surface) => lemmasWithGuess(surface).$2;

  (List<String>, bool) lemmasWithGuess(String surface) {
    var w = lower(surface.trim());
    final apo = w.indexOf("'");
    if (apo > 0) w = w.substring(0, apo);
    List<String> direct(String t) {
      final out = <String>[];
      if (_has(t)) out.add(t);
      final rows = db.select('SELECT f.lemma FROM form f JOIN lemma l ON l.word = f.lemma WHERE f.form=? ORDER BY l.rank', [t]);
      for (final r in rows) {
        final l = r.columnAt(0) as String;
        if (!out.contains(l)) out.add(l);
      }
      // An entry that only says which form of another word it is
      // ("annesi": possessive of anne; "yılında") comes after that word.
      if (out.length > 1 && out.first == t && _onlyFormOf(t, out.skip(1).toSet())) out.add(out.removeAt(0));
      return out;
    }

    final found = direct(w);
    if (found.isNotEmpty) return (found, false);
    for (final end in _endings) {
      if (w.length > end.length + 1 && w.endsWith(end)) {
        final r = direct(w.substring(0, w.length - end.length));
        if (r.isNotEmpty) return (r, false);
      }
    }
    // Not in the tables: a guess. Every base word the endings allow is kept
    // (at most three), so a wrong first guess is never the only one shown.
    final guesses = <String>[];
    // Verb forms the tables leave out ("olduğumu", "yaptığını", "alabilir"):
    // cut a verb ending and look for the infinitive (ol -> olmak).
    for (final end in _verbEndings) {
      if (w.length >= end.length + 2 && w.endsWith(end)) {
        var stem = w.substring(0, w.length - end.length);
        for (final st in {stem, if (stem.endsWith('d')) '${stem.substring(0, stem.length - 1)}t'}) {
          for (final inf in ['${st}mak', '${st}mek']) {
            if (_has(inf) && !guesses.contains(inf)) guesses.add(inf);
          }
          // negative: "olmadığından" is ol-ma-dığından (olmak)
          if (st.length > 3 && (st.endsWith('ma') || st.endsWith('me'))) {
            final pos = st.substring(0, st.length - 2);
            for (final inf in ['${pos}mak', '${pos}mek']) {
              if (_has(inf) && !guesses.contains(inf)) guesses.add(inf);
            }
          }
        }
      }
    }
    // Noun endings the tables leave out ("tehlikesi", "hesabına",
    // "yatırımcıları"): plural, possessive and case endings that agree with
    // the word's last vowel, on a noun or adjective the dictionary has.
    for (final n in _nounStems(w)) {
      if (!guesses.contains(n)) guesses.add(n);
    }
    if (guesses.isEmpty) return (const <String>[], false);
    return (guesses.take(3).toList(), true);
  }

  static final _formOf = RegExp(
      r'\b(singular|plural|person|possession|possessive|nominative|accusative|dative|locative|ablative|genitive|instrumental|definite|inflection|form)\b.* of (\S+)\s*$');

  bool _onlyFormOf(String w, Set<String> bases) {
    final e = entry(w);
    if (e == null || e.senses.isEmpty) return false;
    for (final s in e.senses) {
      for (final g in s.glosses) {
        final m = _formOf.firstMatch(g);
        if (m == null || !bases.contains(m.group(2)!.replaceAll(RegExp(r'[^a-zçğıöşüâîû]'), ''))) return false;
      }
    }
    return true;
  }

  static const _back = 'aıou', _vowels = 'aıoueiöüâîû';

  static String? _lastVowel(String s) {
    for (var i = s.length - 1; i >= 0; i--) {
      if (_vowels.contains(s[i])) return s[i];
    }
    return null;
  }

  // Whether the first vowel of [ending] follows the vowel harmony of [stem].
  static bool _harmony(String stem, String ending) {
    final v = _lastVowel(stem), e = _lastVowel(ending.isEmpty ? '' : ending.substring(0, ending.indexOf(RegExp('[$_vowels]')) + 1));
    if (v == null || e == null) return true;
    final backStem = _back.contains(v) || v == 'â' || v == 'û';
    if ('ae'.contains(e)) return backStem ? e == 'a' : e == 'e';
    const four = {'a': 'ı', 'ı': 'ı', 'o': 'u', 'u': 'u', 'e': 'i', 'i': 'i', 'ö': 'ü', 'ü': 'ü', 'â': 'ı', 'î': 'i', 'û': 'u'};
    return four[v] == e;
  }

  static final List<String> _nounEndings = () {
    const plural = ['', 'lar', 'ler'];
    const poss = ['', 'ım', 'im', 'um', 'üm', 'm', 'ın', 'in', 'un', 'ün', 'n', 'ı', 'i', 'u', 'ü', 'sı', 'si', 'su', 'sü',
      'ımız', 'imiz', 'umuz', 'ümüz', 'mız', 'miz', 'muz', 'müz', 'ınız', 'iniz', 'unuz', 'ünüz', 'nız', 'niz', 'nuz', 'nüz', 'ları', 'leri'];
    const cases = ['', 'ı', 'i', 'u', 'ü', 'yı', 'yi', 'yu', 'yü', 'nı', 'ni', 'nu', 'nü', 'a', 'e', 'ya', 'ye', 'na', 'ne',
      'da', 'de', 'ta', 'te', 'nda', 'nde', 'dan', 'den', 'tan', 'ten', 'ndan', 'nden', 'ın', 'in', 'un', 'ün', 'nın', 'nin', 'nun', 'nün',
      'la', 'le', 'yla', 'yle', 'ca', 'ce', 'ndaki', 'ndeki', 'daki', 'deki'];
    final out = <String>{};
    for (final p in plural) {
      for (final q in poss) {
        for (final c in cases) {
          final e = '$p$q$c';
          if (e.length >= 2) out.add(e);
        }
      }
    }
    return out.toList()..sort((a, b) => b.length.compareTo(a.length));
  }();

  bool _isNominal(String w) {
    final e = entry(w);
    return e != null && e.senses.any((s) => const {'noun', 'adj', 'name', 'pron'}.contains(s.pos));
  }

  /// The nouns a word with endings can belong to, the likeliest first. Consonants softened
  /// before a vowel are put back (hesab- → hesap, ağac- → ağaç) and a vowel
  /// dropped before an ending ("kadri" → kadir); the ending must follow the
  /// word's vowel harmony, and the rest must be two letters or more.
  List<String> _nounStems(String w) {
    final out = <String>[];
    // First the word as written before the ending, then with a softened
    // consonant or a dropped vowel put back ("kendinden" is kendi, not kent).
    for (final altered in [false, true]) {
      for (final end in _nounEndings) {
        if (w.length < end.length + 2 || !w.endsWith(end)) continue;
        final st = w.substring(0, w.length - end.length);
        if (!_harmony(st, end)) continue;
        if (!altered) {
          if (!out.contains(st) && _isNominal(st)) out.add(st);
          continue;
        }
        // Softening happens only before a vowel.
        if (!_vowels.contains(end[0]) && !(end[0] == 'y')) continue;
        final opts = <String>[
        if (st.endsWith('b')) '${st.substring(0, st.length - 1)}p',
        if (st.endsWith('c')) '${st.substring(0, st.length - 1)}ç',
        if (st.endsWith('d')) '${st.substring(0, st.length - 1)}t',
        if (st.endsWith('ğ')) ...['${st.substring(0, st.length - 1)}k', '${st.substring(0, st.length - 1)}g'],
        if (st.length >= 3 && !_vowels.contains(st[st.length - 1]) && !_vowels.contains(st[st.length - 2]))
          for (final v in 'ıiuü'.split('')) '${st.substring(0, st.length - 1)}$v${st[st.length - 1]}',
      ];
        for (final o in opts) {
          if (o.length >= 2 && !out.contains(o) && _isNominal(o)) out.add(o);
        }
      }
    }
    return out;
  }

  static final List<String> _verbEndings = () {
    final out = <String>{};
    const tails = ['', 'ı', 'i', 'u', 'ü', 'ını', 'ini', 'unu', 'ünü', 'ımı', 'imi', 'umu', 'ümü', 'ımızı', 'imizi', 'umuzu', 'ümüzü',
      'ında', 'inde', 'unda', 'ünde', 'ına', 'ine', 'una', 'üne', 'ından', 'inden', 'undan', 'ünden', 'ım', 'im', 'um', 'üm', 'ımız', 'imiz', 'umuz', 'ümüz'];
    for (final b in ['dığ', 'diğ', 'duğ', 'düğ', 'tığ', 'tiğ', 'tuğ', 'tüğ', 'acağ', 'eceğ', 'yacağ', 'yeceğ']) {
      for (final t in tails) {
        if (t.isNotEmpty) out.add('$b$t');
      }
    }
    for (final b in ['ma', 'me']) {
      for (final t in ['sı', 'si', 'sını', 'sini', 'sında', 'sinde', 'sına', 'sine', 'yı', 'yi', 'dan', 'den', 'k', 'z', 'm', 'n', 'nız', 'niz', 'mız', 'miz']) {
        out.add('$b$t');
      }
    }
    out.addAll([
      'abilir', 'ebilir', 'abilirim', 'ebilirim', 'abilirsin', 'ebilirsin', 'abiliriz', 'ebiliriz', 'abilirler', 'ebilirler', 'yabilir', 'yebilir',
      'acak', 'ecek', 'yacak', 'yecek', 'arak', 'erek', 'yarak', 'yerek', 'ınca', 'ince', 'unca', 'ünce', 'yınca', 'yince',
      'mış', 'miş', 'muş', 'müş', 'mıştı', 'mişti', 'muştu', 'müştü', 'dı', 'di', 'du', 'dü', 'tı', 'ti', 'tu', 'tü',
      'dım', 'dim', 'dum', 'düm', 'tım', 'tim', 'tum', 'tüm', 'dın', 'din', 'dun', 'dün', 'dık', 'dik', 'duk', 'dük', 'dılar', 'diler', 'dular', 'düler',
      'ıyor', 'iyor', 'uyor', 'üyor', 'yor', 'ıyorum', 'iyorum', 'uyorum', 'üyorum', 'yorum', 'ıyorsun', 'iyorsun', 'uyorsun', 'üyorsun', 'yorsun',
      'ıyordu', 'iyordu', 'uyordu', 'üyordu', 'yordu', 'ıyoruz', 'iyoruz', 'uyoruz', 'üyoruz', 'yoruz', 'ıyorlar', 'iyorlar', 'uyorlar', 'üyorlar', 'yorlar',
      'malı', 'meli', 'malıyım', 'meliyim', 'malısın', 'melisin', 'malıyız', 'meliyiz', 'sa', 'se', 'saydı', 'seydi', 'alım', 'elim', 'ayım', 'eyim',
    ]);
    final list = out.toList()..sort((a, b) => b.length.compareTo(a.length));
    return list;
  }();

  // Clitics and endings that are written on the word but are not in the
  // inflection tables, longest first.
  static const _endings = [
    'ndaki', 'ndeki', 'daki', 'deki', 'taki', 'teki', 'yla', 'yle', 'la', 'le', 'ki',
    'dır', 'dir', 'dur', 'dür', 'tır', 'tir', 'tur', 'tür', 'ydı', 'ydi', 'ydu', 'ydü', 'ysa', 'yse',
    'mı', 'mi', 'mu', 'mü',
  ];

  TrEntry? entry(String lemma) {
    final r = db.select('SELECT word, senses FROM lemma WHERE word=?', [lemma]);
    if (r.isEmpty) return null;
    final senses = [
      for (final s in jsonDecode(r.first['senses'] as String) as List)
        TrSense((s as Map)['p'] as String? ?? '', [for (final g in s['g'] as List) '$g'], s['s'] as String?),
    ];
    final ex = [
      for (final e in db.select('SELECT tr, en, id FROM ex WHERE lemma=?', [lemma])) TrExample(e['tr'] as String, e['en'] as String, e['id'] as int?),
    ];
    return TrEntry(lemma, senses, ex);
  }

  /// First English meanings of [lemma], short (lists and review cards).
  String? shortMeaning(String lemma) {
    final s = entry(lemma)?.senses;
    if (s == null || s.isEmpty || s.first.glosses.isEmpty) return null;
    final two = s.first.glosses.take(2).join('; ');
    return two.length <= 50 ? two : s.first.glosses.first;
  }

  /// English meanings of random common words (wrong options in a review quiz).
  List<String> randomGlosses({int limit = 300}) => [
        for (final r in db.select('SELECT senses FROM lemma WHERE rank < 8000 ORDER BY random() LIMIT ?', [limit]))
          for (final s in (jsonDecode(r.columnAt(0) as String) as List).take(1))
            if (((s as Map)['g'] as List).isNotEmpty) '${(s['g'] as List).first}',
      ];

  bool? _hasCtx;

  /// The meaning [lemma] has next to the words [context] (their base words),
  /// from Tatoeba sentences where the English showed the meaning: an index
  /// into all its glosses counted in order, or null when the words around it
  /// say nothing (then the first meaning stands).
  int? meaningInContext(String lemma, Iterable<String> context) {
    _hasCtx ??= db.select("SELECT 1 FROM sqlite_master WHERE name='ctxn'").isNotEmpty;
    if (!_hasCtx!) return null;
    final prior = {for (final r in db.select('SELECT g, n FROM ctxn WHERE lemma=?', [lemma])) r['g'] as int: (r['n'] as int).toDouble()};
    if (prior.length < 2) return null;
    final words = context.where((w) => w != lemma).toSet().toList();
    if (words.isEmpty) return null;
    final total = prior.values.fold<double>(0, (a, b) => a + b);
    final score = {for (final e in prior.entries) e.key: math.log(e.value / total)};
    var evidence = false;
    final q = 'SELECT g, word, n FROM ctx WHERE lemma=? AND word IN (${List.filled(words.length, '?').join(',')})';
    final byWord = <String, Map<int, int>>{};
    for (final r in db.select(q, [lemma, ...words])) {
      (byWord[r['word'] as String] ??= {})[r['g'] as int] = r['n'] as int;
    }
    for (final counts in byWord.values) {
      final nc = counts.values.fold<int>(0, (a, b) => a + b);
      for (final g in prior.keys) {
        final pg = prior[g]! / total;
        // P(meaning | word), smoothed toward how common the meaning is.
        final pgc = ((counts[g] ?? 0) + pg) / (nc + 1);
        score[g] = score[g]! + math.log(pgc) - math.log(pg);
      }
      evidence = true;
    }
    if (!evidence) return null;
    final best = score.entries.reduce((a, b) => b.value > a.value ? b : a);
    return best.key;
  }

  /// The most common words, most common first (the dictionary's word list).
  List<String> commonWords({int limit = 100}) => [
        for (final r in db.select('SELECT word FROM lemma ORDER BY rank LIMIT ?', [limit])) r.columnAt(0) as String,
      ];

  /// Turkish words with an English meaning that starts with [en] ("dog" → köpek),
  /// whole-meaning matches first, then by how common the word is.
  List<(String, String)> searchEnglish(String en, {int limit = 40}) {
    final q = en.trim().toLowerCase().replaceAll('"', '');
    if (q.length < 2) return const [];
    final rows = db.select('SELECT word, senses FROM lemma WHERE senses LIKE ? ORDER BY rank LIMIT 400', ['%"$q%']);
    final out = <(String, String, int)>[];
    for (final r in rows) {
      final senses = jsonDecode(r['senses'] as String) as List;
      var best = 3;
      String? hit;
      for (final s in senses) {
        for (final g in (s as Map)['g'] as List) {
          final l = '$g'.toLowerCase();
          final score = l == q ? 0 : (l.startsWith('$q ') || l.startsWith('$q,') ? 1 : (l.startsWith(q) ? 2 : 3));
          if (score < best) {
            best = score;
            hit = '$g';
          }
        }
      }
      if (hit != null) out.add((r['word'] as String, hit, best));
    }
    // Stable: equal scores keep the frequency order.
    final sorted = [for (var i = 0; i < out.length; i++) (i, out[i])]..sort((a, b) => a.$2.$3 != b.$2.$3 ? a.$2.$3.compareTo(b.$2.$3) : a.$1.compareTo(b.$1));
    return [for (final (_, (w, m, _)) in sorted.take(limit)) (w, m)];
  }

  /// Words that start with [prefix], most common first (dictionary search).
  List<String> search(String prefix, {int limit = 40}) {
    final w = lower(prefix.trim());
    if (w.isEmpty) return const [];
    return [
      for (final r in db.select("SELECT word FROM lemma WHERE word >= ? AND word < ? ORDER BY rank LIMIT ?", [w, '$w￿', limit])) r.columnAt(0) as String,
    ];
  }

  String meta(String key) {
    final r = db.select('SELECT value FROM meta WHERE key=?', [key]);
    return r.isEmpty ? '' : r.first.columnAt(0) as String;
  }
}

class TrSense {
  final String pos;
  final List<String> glosses;

  /// Where the meaning comes from when not Wiktionary: 'wn' (KeNet / WordNet), 'st' (Storilex
  /// contributors), 'rv' or the older 'fd' (English → Turkish meanings reversed; despite the
  /// name, not FreeDict). See trSenseSourceLabel in dictionary_sources.dart.
  final String? source;
  const TrSense(this.pos, this.glosses, [this.source]);
}

class TrExample {
  final String tr, en;
  final int? tatoebaId;
  const TrExample(this.tr, this.en, this.tatoebaId);
}

class TrEntry {
  final String lemma;
  final List<TrSense> senses;
  final List<TrExample> examples;
  const TrEntry(this.lemma, this.senses, this.examples);
}

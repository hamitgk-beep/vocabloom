import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../l10n.dart';
import '../nlp/text.dart';

class Sense {
  final int synId;
  final String pos;
  final String gloss;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> tr;
  /// Turkish of [examples], same order; may be shorter or empty.
  final List<String> examplesTr;
  Sense(this.synId, this.pos, this.gloss, this.examples, this.synonyms, this.tr, [this.examplesTr = const []]);
}

class WordInfo {
  final String lemma;
  final List<String> trFreeDict;
  final List<Sense> senses;
  WordInfo(this.lemma, this.trFreeDict, this.senses);
  bool get isEmpty => trFreeDict.isEmpty && senses.isEmpty;
}

Map<String, String> get posNames => uiEnglish
    ? const {'n': 'noun', 'v': 'verb', 'a': 'adjective', 'r': 'adverb'}
    : const {'n': 'isim', 'v': 'fiil', 'a': 'sıfat', 'r': 'zarf'};

/// Read-only bundled dictionary. Turkish word meanings (`ft`, read as
/// [WordInfo.trFreeDict]) come from Wiktionary and damdafayton/eng-tur-dictionary
/// (tools/main_meanings.py); WordNet gives English senses and base forms.
class DictDb {
  static const _version = '26';
  late final Database db;
  late final Lemmatizer lemmatizer;
  late final PhraseMatcher matcher;
  late final List<Expr> exprs;
  final Map<int, Expr> exprById = {};

  static Future<DictDb> open(Directory dir) async {
    final file = File(p.join(dir.path, 'dict_v$_version.db'));
    // Remove copies of older dictionary versions.
    for (final f in dir.listSync().whereType<File>()) {
      final n = p.basename(f.path);
      if (n.startsWith('dict_v') && n.endsWith('.db') && f.path != file.path) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    if (!file.existsSync() || file.lengthSync() < 1000000) {
      final data = await rootBundle.load('assets/dict.db');
      await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
    }
    final d = DictDb();
    d.db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    d.load();
    return d;
  }

  /// Irregular verbs: base form -> [V1, V2..., V3] ("be" -> be, was, were, been).
  final Map<String, List<String>> irregular = {};

  /// V2/V3 form -> base forms of the irregular verbs it belongs to ("found" -> find).
  final Map<String, List<String>> irregularOf = {};

  void load() {
    irregular.clear();
    irregularOf.clear();
    final known = <String>{};
    for (final r in db.select('SELECT DISTINCT lemma FROM sense')) {
      known.add(r.columnAt(0) as String);
    }
    for (final r in db.select('SELECT word FROM ft')) {
      known.add(r.columnAt(0) as String);
    }
    final exc = <String, List<String>>{};
    for (final r in db.select('SELECT form, lemma FROM exc')) {
      exc.putIfAbsent(r.columnAt(0) as String, () => []).add(r.columnAt(1) as String);
    }
    lemmatizer = Lemmatizer(known, exc);
    exprs = [];
    final forms = <int, List<String>>{};
    final cols = {for (final r in db.select('PRAGMA table_info(expr)')) r['name'] as String};
    final hasEx = cols.contains('ex'), hasEnTr = cols.contains('entr');
    for (final r in db.select('SELECT id, phrase, cat, tr, en, forms${hasEx ? ', ex' : ''}${hasEnTr ? ', entr, extr' : ''} FROM expr')) {
      final e = Expr(r['id'] as int, r['phrase'] as String, r['cat'] as String, r['tr'] as String?,
          r['en'] as String?, patternOf(r['phrase'] as String),
          ex: hasEx ? r['ex'] as String? : null, enTr: hasEnTr ? r['entr'] as String? : null, exTr: hasEnTr ? r['extr'] as String? : null);
      if (e.pattern.isEmpty) continue;
      exprs.add(e);
      exprById[e.id] = e;
      final f = r['forms'] as String?;
      if (f != null) forms[e.id] = (jsonDecode(f) as List).cast<String>();
      if (f != null && e.cat == 'irregular_verbs') {
        final vf = forms[e.id]!;
        if (vf.length >= 3) {
          irregular[e.phrase] = vf;
          for (final x in vf.skip(1)) {
            if (x != e.phrase) irregularOf.putIfAbsent(x, () => []).add(e.phrase);
          }
        }
      }
    }
    matcher = PhraseMatcher(lemmatizer, exprs, forms);
  }

  late final bool _hasExTr = db.select('PRAGMA table_info(syn)').any((r) => r['name'] == 'extr');

  /// Off until the own-dictionary tables have been checked on a copy of the database.
  /// While it is off, the app shows exactly the meanings it shows today.
  /// Not const, so the tests can switch it on for one check; the app never changes it.
  static bool useOwnDictionary = false;

  late final bool _hasOwnWord = db
      .select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'own_word'")
      .isNotEmpty;

  WordInfo lookup(String lemma) {
    // Own meanings first: keep_tr (the Wiktionary part that stays), then the new senses.
    // No own row, or an empty one, falls back to the current table (ft).
    var tr = <String>[];
    if (useOwnDictionary && _hasOwnWord) {
      final own = db.select('SELECT senses, keep_tr FROM own_word WHERE word = ?', [lemma]);
      if (own.isNotEmpty) {
        tr = [
          ...(jsonDecode(own.first.columnAt(1) as String) as List).cast<String>(),
          for (final s in jsonDecode(own.first.columnAt(0) as String) as List)
            (s as Map)['tr'] as String,
        ];
      }
    }
    if (tr.isEmpty) {
      final ft = db.select('SELECT tr FROM ft WHERE word = ?', [lemma]);
      tr = ft.isEmpty ? <String>[] : (jsonDecode(ft.first.columnAt(0) as String) as List).cast<String>();
    }
    final senses = <Sense>[];
    for (final r in db.select(
        'SELECT s.id, s.pos, s.gloss, s.examples, s.words, s.tr${_hasExTr ? ', s.extr' : ''} FROM sense x JOIN syn s ON s.id = x.syn_id '
        'WHERE x.lemma = ? ORDER BY x.rank, s.pos',
        [lemma])) {
      senses.add(Sense(
        r['id'] as int,
        r['pos'] as String,
        r['gloss'] as String,
        (jsonDecode(r['examples'] as String) as List).cast<String>(),
        (jsonDecode(r['words'] as String) as List).cast<String>().where((w) => w != lemma).toList(),
        r['tr'] == null ? const [] : (jsonDecode(r['tr'] as String) as List).cast<String>(),
        !_hasExTr || r['extr'] == null ? const [] : (jsonDecode(r['extr'] as String) as List).cast<String>(),
      ));
    }
    return WordInfo(lemma, tr, senses);
  }

  /// Lesk-style choice of the sense that best fits the sentence.
  final Map<String, Set<String>> _posCache = {};

  /// Parts of speech WordNet knows for [word] (any inflected form).
  late final bool _hasExd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='exd'").isNotEmpty;

  /// Built-in senses of an expression (Turkish + English, with translated
  /// examples), as JSON in the same shape the AI service returns. Null when
  /// this dictionary has none for it.
  String? exprDetail(String phrase, String cat) {
    if (!_hasExd) return null;
    final r = db.select('SELECT json FROM exd WHERE phrase=? AND cat=?', [phrase, cat]);
    return r.isEmpty ? null : r.first.columnAt(0) as String;
  }

  late final bool _hasExs =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='exs'").isNotEmpty;

  /// Example sentences with Turkish translations (Tatoeba) for an expression
  /// ("phrase|cat") or a word ("w:lemma").
  List<(String, String)> examples(String key, {int limit = 4}) {
    if (!_hasExs) return const [];
    return [
      for (final r in db.select('SELECT en, tr FROM exs WHERE key=? LIMIT ?', [key, limit]))
        (r.columnAt(0) as String, r.columnAt(1) as String)
    ];
  }

  late final bool _hasWd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wd'").isNotEmpty;

  /// Built-in teacher-style explanation of [lemma]: (main Turkish, senses JSON), or null.
  (String, String)? wordDetail(String lemma) {
    if (!_hasWd) return null;
    final r = db.select('SELECT tr, json FROM wd WHERE word=?', [lemma]);
    return r.isEmpty ? null : (r.first.columnAt(0) as String, r.first.columnAt(1) as String);
  }

  late final bool _hasWfd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wfd'").isNotEmpty;

  /// Built-in detailed word family of [lemma] (same JSON as WordFamily.toJsonString).
  String? familyDetail(String lemma) {
    if (!_hasWfd) return null;
    final r = db.select('SELECT w.json FROM fam f JOIN famg g ON g.id=f.gid JOIN wfd w ON w.root=g.root WHERE f.word=?', [lemma]);
    return r.isEmpty ? null : r.first.columnAt(0) as String;
  }

  final Map<String, Set<String>> _lemmaPosCache = {};

  /// Parts of speech of a lemma itself ('n', 'v', 'a', 'r'), not of its other forms.
  Set<String> lemmaPos(String lemma) => _lemmaPosCache.putIfAbsent(lemma, () {
        final out = <String>{};
        for (final r in db.select('SELECT DISTINCT pos FROM sense WHERE lemma=?', [lemma])) {
          final p = r.columnAt(0) as String;
          out.add(p == 's' ? 'a' : p);
        }
        return out;
      });

  Set<String> posOf(String word) => _posCache.putIfAbsent(word, () {
        final out = <String>{};
        for (final l in lemmatizer.lemmas(word)) {
          for (final r in db.select('SELECT DISTINCT pos FROM sense WHERE lemma=?', [l])) {
            final p = r.columnAt(0) as String;
            out.add(p == 's' ? 'a' : p);
          }
        }
        return out;
      });

  /// A two-word dictionary entry the word forms with its neighbour in the
  /// sentence ("golf course", "course of action"), or null.
  WordInfo? compoundAt(List<Token> sentence, int tokenIndex, String lemma) {
    final cands = <String>[
      if (tokenIndex > 0) ...lemmatizer.lemmas(sentence[tokenIndex - 1].lower).map((l) => '$l $lemma'),
      if (tokenIndex > 0) '${sentence[tokenIndex - 1].lower} $lemma',
      if (tokenIndex + 1 < sentence.length) '$lemma ${sentence[tokenIndex + 1].lower}',
    ];
    for (final c in cands) {
      if (c.split(' ').any((w) => stopWords.contains(w) || w.length < 2)) continue;
      final i = lookup(c);
      if (!i.isEmpty) return i;
    }
    return null;
  }

  Sense? bestSense(WordInfo info, List<Token> sentence, int tokenIndex) {
    if (info.senses.isEmpty) return null;
    final pos = guessPos(sentence, tokenIndex, info.senses.map((s) => s.pos == 's' ? 'a' : s.pos).toSet(), posOf: posOf);
    final ctx = <String>{};
    for (var i = 0; i < sentence.length; i++) {
      if (i == tokenIndex) continue;
      final w = sentence[i].lower;
      if (stopWords.contains(w) || w.length < 3) continue;
      ctx.addAll(lemmatizer.lemmas(w));
    }
    // "golf course": the compound's own definition tells which sense of
    // "course" this is (an area laid out for a sport, not a series of lessons).
    final comp = tokenIndex < sentence.length ? compoundAt(sentence, tokenIndex, info.lemma) : null;
    if (comp != null) {
      for (final s in comp.senses.take(2)) {
        for (final t in tokenize(s.gloss)) {
          if (stopWords.contains(t.lower) || t.lower.length < 3 || t.lower == info.lemma) continue;
          ctx.addAll(lemmatizer.lemmas(t.lower));
        }
      }
    }
    Sense? best;
    var bestScore = -1e9;
    for (var k = 0; k < info.senses.length; k++) {
      final s = info.senses[k];
      final bag = tokenize('${s.gloss} ${s.examples.join(' ')} ${s.synonyms.join(' ')}')
          .expand((t) => lemmatizer.lemmas(t.lower))
          .toSet();
      var score = bag.intersection(ctx).length * 2.0;
      if (pos != null && (s.pos == pos || (pos == 'a' && s.pos == 's'))) score += 6;
      score -= k * 0.15; // WordNet order roughly follows frequency
      if (s.tr.isNotEmpty) score += 0.3;
      if (score > bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  /// Index of the token in [sentence] that is a form of [lemma], or -1.
  int indexOfLemma(List<Token> sentence, String lemma) {
    for (var i = 0; i < sentence.length; i++) {
      final w = sentence[i].lower;
      if (w == lemma || lemmatizer.lemmas(w).contains(lemma)) return i;
    }
    return -1;
  }

  /// What [lemma] means in [sentence]: the WordNet sense that fits it and a
  /// Turkish meaning that is known to belong to that sense. [tr] is null when
  /// the dictionary has no Turkish for the sense used here; it never falls
  /// back to an unrelated meaning ("course" in "golf course" is not "akmak").
  ({Sense? sense, String? tr, String? pos, bool sure}) meaningIn(String lemma, String? sentence) {
    final raw = lookup(lemma);
    // Cross references ("bakınız: joust") are not meanings.
    final info = WordInfo(raw.lemma, raw.trFreeDict.where((t) => !t.toLowerCase().contains('bakınız')).toList(), raw.senses);
    final toks = sentence == null ? const <Token>[] : tokenize(sentence);
    final i = indexOfLemma(toks, lemma);
    if (i < 0) {
      // No sentence to go by: the word's most common meaning.
      final s = info.senses.firstOrNull;
      final tr = info.trFreeDict.isNotEmpty
          ? shortTr(info.trFreeDict.first)
          : info.senses.where((s) => s.tr.isNotEmpty).map((s) => s.tr.take(3).join(', ')).firstOrNull;
      // The part of speech follows the meaning shown: WordNet's first sense
      // of "fall" is the noun (autumn) but its first meaning is "düşmek".
      final sPos = s == null ? null : normPos(s.pos);
      final pos = tr == null
          ? sPos
          : isTrVerb(tr)
              ? 'v'
              : (sPos == 'v' ? null : sPos);
      return (sense: s, tr: tr, pos: pos, sure: true);
    }
    final comp = compoundAt(toks, i, lemma);
    final best = bestSense(info, toks, i);
    final pos = best == null ? null : normPos(best.pos);
    if (comp != null) {
      final ctr = comp.senses.where((s) => s.tr.isNotEmpty).map((s) => s.tr.take(2).join(', ')).firstOrNull ??
          (comp.trFreeDict.isNotEmpty ? shortTr(comp.trFreeDict.first) : null);
      if (ctr != null) return (sense: best, tr: ctr, pos: pos ?? 'n', sure: true);
    }
    if (best == null) {
      final f = info.trFreeDict.isEmpty ? null : shortTr(info.trFreeDict.first);
      return (sense: null, tr: f, pos: f != null && isTrVerb(f) ? 'v' : null, sure: true);
    }
    if (best.tr.isNotEmpty) return (sense: best, tr: best.tr.take(3).join(', '), pos: pos, sure: true);

    // The sense has no Turkish of its own. FreeDict's meanings are not tied
    // to senses, so one is matched to the sense through the Turkish of the
    // sense's synonyms ("simply" = "merely, just" -> "ancak, sadece").
    final samePos = info.trFreeDict.where((t) => isTrVerb(t) == (pos == 'v')).toList();
    final synTr = <String>{};
    final synFirst = <String>[];
    for (final w in best.synonyms.take(6)) {
      if (w.contains(' ') && w.split(' ').length > 3) continue;
      final si = lookup(w.toLowerCase());
      final mine = [
        ...si.senses.where((x) => normPos(x.pos) == pos && x.tr.isNotEmpty).map((x) => x.tr.take(3).join(', ')),
        ...si.trFreeDict.where((t) => isTrVerb(t) == (pos == 'v')),
      ];
      if (mine.isNotEmpty) synFirst.add(mine.first);
      for (final t in mine.take(4)) {
        synTr.addAll(_parts(t));
      }
    }
    if (synTr.isNotEmpty) {
      String? pick;
      var bestHit = 0;
      for (final t in samePos) {
        final hit = _parts(t).where(synTr.contains).length;
        if (hit > bestHit) {
          bestHit = hit;
          pick = t;
        }
      }
      if (pick != null) return (sense: best, tr: shortTr(pick), pos: pos, sure: true);
    }
    // The word's main sense for this part of speech: FreeDict's first meaning
    // of that part of speech is that sense.
    final first = info.senses.firstWhere((s) => normPos(s.pos) == pos);
    if (identical(first, best) && samePos.isNotEmpty) {
      return (sense: best, tr: shortTr(samePos.first), pos: pos, sure: true);
    }
    // A rarer sense: the Turkish of its synonym, otherwise the best guess
    // (marked unsure, so the AI service is asked when there is one).
    if (synFirst.isNotEmpty) return (sense: best, tr: shortTr(synFirst.first), pos: pos, sure: false);
    final guess = info.senses.where((s) => normPos(s.pos) == pos && s.tr.isNotEmpty).map((s) => s.tr.take(3).join(', ')).firstOrNull ??
        (samePos.isNotEmpty ? samePos.first : info.trFreeDict.firstOrNull);
    return (sense: best, tr: guess == null ? null : shortTr(guess), pos: pos, sure: false);
  }

  static Iterable<String> _parts(String t) =>
      t.toLowerCase().split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.length > 1);

  static String normPos(String p) => p == 's' ? 'a' : p;

  /// Whether a Turkish meaning is a verb ("akmak, hızla akmak").
  static bool isTrVerb(String tr) {
    final first = tr.split(RegExp(r'[,;]')).first.trim().toLowerCase();
    if (_mekNouns.contains(first)) return false;
    return RegExp(r'(mak|mek)$').hasMatch(first);
  }

  /// Common Turkish nouns that end like a verb.
  static const _mekNouns = {
    'ırmak', 'ekmek', 'yemek', 'parmak', 'çakmak', 'kaymak', 'damak', 'tokmak', 'yamak', 'kaşmak', 'kıymak',
    'kaynak', 'başmak', 'çömlek', 'emek', 'kepmek', 'sırmak', 'yumak', 'tımak', 'çekmek',
  };

  /// A meaning short enough for an answer button: its first two parts.
  static String shortTr(String s) {
    final parts = s.split(RegExp(r'[,;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts.isEmpty ? s.trim() : parts.take(2).join(', ');
  }

  /// Every Turkish meaning the dictionary has for [lemma], lowercased words.
  Set<String> trWordsOf(String lemma) {
    final info = lookup(lemma);
    final out = <String>{};
    for (final t in [...info.trFreeDict, for (final s in info.senses) ...s.tr]) {
      for (final p in t.toLowerCase().split(RegExp(r'[,;]'))) {
        final x = p.trim();
        if (x.isNotEmpty) out.add(x);
      }
    }
    return out;
  }

  /// Clean Turkish sense meanings of one part of speech, for wrong answers:
  /// main senses of words people meet often, so the wrong options look like
  /// ordinary answers rather than rare technical terms.
  List<String> randomSenseTr(String? pos, {int limit = 200}) {
    final posSql = pos == null ? '' : pos == 'a' ? "AND s.pos IN ('a','s')" : 'AND s.pos = ?';
    List<String> run(String sql) => [
          for (final r in db.select(sql, [if (pos != null && pos != 'a') pos, limit]))
            if ((jsonDecode(r.columnAt(0) as String) as List).isNotEmpty)
              (jsonDecode(r.columnAt(0) as String) as List).cast<String>().take(2).join(', ')
        ];
    final hasFreq = db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wfreq'").isNotEmpty;
    final out = hasFreq
        ? run('SELECT s.tr FROM sense x JOIN syn s ON s.id = x.syn_id JOIN wfreq f ON f.word = x.lemma '
            "WHERE s.tr IS NOT NULL AND s.tr != '[]' AND x.rank < 2 AND f.n >= 100 $posSql ORDER BY random() LIMIT ?")
        : <String>[];
    if (out.length >= 20) return out;
    return out + run("SELECT s.tr FROM syn s WHERE s.tr IS NOT NULL AND s.tr != '[]' $posSql ORDER BY random() LIMIT ?");
  }

  /// Meanings that are no good as an answer option: cross references
  /// ("bakınız: keep"), numbers, names, crude words.
  static bool badOption(String tr) {
    final t = tr.trim();
    if (t.isEmpty || t.length > 40) return true;
    final l = t.toLowerCase();
    if (l.contains('bakınız') || l.contains('bkz') || l.contains('see ')) return true;
    if (RegExp(r'\d').hasMatch(t)) return true;
    if (t.split(RegExp(r'[,;]')).any((p) => RegExp(r'^[A-ZÇĞİÖŞÜ]').hasMatch(p.trim()))) return true;
    const crude = ['göt', 'kıç', 'mastürbasyon', 'orospu', 'piç', 'sikiş', 'seks', 'cinsel', 'zampara', 'fahişe', 'meme'];
    return l.split(RegExp(r'[ ,;]+')).any(crude.contains) || l.contains('mastürbasyon');
  }

  /// Single words starting with [prefix] (letters, ' and - only), the most
  /// frequent first, for the dictionary search. An exact match comes first.
  /// Text with Turkish letters (ç, ğ, ı, ö, ş, ü) is not English: no words.
  List<String> searchWords(String prefix, {int limit = 40, int offset = 0}) {
    final raw = prefix.trim().toLowerCase();
    if (RegExp('[çğıöşüâîûİ]').hasMatch(raw)) return const [];
    final q = raw.replaceAll(RegExp(r"[^a-z'\-]"), '');
    if (q.isEmpty) return const [];
    return [
      for (final r in db.select(
          'SELECT w FROM (SELECT word AS w FROM ft WHERE word GLOB ?1 '
          'UNION SELECT word FROM wfreq WHERE word GLOB ?1 AND EXISTS (SELECT 1 FROM sense s WHERE s.lemma = word)) '
          "LEFT JOIN wfreq f ON f.word = w WHERE w NOT GLOB '* *' "
          'ORDER BY (w = ?2) DESC, IFNULL(f.n, 0) DESC, w LIMIT ?3 OFFSET ?4',
          ['$q*', q, limit, offset]))
        r.columnAt(0) as String
    ];
  }

  /// Names and grammar words that top the frequency counts but make a poor
  /// start for a word list ("tom", "the", "of"); still found by search.
  static const _skipCommon = {
    'tom', 'mary', 'sami', 'boston', 'john', 'layla', 'i', 'a', 'an', 'the', 'to', 'of', 'in', 'on', 'at', 'by', 'for', 'from',
    'with', 'about', 'into', 'over', 'off', 'up', 'out', 'down', 'and', 'or', 'but', 'so', 'if', 'than', 'as', 'that', 'this',
    'these', 'those', 'it', 'he', 'she', 'we', 'you', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'our',
    'their', 'its', 'himself', 'do', 'does', 'did', 'done', 'be', 'is', 'are', 'was', 'were', 'been', 'being', 'have', 'has',
    'had', 'can', 'could', 'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'not', 'no', 'what', 'how', 'why',
    'when', 'where', 'who', 'there', 'here', 'just', 'too', 'very', 'any', 'some', 'both', 'because', 'while', 'yet', 'even',
  };

  /// The single words met most often in books that have a Turkish meaning,
  /// most frequent first: what the dictionary tab lists before anything is
  /// typed (grammar words and names left out).
  List<String> commonWords({int limit = 100, int offset = 0}) {
    final out = <String>[];
    var skipped = 0;
    for (final r in db.select(
        "SELECT f.word FROM wfreq f WHERE f.word NOT GLOB '* *' AND f.word GLOB '[a-z][a-z]*' "
        "AND (EXISTS (SELECT 1 FROM ft WHERE ft.word = f.word AND ft.tr != '[]') "
        "OR EXISTS (SELECT 1 FROM sense x JOIN syn s ON s.id = x.syn_id WHERE x.lemma = f.word AND s.tr IS NOT NULL AND s.tr != '[]')) "
        'ORDER BY f.n DESC, f.word LIMIT ?',
        [offset + limit + _skipCommon.length])) {
      final w = r.columnAt(0) as String;
      if (_skipCommon.contains(w)) continue;
      if (skipped++ < offset) continue;
      out.add(w);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Lower case without Turkish accents, so "kopek" finds "köpek" and
  /// "Işık" finds "ışık".
  static String foldTr(String s) {
    const from = 'çğıöşüâîû';
    const to = 'cgiosuaiu';
    final l = s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
    final b = StringBuffer();
    for (final ch in l.split('')) {
      final i = from.indexOf(ch);
      b.write(i < 0 ? ch : to[i]);
    }
    return b.toString();
  }

  /// (English word, Turkish meaning, folded meaning) for every single word
  /// with a Turkish meaning; built the first time someone searches in Turkish.
  late final List<(String, String, String)> _trIndex = () {
    final out = <(String, String, String)>[];
    void add(String w, String json) {
      if (w.contains(' ')) return;
      for (final m in (jsonDecode(json) as List).cast<String>()) {
        final t = m.trim();
        if (t.isNotEmpty) out.add((w, t, foldTr(t)));
      }
    }

    for (final r in db.select("SELECT word, tr FROM ft WHERE tr != '[]'")) {
      add(r.columnAt(0) as String, r.columnAt(1) as String);
    }
    for (final r in db.select("SELECT x.lemma, s.tr FROM sense x JOIN syn s ON s.id = x.syn_id "
        "WHERE s.tr IS NOT NULL AND s.tr != '[]' AND x.rank < 4")) {
      add(r.columnAt(0) as String, r.columnAt(1) as String);
    }
    return out;
  }();

  late final Map<String, int> _freq = {
    for (final r in db.select('SELECT word, n FROM wfreq')) r.columnAt(0) as String: r.columnAt(1) as int,
  };

  /// Single words the dictionary has a meaning for (Turkish or WordNet).
  late final Set<String> _headwords = {
    for (final r in db.select("SELECT word FROM ft WHERE word NOT GLOB '* *'")) r.columnAt(0) as String,
    for (final r in db.select("SELECT DISTINCT lemma FROM sense WHERE lemma NOT GLOB '* *'")) r.columnAt(0) as String,
  };

  static const _abc = 'abcdefghijklmnopqrstuvwxyz';

  static Iterable<String> _edits1(String w) sync* {
    for (var i = 0; i <= w.length; i++) {
      final a = w.substring(0, i), b = w.substring(i);
      if (b.isNotEmpty) yield a + b.substring(1); // delete
      if (b.length > 1) yield a + b[1] + b[0] + b.substring(2); // swap
      for (var k = 0; k < _abc.length; k++) {
        final c = _abc[k];
        if (b.isNotEmpty && c != b[0]) yield a + c + b.substring(1); // replace
        yield a + c + b; // insert
      }
    }
  }

  /// The dictionary word a misspelt [word] most likely stands for
  /// ("overwhelmn" → overwhelm), or null. One letter off for words of 4 to 6
  /// letters, up to two for longer ones; the most common candidate wins.
  String? closestWord(String word) {
    final w = word.toLowerCase();
    if (w.length < 4 || !RegExp(r"^[a-z]+$").hasMatch(w) || _headwords.contains(w) || _freq.containsKey(w)) {
      return null; // a real word the dictionary lacks ("gonna") is not a typo
    }
    String? pick(Iterable<String> cands) {
      String? best;
      var bestN = -1;
      for (final c in cands) {
        if (c.length < 3 || !_headwords.contains(c)) continue;
        final n = _freq[c] ?? 0;
        if (n > bestN || (n == bestN && best != null && c.compareTo(best) < 0)) {
          best = c;
          bestN = n;
        }
      }
      return best;
    }

    final one = _edits1(w).toSet();
    final p1 = pick(one);
    if (p1 != null || w.length < 7) return p1;
    // Two letters off: only common words, so a long rare word is not taken
    // for a different one.
    final p2 = pick({for (final e in one) ..._edits1(e)});
    return p2 != null && (_freq[p2] ?? 0) > 0 ? p2 : null;
  }

  /// Turkish to English: English words whose Turkish meaning is [text] or
  /// starts with it, with the meaning that matched. Words whose meaning is
  /// exactly the text come first ("kitap" → book), then the common ones.
  List<(String, String)> searchTurkish(String text, {int limit = 40}) =>
      [for (final (w, m, _) in searchTurkishScored(text, limit: limit)) (w, m)];

  /// [searchTurkish] with how well each meaning matched: 0 or 1 = the text
  /// is one of the meanings, higher = a meaning only starts with it.
  List<(String, String, int)> searchTurkishScored(String text, {int limit = 40}) {
    final q = foldTr(text.trim()).replaceAll(RegExp(r'\s+'), ' ');
    if (q.length < 2) return const [];
    final wordStart = RegExp('(^|[^a-z])${RegExp.escape(q)}');
    final best = <String, (int, String)>{};
    for (final (w, m, f) in _trIndex) {
      if (!f.contains(q)) continue;
      int? score;
      for (final part in f.split(RegExp(r'[,;()]'))) {
        final p = part.trim();
        if (p == q) {
          score = 0;
          break;
        }
        if (p.startsWith(q)) {
          final next = p.length > q.length ? p[q.length] : ' ';
          final s = next == ' ' ? 2 : 3;
          if (score == null || s < score) score = s;
        } else if (wordStart.hasMatch(p)) {
          score ??= 4;
        }
      }
      // Some meanings carry English derived words ("worrisome üzücü"): a
      // partial match on an English word is not a Turkish match.
      if (score != null && score >= 2) {
        final hit = RegExp('(?:^|[^a-z])(${RegExp.escape(q)}[a-z]*)').firstMatch(f)?.group(1);
        if (hit != null && lemmatizer.known.contains(hit)) continue;
      }
      // A meaning that is one short word ("kitap") beats a long description.
      if (score == null) continue;
      if (score == 0 && f != q) score = 1;
      final old = best[w];
      if (old == null || score < old.$1) best[w] = (score, m);
    }
    final words = best.keys.toList()
      ..sort((a, b) {
        final c = best[a]!.$1.compareTo(best[b]!.$1);
        if (c != 0) return c;
        final d = (_freq[b] ?? 0).compareTo(_freq[a] ?? 0);
        return d != 0 ? d : a.length.compareTo(b.length);
      });
    return [for (final w in words.take(limit)) (w, best[w]!.$2, best[w]!.$1)];
  }

  /// The expressions of [cat] met most often in books, most frequent first
  /// (alphabetical when the dictionary has no counts).
  List<Expr> commonExprs(String cat, {int limit = 8}) {
    final byPhrase = {for (final e in exprs) if (e.cat == cat) e.phrase: e};
    final hasFreq = db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='exfreq'").isNotEmpty;
    final out = <Expr>[
      if (hasFreq)
        for (final r in db.select('SELECT phrase FROM exfreq WHERE cat = ? ORDER BY n DESC LIMIT ?', [cat, limit * 2]))
          ?byPhrase[r.columnAt(0) as String],
    ];
    if (out.length < limit) out.addAll(byCategory(cat).where((e) => !out.contains(e)).take(limit - out.length));
    return out.take(limit).toList();
  }

  List<Expr> byCategory(String cat) => exprs.where((e) => e.cat == cat).toList()
    ..sort((a, b) => a.phrase.compareTo(b.phrase));
}

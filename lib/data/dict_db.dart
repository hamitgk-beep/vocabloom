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

/// Read-only bundled dictionary (FreeDict + WordNet + KeNet + categories).
class DictDb {
  static const _version = '7';
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

  void load() {
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
    final hasEx = db.select('PRAGMA table_info(expr)').any((r) => r['name'] == 'ex');
    for (final r in db.select('SELECT id, phrase, cat, tr, en, forms${hasEx ? ', ex' : ''} FROM expr')) {
      final e = Expr(r['id'] as int, r['phrase'] as String, r['cat'] as String, r['tr'] as String?,
          r['en'] as String?, patternOf(r['phrase'] as String),
          ex: hasEx ? r['ex'] as String? : null);
      if (e.pattern.isEmpty) continue;
      exprs.add(e);
      exprById[e.id] = e;
      final f = r['forms'] as String?;
      if (f != null) forms[e.id] = (jsonDecode(f) as List).cast<String>();
    }
    matcher = PhraseMatcher(lemmatizer, exprs, forms);
  }

  late final bool _hasExTr = db.select('PRAGMA table_info(syn)').any((r) => r['name'] == 'extr');

  WordInfo lookup(String lemma) {
    final ft = db.select('SELECT tr FROM ft WHERE word = ?', [lemma]);
    final tr = ft.isEmpty ? <String>[] : (jsonDecode(ft.first.columnAt(0) as String) as List).cast<String>();
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

  late final bool _hasWfd =
      db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wfd'").isNotEmpty;

  /// Built-in detailed word family of [lemma] (same JSON as WordFamily.toJsonString).
  String? familyDetail(String lemma) {
    if (!_hasWfd) return null;
    final r = db.select('SELECT w.json FROM fam f JOIN famg g ON g.id=f.gid JOIN wfd w ON w.root=g.root WHERE f.word=?', [lemma]);
    return r.isEmpty ? null : r.first.columnAt(0) as String;
  }

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

  List<Expr> byCategory(String cat) => exprs.where((e) => e.cat == cat).toList()
    ..sort((a, b) => a.phrase.compareTo(b.phrase));
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../nlp/text.dart';

class Sense {
  final int synId;
  final String pos;
  final String gloss;
  final List<String> examples;
  final List<String> synonyms;
  final List<String> tr;
  Sense(this.synId, this.pos, this.gloss, this.examples, this.synonyms, this.tr);
}

class WordInfo {
  final String lemma;
  final List<String> trFreeDict;
  final List<Sense> senses;
  WordInfo(this.lemma, this.trFreeDict, this.senses);
  bool get isEmpty => trFreeDict.isEmpty && senses.isEmpty;
}

const posNames = {'n': 'isim', 'v': 'fiil', 'a': 'sıfat', 'r': 'zarf'};

/// Read-only bundled dictionary (FreeDict + WordNet + KeNet + categories).
class DictDb {
  static const _version = '1';
  late final Database db;
  late final Lemmatizer lemmatizer;
  late final PhraseMatcher matcher;
  late final List<Expr> exprs;
  final Map<int, Expr> exprById = {};

  static Future<DictDb> open(Directory dir) async {
    final file = File(p.join(dir.path, 'dict_v$_version.db'));
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
    for (final r in db.select('SELECT id, phrase, cat, tr, en, forms FROM expr')) {
      final e = Expr(r['id'] as int, r['phrase'] as String, r['cat'] as String, r['tr'] as String?,
          r['en'] as String?, patternOf(r['phrase'] as String));
      if (e.pattern.isEmpty) continue;
      exprs.add(e);
      exprById[e.id] = e;
      final f = r['forms'] as String?;
      if (f != null) forms[e.id] = (jsonDecode(f) as List).cast<String>();
    }
    matcher = PhraseMatcher(lemmatizer, exprs, forms);
  }

  WordInfo lookup(String lemma) {
    final ft = db.select('SELECT tr FROM ft WHERE word = ?', [lemma]);
    final tr = ft.isEmpty ? <String>[] : (jsonDecode(ft.first.columnAt(0) as String) as List).cast<String>();
    final senses = <Sense>[];
    for (final r in db.select(
        'SELECT s.id, s.pos, s.gloss, s.examples, s.words, s.tr FROM sense x JOIN syn s ON s.id = x.syn_id '
        'WHERE x.lemma = ? ORDER BY x.rank, s.pos',
        [lemma])) {
      senses.add(Sense(
        r['id'] as int,
        r['pos'] as String,
        r['gloss'] as String,
        (jsonDecode(r['examples'] as String) as List).cast<String>(),
        (jsonDecode(r['words'] as String) as List).cast<String>().where((w) => w != lemma).toList(),
        r['tr'] == null ? const [] : (jsonDecode(r['tr'] as String) as List).cast<String>(),
      ));
    }
    return WordInfo(lemma, tr, senses);
  }

  /// Lesk-style choice of the sense that best fits the sentence.
  Sense? bestSense(WordInfo info, List<Token> sentence, int tokenIndex) {
    if (info.senses.isEmpty) return null;
    final pos = guessPos(sentence, tokenIndex, info.senses.map((s) => s.pos).toSet());
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
      if (pos != null && s.pos == pos) score += 3;
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

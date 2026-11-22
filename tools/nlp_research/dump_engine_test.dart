// Task 5E: dumps what the current SenseEngine decides, with every candidate meaning, so that the
// research systems (spaCy, Sentence Transformers, cross-encoders, idiom classifiers) can be compared
// with it on exactly the same rows (tools/nlp_research/*.py). Not part of the app's test suite; it
// checks nothing. Run from the repository root:
//
//   NLP_SENSE="name=path.tsv,..." NLP_MAGPIE="name=path.tsv,..." NLP_EWT="name=path.jsonl" NLP_OUT=<dir> \
//     flutter test tools/nlp_research/dump_engine_test.dart
//
// Sense files: lemma, pos, gold synset id(s) separated by ';', KeNet Turkish, sentence (build_holdout.py,
// build_final.py, build_final_5e.py). MAGPIE files: idiom, label, (cat,) id, sentence (any of the builders).
// EWT: text_eval jsonl (build_final.py, build_text_eval.py).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/pos_tagger.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

Map<String, String> _files(String? env) => {
      for (final x in (env ?? '').split(',').where((e) => e.contains('=')))
        x.substring(0, x.indexOf('=')): x.substring(x.indexOf('=') + 1),
    };

List<List<String>> _rows(String path) => [
      for (final l in File(path).readAsLinesSync())
        if (!l.startsWith('#') && l.trim().isNotEmpty) l.split('\t'),
    ];

Map<String, Object?> _cand(DictDb d, SenseCandidate c, Set<String> gold, String gtr) {
  bool link(String? t, {bool syn = false}) =>
      t != null && gtr.isNotEmpty && gtr.split(', ').any((g) => t.split(', ').any((x) => syn ? d.trLink(x, g, pos: c.pos) != null : d.trLink(x, g) == 'same') || (syn ? d.trLink(t, g, pos: c.pos) != null : d.trLink(t, g) == 'same'));
  final t = c.tr.isEmpty ? null : c.tr.take(3).join(', ');
  return {
    'id': c.id, 'src': c.source, 'lemma': c.lemma, 'pos': c.pos, 'en': c.en, 'tr': c.tr.take(6).toList(), 'score': c.score,
    'parts': c.parts, 'lit': c.literal, 'unv': c.unverified, 'rank': c.rank, 'syns': c.synonyms.take(6).toList(),
    'ex': c.examples.take(2).toList(), 'gold': gold.contains(c.id), 'trOk': link(t), 'trSyn': link(t, syn: true),
  };
}

// NLP_TAGGER=<ewt_perceptron.json.gz>: the engine with the experimental tagger (Task 5E system B-in-engine).
SenseEngine _engine(DictDb d) {
  final p = Platform.environment['NLP_TAGGER'];
  return SenseEngine(d, tagger: p == null ? null : (PosTagger.load(p) ?? (throw StateError('tagger not loaded: $p'))));
}

void main() {
  final out = Platform.environment['NLP_OUT'];
  if (out == null) return;
  Directory(out).createSync(recursive: true);
  late DictDb d;
  late SenseEngine eng;
  setUpAll(() {
    d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    eng = _engine(d);
  });

  test('sense rows', () {
    for (final e in _files(Platform.environment['NLP_SENSE']).entries) {
      final sink = StringBuffer();
      eng = _engine(d); // a fresh cache per file: the cache key has no lemma, so files must not share it
      var k = 0;
      for (final r in _rows(e.value)) {
        final lemma = r[0], pos = r[1], gtr = r[3].replaceAll('; ', ', '), sentence = r[4];
        final gold = {for (final g in r[2].split(';')) 'wn:$g'};
        final toks = tokenize(sentence);
        final i = d.indexOfLemma(toks, lemma);
        final row = <String, Object?>{'k': k++, 'lemma': lemma, 'pos': pos, 'gold': gold.toList(), 'gtr': gtr, 'sentence': sentence, 'i': i};
        if (i >= 0) {
          final sw = Stopwatch()..start();
          final c = eng.resolve(SenseQuery(sentence: sentence, tokens: toks, index: i, lemma: lemma));
          row['us'] = sw.elapsedMicroseconds;
          row['word'] = toks[i].text;
          row['start'] = toks[i].start;
          row['end'] = toks[i].end;
          row['conf'] = c.confidence.name;
          row['shown'] = c.shown;
          row['best'] = c.best?.id;
          row['shownTr'] = c.tr;
          row['reason'] = c.reason;
          row['cands'] = [for (final x in c.ranked) _cand(d, x, gold, gtr)];
          row['bestc'] = c.best == null ? null : _cand(d, c.best!, gold, gtr);
          // First WordNet sense of the gold part of speech (baseline).
          final wnS = d.lookup(lemma).senses.where((s) => DictDb.normPos(s.pos) == pos).toList();
          row['first'] = wnS.isEmpty ? null : 'wn:${wnS.first.synId}';
          row['firstTr'] = wnS.isEmpty || wnS.first.tr.isEmpty ? null : wnS.first.tr.join(', ');
          bool same(String? t) => t != null && gtr.isNotEmpty && gtr.split(', ').any((g) => d.trLink(t, g) == 'same' || t.split(', ').any((x) => d.trLink(x, g) == 'same'));
          row['firstTrOk'] = same(row['firstTr'] as String?);
          row['shownTrOk'] = same(c.tr);
          // Review-card rule on the dictionary's common meaning.
          final common = d.commonMeaning(lemma).tr;
          if (common != null) {
            final f = eng.fit(lemma, sentence, common);
            row['fit'] = {'tr': common, 'fit': f.fit.name, 'why': f.why, 'best': f.sense?.best?.id, 'ok': same(common)};
          }
        }
        sink.writeln(jsonEncode(row));
      }
      File('$out/${e.key}.engine.jsonl').writeAsStringSync(sink.toString());
    }
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('magpie rows', () {
    for (final e in _files(Platform.environment['NLP_MAGPIE']).entries) {
      final sink = StringBuffer();
      eng = _engine(d); // a fresh cache per file: the cache key has no lemma, so files must not share it
      var k = 0;
      for (final r in _rows(e.value)) {
        // sense_eval_magpie_*: idiom, label, id, sentence; the others: idiom, label, cat, id, sentence, ...
        final four = r.length == 4;
        final idiom = r[0], label = r[1], s = four ? r[3] : r[4], id = four ? r[2] : r[3];
        final extra = four ? '' : (r.length > 5 ? r[5] : '');
        final toks = tokenize(s);
        final ms = d.matcher.match(toks).where((x) => x.expr.phrase == idiom).toList();
        final row = <String, Object?>{'k': k++, 'idiom': idiom, 'label': label, 'id': id, 'sentence': s, 'extra': extra, 'found': ms.isNotEmpty};
        if (ms.isNotEmpty) {
          final mm = ms.first;
          final sw = Stopwatch()..start();
          final c = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: mm.tokens.first, expr: mm.expr, exprTokens: mm.tokens));
          row['us'] = sw.elapsedMicroseconds;
          row['cat'] = mm.expr.cat;
          row['span'] = [toks[mm.tokens.first].start, toks[mm.tokens.last].end];
          row['literal'] = c.literalPhrase != null;
          row['conf'] = c.confidence.name;
          row['shownTr'] = c.tr;
          row['best'] = c.best?.id;
          row['reason'] = c.reason;
          row['cands'] = [for (final x in c.ranked) _cand(d, x, const {}, '')];
          row['bestc'] = c.best == null ? null : _cand(d, c.best!, const {}, '');
          final f = eng.fit(idiom, s, (mm.expr.tr ?? '').split(RegExp(r'[,;]')).first.trim());
          row['fit'] = f.fit.name;
        }
        sink.writeln(jsonEncode(row));
      }
      File('$out/${e.key}.engine.jsonl').writeAsStringSync(sink.toString());
    }
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('ewt tokens', () {
    const want = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'};
    final every = int.tryParse(Platform.environment['NLP_EWT_EVERY'] ?? '') ?? 1;
    for (final e in _files(Platform.environment['NLP_EWT']).entries) {
      final sink = StringBuffer();
      eng = _engine(d); // a fresh cache per file: the cache key has no lemma, so files must not share it
      final all = File(e.value).readAsLinesSync();
      for (var pi = 0; pi < all.length; pi += every) {
        final r = jsonDecode(all[pi]) as Map;
        final text = r['text'] as String;
        final toks = tokenize(text);
        final at = {for (var i = 0; i < toks.length; i++) toks[i].start: i};
        final ranges = sentenceRanges(text);
        for (final t in r['toks'] as List) {
          final s = (t as List)[0] as int, en = t[1] as int, form = t[2] as String, lemma = (t[3] as String).toLowerCase(), upos = t[4] as String;
          if (want[upos] == null) continue;
          final ti = at[s];
          if (ti == null || toks[ti].end != en) continue;
          final lower = toks[ti].lower;
          if (!RegExp(r'^[a-z]+$').hasMatch(lower)) continue;
          final sr = ranges.firstWhere((x) => s >= x.$1 && s < x.$2, orElse: () => (0, text.length));
          final st = [for (final x in toks) if (x.start >= sr.$1 && x.end <= sr.$2) x];
          final si = st.indexWhere((x) => x.start == s);
          if (si < 0) continue;
          final sent = text.substring(sr.$1, sr.$2);
          final c = eng.resolve(SenseQuery(sentence: sent.trim(), tokens: st, index: si));
          final byPos = <String, Map<String, Object?>>{};
          for (final x in c.ranked) {
            if (x.pos != null && !byPos.containsKey(x.pos)) byPos[x.pos!] = {'id': x.id, 'lemma': x.lemma, 'score': x.score, 'tr': x.tr.take(3).join(', ')};
          }
          sink.writeln(jsonEncode({
            'p': pi, 'form': form, 'start': s - sr.$1 - (sent.length - sent.trimLeft().length), 'sent': sent.trim(), 'gold_lemma': lemma, 'gold_upos': upos,
            'lemma_alone': eng.lemmaOf(lower), 'posOf': d.posOf(lower).toList(), 'cat': c.cat, 'shown': c.shown,
            'pos': c.best?.pos, 'lemma_ctx': c.shown ? c.best!.lemma : eng.lemmaOf(lower), 'conf': c.confidence.name, 'byPos': byPos,
          }));
        }
      }
      File('$out/${e.key}.engine.jsonl').writeAsStringSync(sink.toString());
    }
  }, timeout: const Timeout(Duration(minutes: 40)));
}

// Task 5F: what the SenseEngine says on the 5F idiom sets. Writes one JSON line per row; checks nothing.
// Run from the repository root (the same file is run on main and on the 5F branch):
//
//   NLP_5F_SETS=dev=/path/dev5f_magpie.tsv,claude=test/data/idiom_5f_claude.tsv NLP_5F_OUT=/path/out \
//     flutter test tools/nlp_research_5f/dump_5f_test.dart
//
// Set formats: MAGPIE (idiom, label, cat, id, sentence, variant, confidence) or the Claude set
// (part, phrase, expected, case, sentence), told apart by the first column.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final sets = Platform.environment['NLP_5F_SETS'];
  final out = Platform.environment['NLP_5F_OUT'];
  if (sets == null || out == null) return;
  test('dump', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    Directory(out).createSync(recursive: true);
    for (final spec in sets.split(',')) {
      final name = spec.substring(0, spec.indexOf('='));
      final path = spec.substring(spec.indexOf('=') + 1);
      final eng = SenseEngine(d); // a fresh cache per set
      final sink = StringBuffer();
      final sw = Stopwatch();
      var n = 0;
      for (final l in File(path).readAsLinesSync()) {
        if (l.startsWith('#') || l.trim().isEmpty) continue;
        final p = l.split('\t');
        final claude = p[0] == 'dev' || p[0] == 'final';
        final phrase = claude ? p[1] : p[0];
        final gold = claude ? p[2] : (p[1] == 'i' ? 'idiom' : 'literal');
        final s = claude ? p[4] : p[4];
        final row = <String, Object?>{
          'set': name,
          'part': claude ? p[0] : name,
          'phrase': phrase,
          'gold': gold,
          'case': claude ? p[3] : p[5],
          'sentence': s,
        };
        // The reader's path: the expression found inside one sentence of the text.
        final toks = tokenize(s);
        final ms = d.matcher.match(toks, text: s).where((m) => m.expr.phrase == phrase).toList();
        row['found'] = ms.isNotEmpty;
        if (ms.isNotEmpty) {
          final m = ms.first;
          sw.start();
          final c = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
          sw.stop();
          n++;
          row.addAll({
            'cat': m.expr.cat,
            'conf': c.confidence.name,
            'asIdiom': c.cat != null && c.literalPhrase == null && c.shown,
            'literal': c.literalPhrase != null,
            'shown': c.shown,
            'tr': c.tr,
            'reason': c.reason,
            'litCands': c.ranked.where((x) => x.literal).length,
            'litCandsTr': c.ranked.where((x) => x.literal && x.tr.isNotEmpty).length,
          });
        }
        // The review card's path ([SenseEngine.fit]): the whole stored sentence, the expression's own Turkish.
        final e = d.exprs.where((x) => x.phrase == phrase).firstOrNull;
        if (e?.tr != null) {
          final f = eng.fit(phrase, s, e!.tr!);
          row['fit'] = f.fit.name;
          row['fitWhy'] = f.why;
        }
        sink.writeln(jsonEncode(row));
      }
      File('$out/$name.jsonl').writeAsStringSync(sink.toString());
      // ignore: avoid_print
      print('$name: $n resolved, ${(sw.elapsedMicroseconds / (n == 0 ? 1 : n) / 1000).toStringAsFixed(2)} ms each');
    }
  });
}

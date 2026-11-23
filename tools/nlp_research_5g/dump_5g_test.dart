// Task 5G: what the SenseEngine says on the 5G idiom sets, one JSON line per row; checks nothing.
// Run from the repository root:
//
//   NLP_5G_SETS=dev=/path/dev5g_magpie.tsv,claude=test/data/idiom_5f_claude.tsv NLP_5G_OUT=/path/out \
//   [NLP_5G_MODE=baseline|cues] [NLP_5G_MATCH=1] flutter test tools/nlp_research_5g/dump_5g_test.dart
//
// NLP_5G_MODE=cues turns on SenseEngine.literalCues (off in the app unless decided otherwise);
// NLP_5G_MATCH=1 uses the experimental wider matcher (PhraseMatcher.variants), measured apart.
// Set formats: MAGPIE (idiom, label, cat, id, sentence, variant, confidence) or the Claude set
// (part, phrase, expected, case, sentence), told apart by the first column.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/literal_cues.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final sets = Platform.environment['NLP_5G_SETS'];
  final out = Platform.environment['NLP_5G_OUT'];
  final mode = Platform.environment['NLP_5G_MODE'] ?? 'baseline';
  final wide = Platform.environment['NLP_5G_MATCH'] == '1';
  if (sets == null || out == null) return;
  test('dump', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    Directory(out).createSync(recursive: true);
    for (final spec in sets.split(',')) {
      final name = spec.substring(0, spec.indexOf('='));
      final path = spec.substring(spec.indexOf('=') + 1);
      final eng = SenseEngine(d, literalCues: mode == 'cues');
      final sink = StringBuffer();
      final sw = Stopwatch();
      var n = 0;
      for (final l in File(path).readAsLinesSync()) {
        if (l.startsWith('#') || l.trim().isEmpty) continue;
        final p = l.split('\t');
        final claude = p[0] == 'dev' || p[0] == 'final';
        final phrase = claude ? p[1] : p[0];
        final gold = claude ? p[2] : (p[1] == 'i' ? 'idiom' : 'literal');
        final s = p[4];
        final row = <String, Object?>{
          'set': name,
          'part': claude ? p[0] : name,
          'phrase': phrase,
          'gold': gold,
          'case': claude ? p[3] : p[5],
          'id': claude ? '' : p[3],
          'sentence': s,
        };
        final toks = tokenize(s);
        final all = wide ? d.matcher.match(toks, text: s, variants: true) : d.matcher.match(toks, text: s);
        final ms = all.where((m) => m.expr.phrase == phrase).toList();
        row['found'] = ms.isNotEmpty;
        if (ms.isNotEmpty) {
          final m = ms.first;
          row['idx'] = m.tokens;
          row['variant'] = m.variant;
          row['cues'] = literalCuesOf(d, m.expr, toks, m.tokens, s).toJson();
          sw.start();
          final c = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
          sw.stop();
          n++;
          final bestI = c.ranked.where((x) => !x.literal).firstOrNull;
          final bestL = c.ranked.where((x) => x.literal).firstOrNull;
          row.addAll({
            'cat': m.expr.cat,
            'conf': c.confidence.name,
            'asIdiom': c.cat != null && c.literalPhrase == null && c.shown,
            'literal': c.literalPhrase != null,
            'shown': c.shown,
            'tr': c.tr,
            'reason': c.reason,
            'sI': bestI?.score,
            'sL': bestL?.score,
            'freeI': bestI?.parts['free'],
            'litCands': c.ranked.where((x) => x.literal).length,
            'litCandsTr': c.ranked.where((x) => x.literal && x.tr.isNotEmpty).length,
          });
        }
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

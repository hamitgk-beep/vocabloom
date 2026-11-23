// Task 5N: list the expression candidates (sequence matcher + templates, the reader's expression categories) of each
// sentence, with the current engine's decision (SenseEngine.isLiteral for phrasal verbs, then resolve's confidence).
// Opens assets/dict.db read-only; writes only NLP_5N_OUT (JSONL).
//   NLP_5N_IN=sents.tsv NLP_5N_OUT=cands.jsonl flutter test tools/sentence_engine_5n/cands_5n_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/construction.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/nlp/unit_weights_5m.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final inPath = Platform.environment['NLP_5N_IN'];
  final outPath = Platform.environment['NLP_5N_OUT'];
  if (inPath == null || outPath == null) return;
  test('candidates 5N', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final an = SentenceAnalyzer(d, unitScorer5m);
    final cats = categories.map((c) => c.id).toSet();
    final sink = StringBuffer();
    for (final line in File(inPath).readAsLinesSync()) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final id = line.substring(0, tab), s = line.substring(tab + 1);
      final toks = tokenize(s);
      final seq = d.matcher.match(toks, text: s);
      final all = an.matches(s, toks, seq).where((m) => m.tokens.length >= 2 && cats.contains(m.expr.cat)).toList();
      if (all.isEmpty) continue;
      final c = <Map<String, Object?>>[];
      for (final m in all) {
        final lit = m.expr.cat == 'phrasal_verbs' && eng.isLiteral(m.expr, toks, m.tokens, sentence: s);
        final r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
        c.add({
          'expr_id': m.expr.id, 'phrase': m.expr.phrase, 'cat': m.expr.cat, 'tokens': m.tokens,
          'chars': [for (final t in m.tokens) [toks[t].start, toks[t].end]],
          'cur': lit ? 'literal' : r.confidence.name, 'tr': r.tr, 'lit': r.literalPhrase != null,
        });
      }
      sink.writeln(jsonEncode({'id': id, 'sentence': s, 'cands': c}));
    }
    File(outPath).writeAsStringSync(sink.toString());
  }, timeout: const Timeout(Duration(hours: 3)));
}

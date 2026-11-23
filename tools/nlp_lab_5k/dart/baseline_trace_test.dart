// Task 5K (development lab): the real Storilex expression path on a list of sentences, one JSON line per sentence.
// Read-only: opens assets/dict.db with OpenMode.readOnly and writes only to NLP_5K_OUT. Checks nothing; it is a trace.
//
//   NLP_5K_IN=/path/sentences.tsv NLP_5K_OUT=/path/baseline.jsonl flutter test tools/nlp_lab_5k/dart/baseline_trace_test.dart
//
// Input: "<sentence id>\t<sentence>" per line. Output per sentence:
//   tokens   : Storilex tokens with 0-based [start, end) character offsets (UTF-16, as Dart strings) and lemma candidates
//   matches  : every raw PhraseMatcher match (dictionary row id, phrase, category, token indexes, variant flag),
//              whether SenseEngine.isLiteral calls it literal (the reader hides those), and the panel's resolve():
//              confidence (sure / likely / none), shown Turkish, whether that Turkish is an unreviewed AI draft, reason
//   winners  : per token, the match the reader underlines and opens (ParaAnalysis.expressionsAt with every
//              expression category on: not literal, longest first, then filter order)
// The experiment engines of tools/nlp_lab_5k never feed back into this path or into card grading.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final inPath = Platform.environment['NLP_5K_IN'];
  final outPath = Platform.environment['NLP_5K_OUT'];
  if (inPath == null || outPath == null) return;
  test('trace', () {
    final sw = Stopwatch()..start();
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final loadMs = sw.elapsedMilliseconds;
    final order = {for (var i = 0; i < allCategories.length; i++) allCategories[i].id: i};
    final exprCats = categories.map((c) => c.id).toSet();
    final out = StringBuffer();
    var n = 0;
    final run = Stopwatch()..start();
    for (final line in File(inPath).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final tab = line.indexOf('\t');
      final id = line.substring(0, tab), s = line.substring(tab + 1);
      final toks = tokenize(s);
      final all = d.matcher.match(toks, text: s);
      final lit = <Match, bool>{};
      final ms = <Map<String, Object?>>[];
      for (final m in all) {
        bool literal;
        ContextSense? r;
        try {
          literal = m.expr.cat == 'phrasal_verbs' && eng.isLiteral(m.expr, toks, m.tokens, sentence: s);
          r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
        } catch (e) {
          literal = false;
        }
        lit[m] = literal;
        ms.add({
          'expr_id': m.expr.id,
          'phrase': m.expr.phrase,
          'cat': m.expr.cat,
          'tokens': m.tokens,
          'chars': [for (final t in m.tokens) [toks[t].start, toks[t].end]],
          'variant': m.variant,
          'literal_hidden': literal,
          'conf': r?.confidence.name,
          'literal_phrase': r?.literalPhrase,
          'tr_shown': r?.tr,
          'draft': r?.best?.unverified,
          'reason': r?.reason,
          'dict_tr': m.expr.tr,
          'dict_tr_draft': m.expr.trDraft,
        });
      }
      final winners = <int?>[];
      for (var i = 0; i < toks.length; i++) {
        final c = [
          for (var k = 0; k < all.length; k++)
            if (exprCats.contains(all[k].expr.cat) && all[k].tokens.contains(i) && !lit[all[k]]!) k,
        ]..sort((x, y) {
            final byLen = all[y].tokens.length.compareTo(all[x].tokens.length);
            return byLen != 0 ? byLen : order[all[x].expr.cat]!.compareTo(order[all[y].expr.cat]!);
          });
        winners.add(c.firstOrNull);
      }
      out.writeln(jsonEncode({
        'id': id,
        'sentence_sha1': null,
        'tokens': [
          for (var i = 0; i < toks.length; i++)
            {'i': i, 'start': toks[i].start, 'end': toks[i].end, 'text': toks[i].text, 'lemmas': d.lemmatizer.lemmas(toks[i].lower)},
        ],
        'matches': ms,
        'winners': winners,
      }));
      n++;
    }
    File(outPath).writeAsStringSync(out.toString());
    stdout.writeln('NLP5K baseline: $n sentences, dictionary load ${loadMs}ms, run ${run.elapsedMilliseconds}ms');
  }, timeout: const Timeout(Duration(hours: 2)));
}

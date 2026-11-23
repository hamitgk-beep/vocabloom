// Task 5L (research): read-only trace of every expression candidate of each sentence, for the 5K engine and for
// each 5L rule set, through the real app path: PhraseMatcher.match, SenseEngine.isLiteral (the reader hides those),
// the reader's longest-first / filter-order choice (ParaAnalysis.expressionsAt), SenseEngine.resolve (panel) and
// SenseEngine.fit (card grading, with the expression's own checked Turkish as the card's answer).
// Opens assets/dict.db read-only; writes only NLP_5L_OUT.
//
//   NLP_5L_IN=sents.tsv NLP_5L_OUT=out.jsonl NLP_5L_SYSTEMS="base,A,B,A+B" flutter test tools/nlp_research_5l/trace_5l_test.dart
//
// Output per sentence: {id, tokens:[[start,end,text]], cands:[{expr_id, phrase, cat, tokens, chars, variant,
//   tr_status, sys:{<name>: {hidden, win, conf, tr, draft, card, reason}}}]}.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/overlap_rules.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final inPath = Platform.environment['NLP_5L_IN'];
  final outPath = Platform.environment['NLP_5L_OUT'];
  if (inPath == null || outPath == null) return;
  final names = (Platform.environment['NLP_5L_SYSTEMS'] ?? 'base').split(',').map((s) => s.trim()).toList();
  test('trace 5L', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final engines = {
      for (final n in names) n: SenseEngine(d, overlap: n == 'base' ? OverlapRules.none : OverlapRules.parse(n)),
    };
    final order = {for (var i = 0; i < allCategories.length; i++) allCategories[i].id: i};
    final exprCats = categories.map((c) => c.id).toSet();
    final sink = StringBuffer();
    final ms = <String, int>{for (final n in names) n: 0};
    var count = 0;
    for (final line in File(inPath).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final tab = line.indexOf('\t');
      final id = line.substring(0, tab), s = line.substring(tab + 1);
      final toks = tokenize(s);
      final all = d.matcher.match(toks, text: s).where((m) => m.tokens.length >= 2).toList();
      final per = <Map<String, Object?>>[
        for (final m in all)
          {
            'expr_id': m.expr.id,
            'phrase': m.expr.phrase,
            'cat': m.expr.cat,
            'tokens': m.tokens,
            'chars': [for (final t in m.tokens) [toks[t].start, toks[t].end]],
            'variant': m.variant,
            'tr_status': m.expr.tr != null && m.expr.tr!.trim().isNotEmpty ? 'checked' : (m.expr.trDraft != null ? 'draft-only' : 'none'),
            'sys': <String, Object?>{},
          }
      ];
      for (final n in names) {
        final eng = engines[n]!;
        final sw = Stopwatch()..start();
        final hidden = [
          for (final m in all)
            m.expr.cat == 'phrasal_verbs' && eng.isLiteral(m.expr, toks, m.tokens, sentence: s),
        ];
        final wins = List.filled(all.length, 0);
        for (var i = 0; i < toks.length; i++) {
          final c = [
            for (var k = 0; k < all.length; k++)
              if (exprCats.contains(all[k].expr.cat) && all[k].tokens.contains(i) && !hidden[k]) k,
          ]..sort((x, y) {
              final byLen = all[y].tokens.length.compareTo(all[x].tokens.length);
              return byLen != 0 ? byLen : order[all[x].expr.cat]!.compareTo(order[all[y].expr.cat]!);
            });
          if (c.isNotEmpty) wins[c.first]++;
        }
        for (var k = 0; k < all.length; k++) {
          final m = all[k];
          final r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
          final tr = m.expr.tr;
          bool? card;
          if (tr != null && tr.trim().isNotEmpty) {
            card = eng.fit(m.expr.phrase, s, tr).confirmed;
          }
          (per[k]['sys'] as Map<String, Object?>)[n] = {
            'hidden': hidden[k],
            'win': wins[k],
            'conf': r.confidence.name,
            'literal': r.literalPhrase != null,
            'tr': r.tr,
            'draft': r.best?.unverified,
            'card': card,
            'reason': r.reason.length > 160 ? r.reason.substring(0, 160) : r.reason,
          };
        }
        ms[n] = ms[n]! + sw.elapsedMicroseconds;
      }
      sink.writeln(jsonEncode({
        'id': id,
        'tokens': [for (final t in toks) [t.start, t.end, t.text]],
        'cands': per,
      }));
      count++;
    }
    File(outPath).writeAsStringSync(sink.toString());
    stdout.writeln('NLP5L trace: $count sentences; ms/sentence ${{for (final n in names) n: (ms[n]! / 1000 / (count == 0 ? 1 : count)).toStringAsFixed(2)}}');
  }, timeout: const Timeout(Duration(hours: 3)));
}

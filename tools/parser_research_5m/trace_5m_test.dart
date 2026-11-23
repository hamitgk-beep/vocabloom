// Task 5M (research): read-only trace of expression candidates for two systems through the real app path
// (same as tools/nlp_research_5l/trace_5l_test.dart: SenseEngine.isLiteral, the reader's longest-first /
// filter-order choice, SenseEngine.resolve, SenseEngine.fit), with the current default engine (5L, rule A on):
//   cur  candidates from PhraseMatcher.match (what the app does today)
//   tpl  the same, but expressions with a template (lib/nlp/construction.dart) are matched on the one sentence
//        parse instead: a template match replaces a sequence match of the same expression (its slot fillers
//        are no longer words of the expression) and adds the variants the sequence matcher misses.
// Opens assets/dict.db read-only; writes only NLP_5M_OUT. Output format = 5L trace (metrics_5l.py reads it);
// a candidate a system does not produce has {hidden: true, win: 0, conf: none} for it.
//
//   NLP_5M_IN=sents.tsv NLP_5M_OUT=out.jsonl flutter test tools/parser_research_5m/trace_5m_test.dart
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
  final inPath = Platform.environment['NLP_5M_IN'];
  final outPath = Platform.environment['NLP_5M_OUT'];
  if (inPath == null || outPath == null) return;
  test('trace 5M', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final parser = ConstructionParser(d);
    final tm = TemplateMatcher(d, d.exprs);
    final withTemplate = {for (final t in tm.templates) t.expr.id};
    stdout.writeln('NLP5M templates: ${tm.templates.length} of ${d.exprs.length} expressions');
    final order = {for (var i = 0; i < allCategories.length; i++) allCategories[i].id: i};
    final exprCats = categories.map((c) => c.id).toSet();
    final sink = StringBuffer();
    var count = 0, usParse = 0, usMatch = 0;
    for (final line in File(inPath).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final tab = line.indexOf('\t');
      final id = line.substring(0, tab), s = line.substring(tab + 1);
      final toks = tokenize(s);
      final cur = d.matcher.match(toks, text: s).where((m) => m.tokens.length >= 2).toList();
      final sw = Stopwatch()..start();
      final parse = parser.parse(s, toks);
      usParse += sw.elapsedMicroseconds;
      sw.reset();
      final tms = tm.match(parse).where((m) => m.tokens.length >= 2).toList();
      usMatch += sw.elapsedMicroseconds;
      // tpl: a template match replaces a sequence match of the same expression that shares a token with it
      // (its slot fillers are no longer words of the expression); other sequence matches stay, so a template
      // can add candidates but not lose one the sequence matcher finds.
      final tpl = <Match>[
        for (final m in cur)
          if (!tms.any((t) => t.expr.id == m.expr.id && t.tokens.any(m.tokens.contains))) m,
        for (final m in tms) Match(m.expr, m.tokens, variant: m.variant == 'exact' ? null : m.variant),
      ];
      String key(Match m) => '${m.expr.id}:${(m.tokens.toList()..sort()).join(',')}';
      final systems = {'cur': cur, 'tpl': tpl, 'unit': tpl};
      final union = <String, Match>{};
      for (final l in systems.values) {
        for (final m in l) {
          union.putIfAbsent(key(m), () => m);
        }
      }
      final keys = union.keys.toList();
      final per = <Map<String, Object?>>[
        for (final k in keys)
          {
            'expr_id': union[k]!.expr.id,
            'phrase': union[k]!.expr.phrase,
            'cat': union[k]!.expr.cat,
            'tokens': union[k]!.tokens,
            'chars': [for (final t in union[k]!.tokens) [toks[t].start, toks[t].end]],
            'variant': union[k]!.variant,
            'templated': withTemplate.contains(union[k]!.expr.id),
            'sys': <String, Object?>{},
          }
      ];
      for (final entry in systems.entries) {
        final all = entry.value;
        final hidden = [for (final m in all) m.expr.cat == 'phrasal_verbs' && eng.isLiteral(m.expr, toks, m.tokens, sentence: s)];
        // unit: the tpl candidates, and one the unit scorer finds unlikely to be a unit here is hidden too
        final score = <double>[];
        for (var k = 0; k < all.length; k++) {
          final m = all[k];
          final r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
          final shared = all.any((o) => !identical(o, m) && o.tokens.any(m.tokens.contains));
          score.add(unitScorer5m.score(unitFeatures(parse, m.expr, m.tokens, variant: m.variant, conf: r.confidence.name, shared: shared)));
          if (entry.key == 'unit' && r.confidence.name != 'none' && score[k] < unitScorer5m.threshold) hidden[k] = true;
        }
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
        final mine = <String, int>{for (var k = 0; k < all.length; k++) key(all[k]): k};
        for (var u = 0; u < keys.length; u++) {
          final k = mine[keys[u]];
          if (k == null) {
            (per[u]['sys'] as Map<String, Object?>)[entry.key] = {'hidden': true, 'win': 0, 'conf': 'none', 'literal': false, 'tr': null, 'draft': null, 'card': null, 'reason': 'not a candidate'};
            continue;
          }
          final m = all[k];
          final r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
          final tr = m.expr.tr;
          bool? card;
          if (tr != null && tr.trim().isNotEmpty) card = eng.fit(m.expr.phrase, s, tr).confirmed;
          final shared = all.any((o) => !identical(o, m) && o.tokens.any(m.tokens.contains));
          if (entry.key != 'unit') (per[u]['feat_${entry.key}'] = unitFeatures(parse, m.expr, m.tokens, variant: m.variant, conf: r.confidence.name, shared: shared));
          (per[u]['sys'] as Map<String, Object?>)[entry.key] = {
            'hidden': hidden[k],
            'unit': double.parse(score[k].toStringAsFixed(4)),
            'win': wins[k],
            'conf': r.confidence.name,
            'literal': r.literalPhrase != null,
            'tr': r.tr,
            'draft': r.best?.unverified,
            'card': card,
            'reason': r.reason.length > 120 ? r.reason.substring(0, 120) : r.reason,
          };
        }
      }
      sink.writeln(jsonEncode({'id': id, 'tokens': [for (final t in toks) [t.start, t.end, t.text]], 'cands': per}));
      count++;
    }
    File(outPath).writeAsStringSync(sink.toString());
    final n = count == 0 ? 1 : count;
    stdout.writeln('NLP5M trace: $count sentences; parse ${(usParse / 1000 / n).toStringAsFixed(3)} ms/sentence, '
        'template match ${(usMatch / 1000 / n).toStringAsFixed(3)} ms/sentence');
  }, timeout: const Timeout(Duration(hours: 3)));
}

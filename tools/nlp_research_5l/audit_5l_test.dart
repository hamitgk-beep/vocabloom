// Task 5L: read-only overlap audit of every `expr` row of assets/dict.db (dictionary text only, no corpus sentences).
//   NLP_5L_AUDIT=out.tsv flutter test tools/nlp_research_5l/audit_5l_test.dart
// Classes (a row can have several; "suspect" is not "proven wrong"):
//   BE_PLUS_PARTICLE         phrasal verb "be" + one particle ("be on")
//   PV_PARTICLE_STARTS_EXPR  two-word phrasal verb whose particle is the first word of a non-phrasal-verb expression ("put on" / "on hold")
//   PV_TAKES_OBJECT          the checked sense examples give the particle (or the verb) an object
//   PV_STRANDED_ONLY         the checked sense examples never give the particle an object (rule A's evidence)
//   PV_FRAME_UNKNOWN         no checked example holds the verb and the particle
//   ARTICLE_NOUN             two words: a/an/the + a word ("the run")
//   OVERLAPS_OTHER_EXPR      its last word is the first word of another multi-word expression (or the other way round)
//   NAME_OR_QUOTE            capital letter or quote mark in the pattern
//   SENTENCE_PUNCT           . ! ? inside the phrase
// Columns also carry the 5K risk (EXPRESSION_MATCH_AUDIT_5K.tsv) and whether 5L rule A can fire on the row.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/overlap_rules.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final out = Platform.environment['NLP_5L_AUDIT'];
  if (out == null) return;
  test('audit 5L', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final risk5k = <int, String>{};
    for (final l in File('docs/nlp_engine_research/EXPRESSION_MATCH_AUDIT_5K.tsv').readAsLinesSync().skip(1)) {
      final c = l.split('\t');
      if (c.length > 12) risk5k[int.parse(c[0])] = c[12];
    }
    final multi = d.exprs.where((e) => e.pattern.length >= 2).toList();
    final firstWords = <String, int>{}, lastWords = <String, int>{};
    final firstNonPv = <String, int>{};
    for (final e in multi) {
      firstWords[e.pattern.first] = (firstWords[e.pattern.first] ?? 0) + 1;
      lastWords[e.pattern.last] = (lastWords[e.pattern.last] ?? 0) + 1;
      if (e.cat != 'phrasal_verbs') firstNonPv[e.pattern.first] = (firstNonPv[e.pattern.first] ?? 0) + 1;
    }
    final rows = StringBuffer('expr_id\tphrase\tcategory\tn_words\tclasses\trivals_starting_with_particle\tchecked_examples\trule_A_applies\trisk_5k\n');
    final counts = <String, int>{};
    final crossHigh = <String, int>{};
    for (final e in d.exprs) {
      final cls = <String>[];
      var rivals = 0, nEx = 0;
      bool? stranded;
      final pv2 = e.cat == 'phrasal_verbs' && e.pattern.length == 2;
      if (pv2) {
        if (isCopulaParticle(e)) cls.add('BE_PLUS_PARTICLE');
        rivals = firstNonPv[e.pattern.last] ?? 0;
        if (rivals > 0) cls.add('PV_PARTICLE_STARTS_EXPR');
        final senses = <List<String>>[];
        final js = d.exprDetail(e.phrase, e.cat);
        if (js != null) {
          try {
            for (final s in jsonDecode(js) as List) {
              senses.add([for (final x in ((s as Map)['examples'] as List? ?? const [])) '${(x as Map)['en'] ?? ''}']);
            }
          } catch (_) {}
        }
        var any = false, obj = false;
        for (final ex in senses) {
          nEx += ex.length;
          final v = strandedOnly(d, e, ex);
          if (v == false) obj = true;
          if (v == true) any = true;
        }
        stranded = obj ? false : (any ? true : null);
        cls.add(stranded == null ? 'PV_FRAME_UNKNOWN' : stranded ? 'PV_STRANDED_ONLY' : 'PV_TAKES_OBJECT');
      }
      if (e.pattern.length == 2 && const {'a', 'an', 'the'}.contains(e.pattern.first)) cls.add('ARTICLE_NOUN');
      if (e.pattern.length >= 2 &&
          ((firstWords[e.pattern.last] ?? 0) > (e.pattern.first == e.pattern.last ? 1 : 0) || (lastWords[e.pattern.first] ?? 0) > 0) &&
          !const {'a', 'an', 'the', 'to', 'of', 'and', 'or'}.contains(e.pattern.last)) {
        cls.add('OVERLAPS_OTHER_EXPR');
      }
      if (RegExp('[A-Z"“”]').hasMatch(e.phrase)) cls.add('NAME_OR_QUOTE');
      if (RegExp(r'[.!?]').hasMatch(e.phrase)) cls.add('SENTENCE_PUNCT');
      final ruleA = isCopulaParticle(e) && stranded == true;
      for (final c in cls) {
        counts[c] = (counts[c] ?? 0) + 1;
        if (risk5k[e.id] == 'high') crossHigh[c] = (crossHigh[c] ?? 0) + 1;
      }
      if (cls.isEmpty && risk5k[e.id] == null) continue;
      rows.writeln([e.id, e.phrase, e.cat, e.pattern.length, cls.join(','), rivals, nEx, ruleA, risk5k[e.id] ?? ''].join('\t'));
    }
    final summary = StringBuffer('# Task 5L overlap audit of assets/dict.db (read-only). ${d.exprs.length} rows, ${risk5k.length} in the 5K audit '
        '(${risk5k.values.where((v) => v == 'high').length} high). Rows with no class and no 5K risk are left out.\n');
    for (final k in counts.keys.toList()..sort()) {
      summary.writeln('# $k\t${counts[k]}\tof them 5K high risk: ${crossHigh[k] ?? 0}');
    }
    File(out).writeAsStringSync(summary.toString() + rows.toString());
    stdout.writeln(summary);
  });
}

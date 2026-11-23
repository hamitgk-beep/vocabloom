// Task 5I dev-only trace: every candidate the SenseEngine scores for an
// expression in a sentence. Prints; checks nothing. No user data is read
// (only assets/dict.db). Run from the repository root:
//   NLP_5I_TRACE='sentence||phrase' flutter test tools/nlp_research_5i/trace_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final spec = Platform.environment['NLP_5I_TRACE'];
  if (spec == null) return;
  test('trace', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final e = SenseEngine(d, idiomRecovery: Platform.environment['REC'] == '1', headFromPattern: Platform.environment['HEAD'] == '1');
    for (final one in spec.split(';;')) {
      final p = one.split('||');
      final s = p[0], phrase = p[1];
      final toks = tokenize(s);
      final ms = d.matcher.match(toks, text: s).where((m) => m.expr.phrase == phrase).toList();
      stdout.writeln('=== $s  [$phrase] matches=${ms.length}');
      if (ms.isEmpty) continue;
      final m = ms.first;
      final r = e.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
      stdout.writeln('decision: conf=${r.confidence.name} lit=${r.literalPhrase} cat=${r.cat} gap=${r.gap?.name} tr=${r.tr}');
      stdout.writeln('reason: ${r.reason}');
      for (final c in r.ranked.take(14)) {
        stdout.writeln('  ${c.literal ? 'LIT' : 'EXP'} ${c.unverified ? 'draft' : 'chk  '} $c');
      }
    }
  });
}

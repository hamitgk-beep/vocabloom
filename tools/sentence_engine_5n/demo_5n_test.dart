// Task 5N demo: break sentences into units with meanings (lib/nlp/sentence_engine.dart) and write a readable
// report. Opens assets/dict.db read-only.
//   NLP_5N_IN=sents.txt NLP_5N_OUT=out.md [NLP_5N_MODEL=idiom_cls.bin] flutter test tools/sentence_engine_5n/demo_5n_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/cross_encoder.dart';
import 'package:kelime_okur/nlp/sentence_engine.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final inPath = Platform.environment['NLP_5N_IN'];
  final outPath = Platform.environment['NLP_5N_OUT'];
  if (inPath == null || outPath == null) return;
  test('demo 5N', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_5n'));
    final app = AppState(d, u)..localAi = KeyAi(u);
    final model = Platform.environment['NLP_5N_MODEL'];
    final cls = model == null ? null : CrossEncoder.fromBytes(File(model).readAsBytesSync());
    final senseModel = Platform.environment['NLP_5N_SENSE'];
    final sm = senseModel == null ? null : CrossEncoder.fromBytes(File(senseModel).readAsBytesSync());
    final eng = SentenceEngine(d, app.senses, app.sentenceAnalyzer, app.grammar,
        categories: categories.map((c) => c.id).toSet(), classifier: cls, senseModel: sm);
    final out = StringBuffer();
    var n = 0;
    final sw = Stopwatch()..start();
    for (final s in File(inPath).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
      final b = eng.analyze(s.trim());
      n++;
      out.writeln('### ${b.sentence}');
      final g = {for (final m in b.grammar) '${m.tr} (${m.en})'};
      if (g.isNotEmpty) out.writeln('Dil bilgisi: ${g.join('; ')}');
      out.writeln();
      for (final x in b.units) {
        if (x.tr == null && !x.isExpression && !RegExp(r'[A-Za-z]').hasMatch(x.text)) continue;
        final head = x.isExpression ? '**${x.text}** → kalıp "${x.headword}" (${x.expr!.cat})' : '${x.text}${x.headword.toLowerCase() != x.text.toLowerCase() ? ' (${x.headword})' : ''}';
        if (Platform.environment['NLP_5N_DEBUG'] != null) {
          for (final c in x.scored) {
            out.writeln('    - ${c.p.toStringAsFixed(2)} ${c.tr} | ${c.en.length > 70 ? c.en.substring(0, 70) : c.en}');
          }
        }
        out.writeln('- $head: ${x.tr ?? '—'}${x.confidence == 'none' ? '' : ' [${x.confidence}]'}${x.isExpression ? ' p=${x.unitScore!.toStringAsFixed(2)}' : ''}');
      }
      final rej = b.rejected.where((r) => r.why != 'literal' || r.expr.cat == 'phrasal_verbs').toList();
      if (rej.isNotEmpty) out.writeln('  - elenen: ${rej.map((r) => '${r.expr.phrase} (${r.why}${r.score > 0 ? ' ${r.score.toStringAsFixed(2)}' : ''})').toSet().join(', ')}');
      out.writeln();
    }
    File(outPath).writeAsStringSync(out.toString());
    stdout.writeln('NLP5N demo: $n sentences, ${(sw.elapsedMilliseconds / (n == 0 ? 1 : n)).toStringAsFixed(1)} ms/sentence');
  }, timeout: const Timeout(Duration(hours: 1)));
}

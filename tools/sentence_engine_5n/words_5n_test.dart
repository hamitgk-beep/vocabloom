// Task 5N: the single-word meaning choices of sentences (SentenceEngine.choicesOf over SenseEngine.resolve), with
// SenseEngine's own pick, for labelling and for checking a sense model. Opens assets/dict.db read-only; writes only
// NLP_5N_OUT (JSONL, one line per word that has two or more meanings to choose between).
//   NLP_5N_IN=sents.tsv NLP_5N_OUT=words.jsonl flutter test tools/sentence_engine_5n/words_5n_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/sentence_engine.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final inPath = Platform.environment['NLP_5N_IN'];
  final outPath = Platform.environment['NLP_5N_OUT'];
  if (inPath == null || outPath == null) return;
  test('words 5N', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final sink = StringBuffer();
    for (final line in File(inPath).readAsLinesSync()) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final id = line.substring(0, tab), s = line.substring(tab + 1);
      final toks = tokenize(s);
      for (var i = 0; i < toks.length; i++) {
        if (!RegExp(r'^[A-Za-z]').hasMatch(toks[i].text)) continue;
        final r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: i));
        if (r.tr == null || r.reason.contains('name')) continue;
        final ch = SentenceEngine.choicesOf(r, max: 10);
        if (ch == null) continue;
        sink.writeln(jsonEncode({
          'id': id, 'sentence': s, 'index': i, 'start': toks[i].start, 'end': toks[i].end, 'word': toks[i].text,
          'headword': r.headword, 'cur': r.tr, 'conf': r.confidence.name,
          'choices': [for (final c in ch) {'lemma': c.lemma, 'pos': c.pos, 'rank': c.rank, 'en': c.en, 'tr': c.trShown}],
        }));
      }
    }
    File(outPath).writeAsStringSync(sink.toString());
  }, timeout: const Timeout(Duration(hours: 3)));
}

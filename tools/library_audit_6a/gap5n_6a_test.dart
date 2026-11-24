// Task 6A: every dictionary meaning of the 5N test words for which none of the offered meanings fitted
// (tools/sentence_engine_5n/data/pd_sense_labels.jsonl, pick -1), so they can be judged again against the full list.
// Opens assets/dict.db read-only; writes only AUDIT_6A_OUT (JSONL, the dump format of dump_6a_test.dart, one word).
//   AUDIT_6A_OUT=gap5n.jsonl flutter test tools/library_audit_6a/gap5n_6a_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final outPath = Platform.environment['AUDIT_6A_OUT'];
  if (outPath == null) return;
  test('gap 5N words', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final out = File(outPath)..writeAsStringSync('');
    final sink = StringBuffer();
    for (final line in File('tools/sentence_engine_5n/data/pd_sense_labels.jsonl').readAsLinesSync()) {
      final x = jsonDecode(line) as Map<String, dynamic>;
      if (x['pick'] != -1) continue;
      final s = x['sentence'] as String;
      final toks = tokenize(s);
      final i = toks.indexWhere((t) => t.start == x['start']);
      if (i < 0) continue;
      final r = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: i));
      sink.writeln(jsonEncode({
        'story': '5n:${x['key']}', 'level': '', 'text': s, 'prev': null, 'next': null, 'off': 0, 'reader': [], 'units': [], 'rejected': [],
        'grammar': [],
        'words': [
          {
            'i': i, 'w': toks[i].text, 'head': r.headword, 'reason': r.reason, 'conf': r.confidence.name, 'cur': r.tr,
            'cur_id': r.shown ? r.best?.id : null, 'offered': x['choices'],
            'all': [
              for (final c in r.ranked)
                {'id': c.id, 'src': c.source, 'lemma': c.lemma, 'pos': c.pos, 'en': c.en, 'tr': c.trShown,
                  if (c.trDerived) 'derived': true, if (c.unverified) 'unverified': true, if (c.literal) 'literal': true},
            ],
          }
        ],
      }));
    }
    out.writeAsStringSync(sink.toString(), mode: FileMode.append);
  }, timeout: const Timeout(Duration(hours: 1)));
}

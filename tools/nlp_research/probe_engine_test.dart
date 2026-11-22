// Task 5E: what the current SenseEngine says on a few probe sentences (the task's own examples and the
// problem cases of stage 1). These sentences were written for the demonstration; they are NOT test data
// and no number is measured on them. Prints a table; checks nothing. Run from the repository root:
//
//   NLP_PROBE=1 flutter test tools/nlp_research/probe_engine_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:sqlite3/sqlite3.dart';

const probes = <(String, String, String)>[
  // (case, word or expression, sentence)
  ('idiom', 'break the ice', 'The host told a joke to break the ice at the start of the meeting.'),
  ('literal', 'break the ice', 'He used a hammer to break the ice on the frozen pond.'),
  ('idiom, inflected', 'spill the beans', 'Who spilled the beans about the surprise party?'),
  ('literal, inflected', 'spill the beans', 'She tripped and spilled the beans all over the kitchen floor.'),
  ('idiom', 'on board', 'Is the finance team on board with the new plan?'),
  ('literal', 'on board', 'There were two hundred passengers on board the ship.'),
  ('idiom', 'go with the flow', 'Just relax and go with the flow.'),
  ('literal', 'go with the flow', 'The dead leaves go with the flow of the river.'),
  ('idiom, word inserted', 'break the ice', 'A funny story can break the awkward ice between strangers.'),
  ('idiom, passive / part only', 'break the ice', 'The ice was finally broken when the coach made a joke.'),
  ('noun vs verb', 'watch', 'He looked at his watch and left.'),
  ('noun vs verb', 'watch', 'We watch the news every evening.'),
  ('two noun senses', 'bank', 'They had a picnic on the bank of the river.'),
  ('two noun senses', 'bank', 'The bank raised its interest rates again.'),
  ('adjective vs adverb', 'hard', 'She works hard every day.'),
  ('adjective vs adverb', 'hard', 'It was a hard exam.'),
  ('adjective vs adverb', 'fast', 'He drives a fast car.'),
  ('adjective vs adverb', 'fast', 'He drives too fast.'),
  ('proper name', 'apple', 'Apple released a new phone in September.'),
  ('proper name', 'brown', 'Mr. Brown arrived late to the meeting.'),
  ('little context', 'light', 'It was light.'),
  ('little context', 'run', 'Run!'),
];

void main() {
  if (Platform.environment['NLP_PROBE'] == null) return;
  test('probes', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final out = StringBuffer('| case | word | sentence | confidence | Turkish shown | chosen meaning | why |\n|---|---|---|---|---|---|---|\n');
    for (final (kind, w, s) in probes) {
      final q = SenseQuery.find(d, s, w);
      final c = eng.resolve(q);
      final b = c.best;
      out.writeln('| $kind | $w | $s | ${c.confidence.name}${c.literalPhrase != null ? ' (read word by word)' : ''} | ${c.tr ?? '-'} | '
          '${b == null ? '-' : '${b.id} ${b.pos ?? ''} ${(b.en ?? '').length > 50 ? '${b.en!.substring(0, 50)}…' : b.en ?? ''}'} | '
          '${c.reason.length > 60 ? '${c.reason.substring(0, 60)}…' : c.reason} |');
    }
    // ignore: avoid_print
    print(out);
    final o = Platform.environment['NLP_PROBE_OUT'];
    if (o != null) File(o).writeAsStringSync(out.toString());
  });
}

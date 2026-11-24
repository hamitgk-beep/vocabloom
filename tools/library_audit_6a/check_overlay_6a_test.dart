// Task 6A: does every checked reading reach the reader? Reads the stories exactly as the reader does and, with the
// checked readings loaded (AUDIT_6A_ASSET, default assets/library/verified_6a.json.gz), counts how many word and
// expression entries the panel and the underline actually use. Opens assets/dict.db read-only; writes nothing.
//   flutter test tools/library_audit_6a/check_overlay_6a_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/nlp/verified_readings.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('checked readings reach the reader', () {
    final path = Platform.environment['AUDIT_6A_ASSET'] ?? VerifiedReadings.asset;
    if (!File(path).existsSync()) return;
    final raw = jsonDecode(utf8.decode(gzip.decode(File(path).readAsBytesSync()))) as Map<String, dynamic>;
    final entries = (raw['s'] as Map).cast<String, dynamic>();
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final plain = SenseEngine(d);
    final checked = SenseEngine(d)..verified = VerifiedReadings.fromBytes(File(path).readAsBytesSync());
    final catalog = (jsonDecode(File('assets/library/catalog.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final stories = (jsonDecode(utf8.decode(gzip.decode(File('assets/library/stories.json.gz').readAsBytesSync()))) as Map)
        .cast<String, String>();
    final used = <String>{};
    var wordSeen = 0, wordChanged = 0, wordSure = 0, wordHidden = 0, wordNotSure = 0, exprSeen = 0;
    for (final it in catalog) {
      final md = stories[it['id']];
      if (md == null) continue;
      final book = importLibraryMarkdown(md, it['title'] as String, it['author'] as String?, it['level'] as String);
      for (final ch in book.chapters) {
        for (final (kind, text) in ch.paragraphs) {
          if (kind == 'i') continue;
          final toks = tokenize(text);
          if (toks.isEmpty) continue;
          final ranges = sentenceRanges(text);
          final seq = d.matcher.match(toks, text: text);
          final done = <int>{};
          for (var ti = 0; ti < toks.length; ti++) {
            final s = sentenceAt(text, toks, ti, ranges: ranges);
            if (!done.add(s.index)) continue;
            final e = entries[s.text] as Map<String, dynamic>?;
            if (e == null) continue;
            for (final k in ((e['w'] as Map?) ?? const {}).keys) {
              final i = int.parse(k as String);
              final q = SenseQuery(sentence: s.text, tokens: s.tokens, index: i, prevSentence: s.prev, nextSentence: s.next);
              final r = checked.resolve(q);
              if (!used.add('w|${s.text}|$i')) continue;
              wordSeen++;
              if (r.reason.startsWith('checked 6A')) {
                wordChanged++;
                if (r.confidence == SenseConfidence.sure) wordSure++;
                if (!r.shown) wordHidden++;
                if (r.shown && r.confidence != SenseConfidence.sure) wordNotSure++;
              } else {
                final p = plain.resolve(q);
                if (p.reason == r.reason && p.best?.id == e['w'][k]) wordChanged++; // already the checked meaning
              }
            }
            for (final m in seq) {
              if (m.tokens.length < 2 || m.tokens.any((x) => x < s.first || x >= s.first + s.tokens.length)) continue;
              final idx = [for (final x in m.tokens) x - s.first];
              if (checked.verifiedUnit(s.text, m.expr, idx) != null && used.add('e|${s.text}|${m.expr.phrase}|$idx')) exprSeen++;
            }
          }
        }
      }
    }
    final wTotal = entries.values.fold<int>(0, (n, v) => n + (((v as Map)['w'] as Map?)?.length ?? 0));
    final eTotal = entries.values.fold<int>(0, (n, v) => n + (((v as Map)['e'] as Map?)?.length ?? 0));
    stdout.writeln('6A check: words $wordSeen/$wTotal reached, $wordChanged applied ($wordSure sure, $wordNotSure likely, '
        '$wordHidden no meaning shown); expressions $exprSeen/$eTotal reached');
  }, timeout: const Timeout(Duration(minutes: 30)));
}

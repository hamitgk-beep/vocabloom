// Task 6A: break every sentence of the bundled library stories into what the reader shows today and what the 5N
// engine reads, with every dictionary meaning of every word, for the audit. Opens assets/dict.db read-only; writes
// only AUDIT_6A_OUT (JSONL, one line per distinct sentence).
//   AUDIT_6A_OUT=sents.jsonl [AUDIT_6A_SHARD=0 AUDIT_6A_SHARDS=4] flutter test tools/library_audit_6a/dump_6a_test.dart
//
// Sentences are cut exactly as the reader cuts them (importLibraryMarkdown, tokenize, sentenceRanges, sentenceAt),
// so the audit's keys are the reader's own sentences.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/cross_encoder.dart';
import 'package:kelime_okur/nlp/sentence_engine.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

Map<String, Object?> cand(SenseCandidate c) => {
      'id': c.id, 'src': c.source, 'lemma': c.lemma, 'pos': c.pos, 'en': c.en, 'tr': c.trShown,
      if (c.trDerived) 'derived': true, if (c.unverified) 'unverified': true, if (c.literal) 'literal': true,
    };

int st0(String s) => tokenize(s).length;

void main() {
  final outPath = Platform.environment['AUDIT_6A_OUT'];
  if (outPath == null) return;
  final shard = int.parse(Platform.environment['AUDIT_6A_SHARD'] ?? '0');
  final shards = int.parse(Platform.environment['AUDIT_6A_SHARDS'] ?? '1');
  final limit = int.parse(Platform.environment['AUDIT_6A_LIMIT'] ?? '1000000000');
  test('dump 6A', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_6a'));
    final app = AppState(d, u)..localAi = KeyAi(u);
    // AUDIT_6A_WORDS_ONLY: only today's word panel (no reader expressions, no 5N engine), for a quick re-run.
    final wordsOnly = Platform.environment['AUDIT_6A_WORDS_ONLY'] != null;
    final eng = wordsOnly
        ? null
        : SentenceEngine(d, app.senses, app.sentenceAnalyzer, app.grammar,
            categories: categories.map((c) => c.id).toSet(),
            classifier: CrossEncoder.fromBytes(File('assets/models/expr_context_5n.bin').readAsBytesSync()),
            senseModel: CrossEncoder.fromBytes(File('assets/models/word_sense_5n.bin').readAsBytesSync()));
    final catalog = (jsonDecode(File('assets/library/catalog.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final stories = (jsonDecode(utf8.decode(gzip.decode(File('assets/library/stories.json.gz').readAsBytesSync()))) as Map)
        .cast<String, String>();
    final seen = <String>{};
    final out = File(outPath)..writeAsStringSync('');
    final sink = StringBuffer();
    var n = 0;
    final sw = Stopwatch()..start();
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
            if (!RegExp(r'[A-Za-z]').hasMatch(s.text)) continue;
            final key = '${s.text}\u0000${s.prev ?? ''}\u0000${s.next ?? ''}';
            if (!seen.add(key)) continue;
            if ((seen.length - 1) % shards != shard) continue;
            if (n >= limit) continue;
            n++;
            if (st0(s.text) != s.tokens.length) stdout.writeln('6A token count differs: ${s.text}');
            // the sentence on its own, as SentenceEngine and the panel read it
            final st = tokenize(s.text);
            final off = toks[s.first].start - st.first.start;
            int local(int pi) => pi - s.first;
            // 1. Today's reader: paragraph matches inside this sentence, with the phrasal-verb literal check.
            final reader = <Map<String, Object?>>[];
            for (final m in wordsOnly ? const <Match>[] : seq) {
              if (m.tokens.length < 2 || m.tokens.any((x) => x < s.first || x >= s.first + s.tokens.length)) continue;
              final idx = [for (final x in m.tokens) local(x)];
              final lit = m.expr.cat == 'phrasal_verbs' &&
                  app.senses.isLiteral(m.expr, s.tokens, idx, sentence: s.text, prev: s.prev, next: s.next);
              final r = app.senses.resolve(SenseQuery(
                  sentence: s.text, tokens: s.tokens, index: idx.first, expr: m.expr, exprTokens: idx, prevSentence: s.prev, nextSentence: s.next));
              reader.add({
                'phrase': m.expr.phrase, 'cat': m.expr.cat, 'eid': m.expr.id, 'tokens': idx, 'literal': lit,
                'tr': r.tr, 'conf': r.confidence.name, 'best': r.best?.id,
                'choices': [for (final c in r.ranked.take(8)) cand(c)],
              });
            }
            // 2. The 5N engine.
            final b = eng?.analyze(s.text, prev: s.prev, next: s.next);
            final units = [
              for (final x in b?.units ?? const <SentenceUnit>[])
                if (x.isExpression)
                  {'kind': 'expr', 'phrase': x.headword, 'cat': x.expr!.cat, 'eid': x.expr!.id, 'tokens': x.tokens, 'tr': x.tr, 'en': x.en, 'p': x.unitScore}
            ];
            final rejected = [
              for (final r in b?.rejected ?? const []) {'phrase': r.expr.phrase, 'cat': r.expr.cat, 'eid': r.expr.id, 'tokens': r.tokens, 'p': r.score, 'why': r.why}
            ];
            // 3. Every word: today's panel pick, the engine's pick and every meaning the dictionary has.
            final words = <Map<String, Object?>>[];
            for (var i = 0; i < st.length; i++) {
              if (!RegExp(r'^[A-Za-z]').hasMatch(st[i].text)) continue;
              final r = app.senses.resolve(SenseQuery(sentence: s.text, tokens: s.tokens, index: i, prevSentence: s.prev, nextSentence: s.next));
              final unit = b?.units.where((x) => x.tokens.contains(i))
                  .firstOrNull;
              words.add({
                'i': i, 'w': st[i].text, 'head': r.headword, 'reason': r.reason, 'conf': r.confidence.name,
                'cur': r.tr, 'cur_id': r.shown ? r.best?.id : null,
                if (unit != null && !unit.isExpression) 'eng_tr': unit.tr,
                if (unit != null && !unit.isExpression) 'eng_en': unit.en,
                if (unit != null && !unit.isExpression && unit.unitScore != null) 'eng_p': unit.unitScore,
                if (unit != null && unit.isExpression) 'in_expr': unit.headword,
                'all': [for (final c in r.ranked) cand(c)],
              });
            }
            sink.writeln(jsonEncode({
              'story': it['id'], 'level': it['level'], 'text': s.text, 'prev': s.prev, 'next': s.next, 'off': off,
              'reader': reader, 'units': units, 'rejected': rejected, 'words': words,
              'grammar': [for (final g in b?.grammar ?? const []) g.en],
            }));
            if (n % 200 == 0) {
              out.writeAsStringSync(sink.toString(), mode: FileMode.append);
              sink.clear();
              stdout.writeln('6A $shard: $n sentences, ${(sw.elapsedMilliseconds / n).toStringAsFixed(0)} ms each');
            }
          }
        }
      }
    }
    out.writeAsStringSync(sink.toString(), mode: FileMode.append);
    stdout.writeln('6A $shard done: $n sentences, ${(sw.elapsedMilliseconds / (n == 0 ? 1 : n)).toStringAsFixed(0)} ms each');
  }, timeout: const Timeout(Duration(hours: 6)));
}

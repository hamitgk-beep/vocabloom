// Task 5J: what a word card does on a set, one JSON line per (row, word of the matched expression); checks nothing.
// Run from the repository root:
//
//   NLP_5J_SETS=dev=/path/dev5h_magpie.tsv,tune=/path/tune5h_magpie.tsv NLP_5J_OUT=/path/out \
//   flutter test tools/nlp_research_5j/dump_5j_test.dart
//   NLP_5J_AUDIT=1 NLP_5J_OUT=/path/out flutter test tools/nlp_research_5j/dump_5j_test.dart   # dictionary example sentences
//
// Every guard mode (SenseEngine.wordCardGuard: off = the 5I engine, undecided, idiom, notLiteral) runs on the same
// rows, each with its own engine and its own ReviewQuiz, through the real card path:
//   * card "first": the answer the 5I report measured (the word's first main meaning) -> SenseEngine.fit.
//   * card "quiz": ReviewQuiz.answerFor(card with the sentence, nothing saved) -> graded (choice) or a flashcard.
//   * card "saved": the meaning the word panel would save with a new card (sure, the word itself, no AI draft,
//     and, with a guard, not blocked) -> ReviewQuiz.answerFor with that meaning -> graded or not.
// Set formats as in tools/nlp_research_5h. Sentences (BNC) stay in the local output only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review_quiz.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

final _alpha = RegExp(r"^[a-z][a-z'-]*$");

Map<String, Object?> card(DictDb d, SenseEngine eng, ReviewQuiz quiz, String s, List<Token> toks, int i, List<Match> all) {
  final lower = toks[i].lower;
  final lem = eng.lemmaOf(lower);
  final out = <String, Object?>{'lemma': lem};
  final ft = eng.mainTr(lem);
  if (ft.isNotEmpty) {
    final f = eng.fit(lem, s, ft.first.split(',').first.trim());
    out['first'] = f.fit.name;
    out['firstWhy'] = f.why;
  }
  final a = quiz.answerFor(SavedWord(lem, WordStatus.learning, s, null, null, DateTime(2026)));
  out['quizTr'] = a.tr;
  final blocker = eng.cardBlocker(s, toks, lem, matches: all, answer: a.tr);
  out['blocked'] = blocker?.expr.phrase;
  final noAnswer = eng.cardBlocker(s, toks, lem, matches: all);
  out['quiz'] = a.tr != null && a.choice;
  // The word panel (ContextSenseCard.resolve -> resolveTap) and the meaning it saves with a new card.
  final tap = eng.resolveTap(SenseQuery(sentence: s, tokens: toks, index: i, lemma: lem), all.where((m) => m.tokens.contains(i)));
  out['tap'] = {'shown': tap.shown, 'conf': tap.confidence.name, 'tr': tap.tr, 'cat': tap.cat, 'gap': tap.gap?.name, 'draft': tap.best?.unverified};
  final canSave = tap.shown && tap.cat == null && tap.headword == lem && tap.confidence == SenseConfidence.sure && !tap.best!.unverified;
  // The panel does not know the answer a later review asks: it saves no meaning when the word may be in an expression
  // whose Turkish does not carry the meaning it would save.
  final panelBlock = canSave ? eng.cardBlocker(s, toks, lem, matches: all, answer: tap.tr) : noAnswer;
  final savedTr = canSave && panelBlock == null ? tap.tr : null;
  out['savedTr'] = savedTr;
  out['savedWouldBe'] = canSave ? tap.tr : null;
  if (savedTr != null) {
    final b = quiz.answerFor(SavedWord(lem, WordStatus.learning, s, null, savedTr, DateTime(2026)));
    out['saved'] = b.tr != null && b.choice;
  }
  return out;
}

void main() {
  final sets = Platform.environment['NLP_5J_SETS'];
  final out = Platform.environment['NLP_5J_OUT'];
  final audit = Platform.environment['NLP_5J_AUDIT'] == '1';
  if (out == null || (sets == null && !audit)) return;
  test('dump', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    Directory(out).createSync(recursive: true);
    final u = UserDb.open(Directory.systemTemp.createTempSync('nlp5j'));
    final modes = [
      for (final g in WordCardGuard.values) g.name,
      for (final g in WordCardGuard.values.skip(1)) '${g.name}+c',
    ];
    final engines = {
      for (final m in modes)
        m: SenseEngine(d, wordCardGuard: WordCardGuard.values.byName(m.split('+').first), cardCarries: m.endsWith('+c')),
    };
    final quizzes = {for (final g in modes) g: ReviewQuiz(d, u, senses: engines[g])};
    final sw = {for (final g in modes) g: Stopwatch()};
    if (audit) {
      // The review audit of test/review_quiz_test.dart: the most frequent words, one dictionary example sentence each.
      final sink = StringBuffer();
      final rows = d.db.select(
          "SELECT substr(e.key, 3) AS w, e.en FROM exs e JOIN wfreq f ON f.word = substr(e.key, 3) "
          "WHERE e.key LIKE 'w:%' AND length(substr(e.key, 3)) > 3 GROUP BY e.key ORDER BY f.n DESC LIMIT 1500");
      for (final r in rows) {
        final s = r['en'] as String;
        final toks = tokenize(s);
        final all = d.matcher.match(toks, text: s);
        final i = d.indexOfLemma(toks, engines['off']!.lemmaOf((r['w'] as String).toLowerCase()));
        if (i < 0) continue;
        final row = <String, Object?>{'set': 'audit', 'word': r['w'], 'sentence': s};
        for (final g in modes) {
          sw[g]!.start();
          row[g] = card(d, engines[g]!, quizzes[g]!, s, toks, i, all);
          sw[g]!.stop();
        }
        sink.writeln(jsonEncode(row));
      }
      File('$out/audit.jsonl').writeAsStringSync(sink.toString());
    }
    for (final spec in (sets ?? '').split(',').where((x) => x.contains('='))) {
      final name = spec.substring(0, spec.indexOf('='));
      final path = spec.substring(spec.indexOf('=') + 1);
      final sink = StringBuffer();
      for (final l in File(path).readAsLinesSync()) {
        if (l.startsWith('#') || l.trim().isEmpty) continue;
        final p = l.split('\t');
        final phrase = p[0];
        final gold = p[1] == 'i' ? 'idiom' : 'literal';
        final s = p[4];
        final toks = tokenize(s);
        final all = d.matcher.match(toks, text: s);
        final ms = all.where((m) => m.expr.phrase == phrase).toList();
        if (ms.isEmpty) {
          sink.writeln(jsonEncode({'set': name, 'phrase': phrase, 'gold': gold, 'id': p[3], 'found': false}));
          continue;
        }
        final m = ms.first;
        // The expression's own reading (the same for every mode: the guard changes no reading).
        final c = engines['off']!.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
        final e = d.exprs.where((x) => x.phrase == phrase).firstOrNull;
        String? efit;
        if (e?.tr != null) efit = engines['off']!.fit(phrase, s, e!.tr!).fit.name;
        for (final i in m.tokens) {
          final lower = toks[i].lower;
          if (stopWords.contains(lower) || !_alpha.hasMatch(lower)) continue;
          final row = <String, Object?>{
            'set': name, 'phrase': phrase, 'gold': gold, 'id': p[3], 'found': true, 'cat': m.expr.cat,
            'tok': i, 'word': lower, 'others': all.where((x) => x != m && x.tokens.length > 1 && x.tokens.contains(i)).map((x) => x.expr.phrase).toList(),
            'expr': {'conf': c.confidence.name, 'shown': c.shown, 'literal': c.literalPhrase != null, 'cat': c.cat, 'gap': c.gap?.name, 'fit': efit},
            'sentence': s,
          };
          for (final g in modes) {
            sw[g]!.start();
            row[g] = card(d, engines[g]!, quizzes[g]!, s, toks, i, all);
            sw[g]!.stop();
            // The expression card and reading under this mode (must not change).
            final cg = engines[g]!.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
            (row[g] as Map<String, Object?>)['exprReading'] = cg.toString();
            if (e?.tr != null) (row[g] as Map<String, Object?>)['exprFit'] = engines[g]!.fit(phrase, s, e!.tr!).fit.name;
          }
          sink.writeln(jsonEncode(row));
        }
      }
      File('$out/$name.jsonl').writeAsStringSync(sink.toString());
    }
    // ignore: avoid_print
    print({for (final g in modes) g: '${sw[g]!.elapsedMilliseconds} ms'});
  }, timeout: Timeout.none);
}

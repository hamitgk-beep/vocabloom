// Independent measurement of the meaning-in-context rule (SenseEngine.fit) and
// of what review cards grade. Nothing here was used to write the rule: the
// examples are drawn by tools/eval/build_sense_eval.py with a fixed seed.
//
//  * test/data/sense_eval_semcor.tsv: 260 words in Brown corpus sentences whose
//    WordNet sense was chosen by human annotators (SemCor 3.0). The reference
//    Turkish is KeNet's Turkish of that synset (hand-made). An answer counts as
//    right only when it shares a Turkish meaning with that reference, so a
//    correct answer worded differently counts as wrong here (strict).
//  * $SENSE_EVAL_MAGPIE (optional, not in the repository): idioms in sentences
//    labelled idiomatic or literal by annotators (MAGPIE).
//
// It prints numbers and checks none of them: a threshold here would turn the
// set into something the code is tuned to. $SENSE_EVAL_OUT gets every row.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/data/review_quiz.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

DictDb _open(bool policy) {
  DictDb.sourcePolicy = policy;
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return d;
}

class _Tally {
  int graded = 0, gradedRight = 0, gradedWrong = 0, heldRight = 0, heldWrong = 0;
  void add(bool graded_, bool right) {
    if (graded_) {
      graded++;
      right ? gradedRight++ : gradedWrong++;
    } else {
      right ? heldRight++ : heldWrong++;
    }
  }

  String line(int n) {
    String pc(int a, int b) => b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(1)}%';
    return 'graded $graded/$n (${pc(graded, n)}) | right among graded $gradedRight/$graded (${pc(gradedRight, graded)}) | '
        'right and graded, of all ${pc(gradedRight, n)} | wrong graded as right $gradedWrong (${pc(gradedWrong, n)} of all) | '
        'not graded: $heldRight with a right answer, $heldWrong with a wrong one';
  }
}

void main() {
  tearDown(() => DictDb.sourcePolicy = true);

  test('words in sentences with a human-chosen sense (SemCor, KeNet Turkish)', () {
    final rows = [
      for (final l in File('test/data/sense_eval_semcor.tsv').readAsLinesSync())
        if (!l.startsWith('#') && l.trim().isNotEmpty) l.split('\t'),
    ];
    expect(rows.length, greaterThanOrEqualTo(200));
    final off = _open(false), on = _open(true);
    final engOff = SenseEngine(off, dictVersion: 'off');
    DictDb.sourcePolicy = true;
    final eng = SenseEngine(on);
    final user = UserDb.open(Directory.systemTemp.createTempSync('sense_eval'));
    final quiz = ReviewQuiz(on, user, senses: eng);
    final before = _Tally(), order = _Tally(), direct = _Tally(), now = _Tally(), fresh = _Tally();
    var pickRight = 0, pickWrong = 0, pickNone = 0, pickRightOff = 0, pickWrongOff = 0, pickNoneOff = 0;
    var sameSenseNoMatch = 0, viaSynonym = 0, viaSynonymWrong = 0, noCommon = 0;
    final why = <String, int>{};
    final byPos = <String, _Tally>{};
    final out = StringBuffer('lemma\tpos\treference\tanswer\tanswer right\tgraded now\twhy\tpicker\tpicker right\tsentence\n');
    for (final r in rows) {
      final lemma = r[0], pos = r[1], gold = r[3].replaceAll('; ', ', '), sentence = r[4], goldId = 'wn:${r[2]}';
      bool right(DictDb d, String? tr) => tr != null && d.trLink(tr, gold) == 'same';
      // Before this pull request: the AI draft first, every card graded.
      DictDb.sourcePolicy = false;
      final a0 = off.commonMeaning(lemma).tr;
      final c0 = engOff.resolve(SenseQuery(sentence: sentence, tokens: tokenize(sentence), index: off.indexOfLemma(tokenize(sentence), lemma), lemma: lemma));
      c0.shown ? (right(off, c0.best!.tr.join(', ')) ? pickRightOff++ : pickWrongOff++) : pickNoneOff++;
      DictDb.sourcePolicy = true;
      final a = on.commonMeaning(lemma).tr;
      if (a == null || a0 == null) {
        noCommon++;
        continue;
      }
      before.add(true, right(off, a0));
      order.add(true, right(on, a));
      final f0 = eng.fit(lemma, sentence, a, synonyms: false);
      direct.add(f0.confirmed, right(on, a));
      final f = eng.fit(lemma, sentence, a);
      now.add(f.confirmed, right(on, a));
      (byPos[pos] ??= _Tally()).add(f.confirmed, right(on, a));
      why['${f.fit.name}: ${f.why}'] = (why['${f.fit.name}: ${f.why}'] ?? 0) + 1;
      if (f.confirmed && f.why != 'same') {
        viaSynonym++;
        if (!right(on, a)) viaSynonymWrong++;
      }
      final c = f.sense;
      final shown = c != null && c.shown && c.cat == null;
      final pr = shown && right(on, c.best!.tr.join(', '));
      shown ? (pr ? pickRight++ : pickWrong++) : pickNone++;
      if (!f.confirmed && shown && c.best!.id == goldId) sameSenseNoMatch++;
      // A new card: the word panel saves the picker's meaning only when it is sure and checked.
      final saves = shown && c.confidence == SenseConfidence.sure && !c.best!.unverified;
      if (saves) {
        final ans = quiz.answerFor(SavedWord(lemma, WordStatus.learning, sentence, null, c.tr, DateTime(2026)));
        fresh.add(ans.choice, right(on, c.tr));
      }
      out.writeln('$lemma\t$pos\t$gold\t$a\t${right(on, a)}\t${f.confirmed}\t${f.fit.name}: ${f.why}\t${shown ? c.best!.tr.join(', ') : ''}\t${shown ? pr : ''}\t$sentence');
    }
    final n = rows.length - noCommon;
    final p = StringBuffer()
      ..writeln('SemCor examples: ${rows.length}, with a Turkish answer in the dictionary: $n')
      ..writeln('Cards saved with no meaning (the answer is the common meaning of the word):')
      ..writeln('  before the PR (AI draft first, all graded):   ${before.line(n)}')
      ..writeln('  source order, all graded:                     ${order.line(n)}')
      ..writeln('  graded only on the same Turkish:              ${direct.line(n)}')
      ..writeln('  now (same Turkish or a checked synonym):      ${now.line(n)}')
      ..writeln('  now, by part of speech: ${byPos.map((k, v) => MapEntry(k, '${v.gradedRight}/${v.graded} right among graded, ${v.gradedWrong} wrong graded'))}')
      ..writeln('  confirmed through a synonym: $viaSynonym, of them wrong by the reference: $viaSynonymWrong')
      ..writeln('  not graded although the picker chose the human-chosen sense (Turkish not recognised as the same): $sameSenseNoMatch')
      ..writeln('  reasons now: $why')
      ..writeln('New cards (meaning saved only when the picker is sure): saved ${fresh.graded + fresh.heldRight + fresh.heldWrong} of $n: ${fresh.line(n)}')
      ..writeln('Context picker, now:    right $pickRight, wrong $pickWrong, no meaning shown $pickNone (of $n)')
      ..writeln('Context picker, before: right $pickRightOff, wrong $pickWrongOff, no meaning shown $pickNoneOff (of ${rows.length})');
    // ignore: avoid_print
    print(p);
    final dump = Platform.environment['SENSE_EVAL_OUT'];
    if (dump != null) File(dump).writeAsStringSync('$p\n$out');
  });

  test('idioms used idiomatically or literally (MAGPIE, when the file is given)', () {
    final path = Platform.environment['SENSE_EVAL_MAGPIE'];
    if (path == null || !File(path).existsSync()) return;
    final d = _open(true);
    final eng = SenseEngine(d);
    final t = {'i': _Tally(), 'l': _Tally()};
    final found = {'i': 0, 'l': 0}, total = {'i': 0, 'l': 0};
    final why = <String, int>{};
    for (final l in File(path).readAsLinesSync()) {
      if (l.startsWith('#') || l.trim().isEmpty) continue;
      final r = l.split('\t');
      final e = d.exprs.where((e) => e.phrase == r[0] && e.cat == 'idioms' && e.tr != null).firstOrNull;
      if (e == null) continue;
      total[r[1]] = total[r[1]]! + 1;
      final f = eng.fit(e.phrase, r[3], e.tr!);
      if (f.why != 'not in sentence') found[r[1]] = found[r[1]]! + 1;
      // Idiomatic use: grading the idiom's meaning is right. Literal use: it is wrong.
      t[r[1]]!.add(f.confirmed, r[1] == 'i');
      final k = '${r[1]} ${f.fit.name}: ${f.why}${f.confirmed ? ' (picker ${f.sense!.confidence.name})' : ''}';
      why[k] = (why[k] ?? 0) + 1;
    }
    // ignore: avoid_print
    print('MAGPIE idioms. Before (every card graded): idiomatic ${total['i']} graded right, literal ${total['l']} graded wrong.\n'
        'Now: idiomatic use: graded ${t['i']!.graded}/${total['i']} (found in the sentence: ${found['i']}); '
        'literal use: graded as the idiom (wrong) ${t['l']!.graded}/${total['l']} (found: ${found['l']}).\nreasons: $why');
  });
}

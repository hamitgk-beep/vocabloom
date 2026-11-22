// Task 5A hold-out measurement (research only; not part of the app's test suite).
//
// Reads the files written by build_holdout.py from $HOLDOUT_DIR and prints numbers; it checks none of
// them, so nothing can be tuned to pass it. Run from the repository root:
//
//   HOLDOUT_DIR=<dir> flutter test docs/lexicon_research/scripts/holdout_eval_test.dart
//
// $HOLDOUT_OUT (a folder) gets every row, for reading the errors.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

String _pc(int a, int b) => b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(1)}%';

void main() {
  final dir = Platform.environment['HOLDOUT_DIR'];
  final outDir = Platform.environment['HOLDOUT_OUT'];
  if (dir == null) return;
  late DictDb d;
  late SenseEngine eng;
  setUpAll(() {
    final sw = Stopwatch()..start();
    d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    // ignore: avoid_print
    print('DictDb.load: ${sw.elapsedMilliseconds} ms, RSS ${(ProcessInfo.currentRss / 1048576).toStringAsFixed(0)} MB');
    eng = SenseEngine(d);
  });

  test('SemCor hold-out: sense chosen in context', () {
    final rows = [
      for (final l in File('$dir/holdout_semcor.tsv').readAsLinesSync())
        if (!l.startsWith('#') && l.trim().isNotEmpty) l.split('\t'),
    ];
    final dump = StringBuffer('lemma\tpos\tgold_id\tgold_tr\tconfidence\tbest_id\tbest_src\tbest_unverified\tshown_tr\tsense_ok\ttr_ok\tfit\tfirst_sense_ok\tgold_in_cands\tsentence\n');
    var n = 0, inSent = 0, shown = 0, sure = 0, likely = 0, sureOk = 0, likelyOk = 0, oracle = 0, first = 0, firstHasWn = 0;
    var trRows = 0, trShown = 0, trOk = 0, trSure = 0, trSureOk = 0, fitConf = 0, fitConfOk = 0, firstTrOk = 0;
    var bestWn = 0, bestDraft = 0;
    final byPos = <String, List<int>>{}; // [rows, shown, senseOk]
    final times = <int>[];
    for (final r in rows) {
      final lemma = r[0], pos = r[1], gid = 'wn:${r[2]}', gtr = r[3].replaceAll('; ', ', '), sentence = r[4];
      n++;
      final toks = tokenize(sentence);
      final i = d.indexOfLemma(toks, lemma);
      final bp = byPos.putIfAbsent(pos, () => [0, 0, 0]);
      bp[0]++;
      if (i < 0) {
        dump.writeln('$lemma\t$pos\t$gid\t$gtr\tnot found\t\t\t\t\t\t\t\t\t\t$sentence');
        continue;
      }
      inSent++;
      final sw = Stopwatch()..start();
      final c = eng.resolve(SenseQuery(sentence: sentence, tokens: toks, index: i, lemma: lemma));
      times.add(sw.elapsedMicroseconds);
      final b = c.best;
      final senseOk = c.shown && b!.id == gid;
      final inCands = c.ranked.any((x) => x.id == gid);
      if (inCands) oracle++;
      // Baseline: the dictionary's first WordNet sense of that part of speech.
      final wnSenses = d.lookup(lemma).senses.where((s) => DictDb.normPos(s.pos) == pos).toList();
      final firstOk = wnSenses.isNotEmpty && 'wn:${wnSenses.first.synId}' == gid;
      if (wnSenses.isNotEmpty) firstHasWn++;
      if (firstOk) first++;
      if (c.shown) {
        shown++;
        bp[1]++;
        if (b!.id.startsWith('wn:')) bestWn++;
        if (b.unverified) bestDraft++;
        if (c.confidence == SenseConfidence.sure) {
          sure++;
          if (senseOk) sureOk++;
        } else {
          likely++;
          if (senseOk) likelyOk++;
        }
      }
      if (senseOk) bp[2]++;
      var trGood = '';
      var fitS = '';
      if (gtr.isNotEmpty) {
        trRows++;
        bool same(String? t) => t != null && gtr.split(', ').any((g) => d.trLink(t, g) == 'same' || t.split(', ').any((x) => d.trLink(x, g) == 'same'));
        if (c.shown) {
          trShown++;
          final ok = same(c.tr);
          if (ok) trOk++;
          if (c.confidence == SenseConfidence.sure) {
            trSure++;
            if (ok) trSureOk++;
          }
          trGood = ok ? '1' : '0';
        }
        if (wnSenses.isNotEmpty && same(wnSenses.first.tr.isEmpty ? null : wnSenses.first.tr.join(', '))) firstTrOk++;
        // The review-card rule: would the dictionary's common Turkish be confirmed here?
        final common = d.commonMeaning(lemma).tr;
        if (common != null) {
          final f = eng.fit(lemma, sentence, common);
          fitS = '${f.fit.name}:${f.why}';
          if (f.confirmed) {
            fitConf++;
            if (same(common)) fitConfOk++;
          }
        }
      }
      dump.writeln([lemma, pos, gid, gtr, c.confidence.name, b?.id ?? '', b?.source ?? '', b?.unverified ?? '', c.tr ?? '',
          senseOk ? 1 : 0, trGood, fitS, firstOk ? 1 : 0, inCands ? 1 : 0, sentence].join('\t'));
    }
    times.sort();
    final out = StringBuffer()
      ..writeln('SemCor hold-out: $n rows, word found in sentence $inSent')
      ..writeln('  English sense = human-chosen synset: shown $shown (${_pc(shown, n)} coverage); '
          'right ${sureOk + likelyOk} (${_pc(sureOk + likelyOk, shown)} of shown, ${_pc(sureOk + likelyOk, n)} of all)')
      ..writeln('    sure: $sure, right $sureOk (${_pc(sureOk, sure)}), WRONG shown as sure ${sure - sureOk} (${_pc(sure - sureOk, n)} of all)')
      ..writeln('    likely: $likely, right $likelyOk (${_pc(likelyOk, likely)})')
      ..writeln('    best meaning is a WordNet synset: $bestWn of $shown; rests on an unverified AI draft: $bestDraft')
      ..writeln('    gold synset among the candidates (upper bound): $oracle (${_pc(oracle, n)})')
      ..writeln('    baseline "first WordNet sense of the gold part of speech": $first (${_pc(first, n)}; rows with such a sense $firstHasWn)')
      ..writeln('    by part of speech [rows, shown, right]: $byPos')
      ..writeln('  Turkish vs KeNet reference (strict, $trRows rows that have one): shown $trShown, same Turkish $trOk (${_pc(trOk, trShown)}); '
          'sure $trSure, right $trSureOk (${_pc(trSureOk, trSure)}); first-sense Turkish right $firstTrOk (${_pc(firstTrOk, trRows)})')
      ..writeln('  review-card rule (fit) on the common meaning: confirmed $fitConf, of them right by KeNet $fitConfOk (${_pc(fitConfOk, fitConf)})')
      ..writeln('  resolve time: median ${times.isEmpty ? '-' : times[times.length ~/ 2]} µs, p95 ${times.isEmpty ? '-' : times[(times.length * 0.95).floor()]} µs');
    // ignore: avoid_print
    print(out);
    if (outDir != null) File('$outDir/holdout_semcor_rows.tsv').writeAsStringSync(dump.toString());
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('MAGPIE hold-out: idiom found, idiomatic vs literal', () {
    final rows = [
      for (final l in File('$dir/holdout_magpie.tsv').readAsLinesSync())
        if (!l.startsWith('#') && l.trim().isNotEmpty) l.split('\t'),
    ];
    final dump = StringBuffer('idiom\tlabel\tcat\tfound\tliteral\tconfidence\tshown_tr\tsentence\n');
    final m = <String, int>{}; // label|found|predicted
    var tp = 0, fp = 0, fn = 0, tn = 0, notFoundI = 0, notFoundL = 0, sureI = 0, sureWrong = 0;
    for (final r in rows) {
      final idiom = r[0], label = r[1], cat = r[2], s = r[4];
      final toks = tokenize(s);
      final ms = d.matcher.match(toks).where((x) => x.expr.phrase == idiom).toList();
      if (ms.isEmpty) {
        label == 'i' ? notFoundI++ : notFoundL++;
        if (label == 'i') {
          fn++;
        } else {
          tn++;
        }
        dump.writeln('$idiom\t$label\t$cat\t0\t\t\t\t$s');
        continue;
      }
      final mm = ms.first;
      final c = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: mm.tokens.first, expr: mm.expr, exprTokens: mm.tokens));
      final literal = c.literalPhrase != null;
      final predIdiom = !literal;
      if (label == 'i' && predIdiom) tp++;
      if (label == 'l' && predIdiom) fp++;
      if (label == 'i' && !predIdiom) fn++;
      if (label == 'l' && !predIdiom) tn++;
      if (predIdiom && c.confidence == SenseConfidence.sure) {
        sureI++;
        if (label == 'l') sureWrong++;
      }
      m['$label|$predIdiom'] = (m['$label|$predIdiom'] ?? 0) + 1;
      dump.writeln('$idiom\t$label\t$cat\t1\t$literal\t${c.confidence.name}\t${c.tr ?? ''}\t$s');
    }
    final p = tp / (tp + fp == 0 ? 1 : tp + fp), rc = tp / (tp + fn == 0 ? 1 : tp + fn);
    final nI = rows.where((r) => r[1] == 'i').length, nL = rows.length - nI;
    final out = StringBuffer()
      ..writeln('MAGPIE hold-out: ${rows.length} rows ($nI idiomatic, $nL literal)')
      ..writeln('  phrase found by the matcher: idiomatic ${nI - notFoundI}/$nI (${_pc(nI - notFoundI, nI)}), literal ${nL - notFoundL}/$nL')
      ..writeln('  "used as an idiom" (found and not literal): precision ${(100 * p).toStringAsFixed(1)}% recall ${(100 * rc).toStringAsFixed(1)}% '
          'F1 ${(p + rc == 0 ? 0 : 200 * p * rc / (p + rc)).toStringAsFixed(1)} | tp $tp fp $fp fn $fn tn $tn')
      ..writeln('  literal sentences read as idiom: $fp of $nL (${_pc(fp, nL)}); idiomatic shown as "sure": $sureI, of them literal by gold $sureWrong')
      ..writeln('  detail $m');
    // ignore: avoid_print
    print(out);
    if (outDir != null) File('$outDir/holdout_magpie_rows.tsv').writeAsStringSync(dump.toString());
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('EWT: phrasal verbs (verb + particle) against UD compound:prt', () {
    const particles = {'up', 'down', 'off', 'out', 'away', 'back', 'on', 'over', 'in', 'around', 'about', 'through', 'along', 'apart', 'aside', 'by', 'forward', 'together'};
    var gold = 0, found = 0, pred = 0, predOk = 0, predNotLit = 0, predNotLitOk = 0;
    final dump = StringBuffer();
    for (final l in File('$dir/holdout_ewt_prt.jsonl').readAsLinesSync()) {
      final j = jsonDecode(l) as Map;
      final text = j['text'] as String;
      final g = {for (final x in j['gold'] as List) '${x[0]} ${x[1]}'};
      final toks = tokenize(text);
      final ms = d.matcher.match(toks).where((m) => m.expr.cat == 'phrasal_verbs').toList();
      final got = <String>{};
      for (final m in ms) {
        final parts = m.expr.phrase.split(' ');
        if (parts.length < 2 || !particles.contains(parts[1])) continue;
        final key = '${parts[0]} ${parts[1]}';
        pred++;
        final ok = g.contains(key);
        if (ok) predOk++;
        final lit = eng.isLiteral(m.expr, toks, m.tokens, sentence: text);
        if (!lit) {
          predNotLit++;
          if (ok) predNotLitOk++;
          got.add(key);
        }
        if (!ok) dump.writeln('FP\t${m.expr.phrase}\tliteral=$lit\t$text');
      }
      // A split phrasal verb ("took it off") is found by the context picker, not the matcher.
      for (var i = 0; i < toks.length; i++) {
        final c = eng.resolve(SenseQuery(sentence: text, tokens: toks, index: i));
        if (c.cat == 'phrasal_verbs') {
          final parts = c.headword.split(' ');
          if (parts.length >= 2) got.add('${parts[0]} ${parts[1]}');
        }
      }
      gold += g.length;
      for (final x in g) {
        if (got.contains(x)) {
          found++;
        } else {
          dump.writeln('FN\t$x\t$text');
        }
      }
    }
    final out = StringBuffer()
      ..writeln('EWT dev+test phrasal verbs: gold verb+particle $gold, found $found (recall ${_pc(found, gold)})')
      ..writeln('  matcher proposals with a particle: $pred, also verb+particle in gold $predOk (${_pc(predOk, pred)}); '
          'after the literal check $predNotLit, in gold $predNotLitOk (${_pc(predNotLitOk, predNotLit)})')
      ..writeln('  note: UD marks only particles (compound:prt); "look at"-type prepositional verbs are never gold, so precision is a lower bound.');
    // ignore: avoid_print
    print(out);
    if (outDir != null) File('$outDir/holdout_ewt_prt_rows.tsv').writeAsStringSync(dump.toString());
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('EWT: proper names given a word meaning', () {
    // Gold PROPN tokens (not sentence-initial) whose lower-case form is also a dictionary word ("Tom", "Bill").
    var n = 0, shown = 0, sure = 0;
    final ex = <String, int>{};
    for (final l in File('$dir/holdout_ewt_propn.jsonl').readAsLinesSync()) {
      final j = jsonDecode(l) as Map;
      final text = j['text'] as String;
      final toks = tokenize(text);
      for (final w in (j['propn'] as List).cast<String>()) {
        final i = toks.indexWhere((t) => t.text == w && t.start > 0);
        if (i <= 0 || d.lookup(d.headword(toks[i].lower)).isEmpty) continue;
        n++;
        final c = eng.resolve(SenseQuery(sentence: text, tokens: toks, index: i));
        if (c.shown) {
          shown++;
          if (c.confidence == SenseConfidence.sure) sure++;
          ex['$w→${c.tr}'] = (ex['$w→${c.tr}'] ?? 0) + 1;
        }
      }
    }
    final top = (ex.entries.toList()..sort((a, b) => b.value - a.value)).take(15).map((e) => '${e.key} (${e.value})').join('; ');
    // ignore: avoid_print
    print('EWT proper names that are also dictionary words: $n, given a word meaning $shown (${_pc(shown, n)}), as "sure" $sure (${_pc(sure, n)})\n  e.g. $top');
  }, timeout: const Timeout(Duration(minutes: 20)));

  test('UD Turkish: base form and part of speech of tr_en.db', () {
    final t = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));
    const upos = {'NOUN': 'noun', 'VERB': 'verb', 'ADJ': 'adj', 'ADV': 'adv'};
    final by = <String, List<int>>{}; // tb: [words, any, first, posFirst, none]
    final err = <String, int>{};
    final dump = StringBuffer();
    final sw = Stopwatch()..start();
    var calls = 0;
    for (final l in File('$dir/holdout_ud_tr.jsonl').readAsLinesSync()) {
      final j = jsonDecode(l) as Map;
      final tb = j['tb'] as String;
      final b = by.putIfAbsent(tb, () => [0, 0, 0, 0, 0]);
      for (final x in j['toks'] as List) {
        final form = x[0] as String, gl = TrEnDict.lower(x[1] as String), up = x[2] as String;
        if (!RegExp(r'[a-zçğıöşüâîû]').hasMatch(TrEnDict.lower(form))) continue;
        b[0]++;
        calls++;
        final ls = t.lemmas(form);
        final golds = {gl, if (up == 'VERB') ...['${gl}mak', '${gl}mek']};
        if (ls.isEmpty) {
          b[4]++;
          err['no base form'] = (err['no base form'] ?? 0) + 1;
          continue;
        }
        if (ls.any(golds.contains)) b[1]++;
        if (golds.contains(ls.first)) {
          b[2]++;
          final e = t.entry(ls.first);
          final p = e?.senses.firstOrNull?.pos;
          if (p != null && p == upos[up]) b[3]++;
        } else {
          final k = ls.any(golds.contains) ? 'right base not first' : 'wrong base';
          err[k] = (err[k] ?? 0) + 1;
          if (dump.length < 400000) dump.writeln('$k\t$form\tgold $gl/$up\tgot ${ls.take(3).join(',')}');
        }
      }
    }
    final out = StringBuffer('UD Turkish test files ($calls words, ${(sw.elapsedMicroseconds / (calls == 0 ? 1 : calls)).toStringAsFixed(0)} µs a word incl. entry):\n');
    var tot = [0, 0, 0, 0, 0];
    by.forEach((k, v) {
      tot = [for (var i = 0; i < 5; i++) tot[i] + v[i]];
      out.writeln('  $k: words ${v[0]}, no base form ${v[4]} (${_pc(v[4], v[0])}), right base first ${v[2]} (${_pc(v[2], v[0])}), '
          'right base anywhere ${v[1]} (${_pc(v[1], v[0])}), first meaning has the gold part of speech ${v[3]} (${_pc(v[3], v[2])} of right bases)');
    });
    out.writeln('  all: words ${tot[0]}, no base form ${_pc(tot[4], tot[0])}, right base first ${_pc(tot[2], tot[0])}, anywhere ${_pc(tot[1], tot[0])}, pos ${_pc(tot[3], tot[2])}');
    out.writeln('  errors: $err');
    // ignore: avoid_print
    print(out);
    if (outDir != null) File('$outDir/holdout_ud_tr_rows.tsv').writeAsStringSync(dump.toString());
  }, timeout: const Timeout(Duration(minutes: 30)));
}

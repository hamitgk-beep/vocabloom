// Measurement of the text pipeline against human annotation: sentence
// boundaries, word positions, base forms, parts of speech and expressions
// that cross a sentence end.
//
// The data is not in the repository (GUM's fiction is CC BY-NC-SA): make it
// with tools/eval/build_text_eval.py and point $TEXT_EVAL_DIR at the folder.
// text_eval_dev.jsonl is for development; text_eval_test.jsonl is measured
// and never tuned on. $TEXT_EVAL_SET picks one ("dev", the default, or
// "test"); $TEXT_EVAL_OUT gets every miss, to read ($TEXT_EVAL_ALLPOS: also
// every right part of speech, with the rule that chose it, for error rates).
//
// It prints numbers and checks none of them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

String _pc(int a, int b) => b == 0 ? '-' : '${(100 * a / b).toStringAsFixed(1)}%';

void main() {
  test('sentences, word positions, base forms and parts of speech (GUM)', () {
    final dir = Platform.environment['TEXT_EVAL_DIR'];
    final set = Platform.environment['TEXT_EVAL_SET'] ?? 'dev';
    if (dir == null || !File('$dir/text_eval_$set.jsonl').existsSync()) return;
    final every = int.tryParse(Platform.environment['TEXT_EVAL_EVERY'] ?? '') ?? (set == 'dev' ? 5 : 1);
    final all = File('$dir/text_eval_$set.jsonl').readAsLinesSync();
    final rows = [for (var i = 0; i < all.length; i += every) jsonDecode(all[i]) as Map];
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final eng = SenseEngine(d);
    final miss = StringBuffer();
    final allPos = Platform.environment['TEXT_EVAL_ALLPOS'] != null;

    var goldB = 0, predB = 0, hitB = 0, goldS = 0, exactS = 0, parasMulti = 0, parasRight = 0;
    var words = 0, wordsFound = 0;
    var lemN = 0, lemOk = 0, ctxN = 0, ctxOk = 0;
    var posN = 0, posShown = 0, posOk = 0, posSureWrong = 0, posSure = 0;
    final posBy = <String, List<int>>{};
    var cross = 0, matches = 0;
    const want = {'NOUN': 'n', 'VERB': 'v', 'ADJ': 'a', 'ADV': 'r'};

    for (final r in rows) {
      final text = r['text'] as String;
      final sents = [for (final s in r['sents'] as List) ((s as List)[0] as int, s[1] as int)];
      // 1. Sentence boundaries: where a sentence starts (not the first).
      final gold = {for (final s in sents.skip(1)) s.$1};
      final ranges = sentenceRanges(text);
      int lead(int s, int e) {
        while (s < e && text[s].trim().isEmpty) {
          s++;
        }
        return s;
      }

      final pred = {for (final x in ranges.skip(1)) lead(x.$1, x.$2)};
      goldB += gold.length;
      predB += pred.length;
      hitB += gold.intersection(pred).length;
      final predSpans = {for (final x in ranges) '${lead(x.$1, x.$2)}-${text.substring(0, x.$2).trimRight().length}'};
      goldS += sents.length;
      var okAll = true;
      for (final s in sents) {
        if (predSpans.contains('${s.$1}-${s.$2}')) {
          exactS++;
        } else {
          okAll = false;
        }
      }
      if (sents.length > 1) {
        parasMulti++;
        if (okAll && ranges.length == sents.length) parasRight++;
      }
      if (!okAll || ranges.length != sents.length) {
        miss.writeln('SPLIT\t${r['genre']}\tgold ${sents.map((s) => text.substring(s.$1, s.$2)).join(' ¦ ')}\n\tpred ${ranges.map((x) => text.substring(x.$1, x.$2).trim()).join(' ¦ ')}');
      }

      // 2. Word positions: every written word is one token at the same place.
      final toks = tokenize(text);
      final at = {for (var i = 0; i < toks.length; i++) toks[i].start: i};
      final ms = d.matcher.match(toks, text: text);
      int sentOf(int off) => sents.indexWhere((s) => off >= s.$1 && off < s.$2);
      for (final m in ms) {
        if (m.tokens.length < 2) continue;
        matches++;
        final a = sentOf(toks[m.tokens.first].start), b = sentOf(toks[m.tokens.last].start);
        if (a != b) {
          cross++;
          miss.writeln('CROSS\t${m.expr.phrase}\t${text.substring(toks[m.tokens.first].start, toks[m.tokens.last].end)}');
        }
      }
      for (final t in r['toks'] as List) {
        final s = (t as List)[0] as int, e = t[1] as int, form = t[2] as String, lemma = (t[3] as String).toLowerCase(), upos = t[4] as String;
        if (!RegExp(r'[A-Za-z]').hasMatch(form) || upos == 'PUNCT' || upos == 'SYM' || upos == 'NUM' || upos == 'X') continue;
        words++;
        final ti = at[s];
        final same = ti != null && toks[ti].end == e;
        if (same) wordsFound++;
        if (!same) {
          miss.writeln('TOKEN\t$form\t${ti == null ? '-' : toks[ti].text}');
          continue;
        }
        final w = want[upos];
        if (w == null) continue;
        // 3. Base form.
        final lower = toks[ti].lower;
        if (RegExp(r"^[a-z]+$").hasMatch(lower)) {
          lemN++;
          final l = eng.lemmaOf(lower);
          if (l == lemma) {
            lemOk++;
          } else {
            miss.writeln('LEMMA\t$form\t$upos\tgold $lemma\tgot $l');
          }
        }
        // 4. Part of speech of the meaning shown, as the panel asks for it:
        // the word in its sentence, by the app's own sentence boundaries.
        final sr = ranges.firstWhere((x) => s >= x.$1 && s < x.$2, orElse: () => (0, text.length));
        final st = [for (final x in toks) if (x.start >= sr.$1 && x.end <= sr.$2) x];
        final si = st.indexWhere((x) => x.start == s);
        if (si < 0) continue;
        final c = eng.resolve(SenseQuery(sentence: text.substring(sr.$1, sr.$2).trim(), tokens: st, index: si));
        if (c.cat != null) continue; // read as part of an expression
        // The base form of the meaning shown in the sentence (the dictionary
        // word alone when no meaning is shown).
        if (RegExp(r"^[a-z]+$").hasMatch(lower)) {
          ctxN++;
          final l = c.shown ? c.best!.lemma : eng.lemmaOf(lower);
          if (l == lemma) {
            ctxOk++;
          } else {
            miss.writeln('CTXLEMMA\t$form\t$upos\tgold $lemma\tgot $l\t${text.substring(sr.$1, sr.$2).trim()}');
          }
        }
        if (d.posOf(lower).length < 2) continue;
        posN++;
        final by = posBy.putIfAbsent(upos, () => [0, 0, 0]);
        by[0]++;
        if (!c.shown || c.best!.pos == null) continue;
        posShown++;
        by[1]++;
        final ok = c.best!.pos == w;
        if (ok) {
          posOk++;
          by[2]++;
        }
        if (c.confidence == SenseConfidence.sure) {
          posSure++;
          if (!ok) posSureWrong++;
        }
        if (ok && allPos) miss.writeln('POSOK\t$form\tgold $upos\tgot ${c.best!.pos} ${c.confidence.name}\t${text.substring(sr.$1, sr.$2).trim()}\t${c.reason}');
        if (!ok) {
          miss.writeln('POS\t$form\tgold $upos\tgot ${c.best!.pos} ${c.confidence.name}\t${text.substring(sr.$1, sr.$2).trim()}\t${c.reason} | ${c.ranked.take(3).map((x) => '${x.lemma}/${x.pos} ${x.score.toStringAsFixed(2)} ${x.parts.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}').join(' ; ')}');
        }
      }
    }
    final p = hitB / (predB == 0 ? 1 : predB), rc = hitB / (goldB == 0 ? 1 : goldB);
    final out = StringBuffer()
      ..writeln('GUM $set: ${rows.length} paragraphs (every ${every}th of ${all.length}), $goldS sentences, $words words')
      ..writeln('Sentence boundaries: gold $goldB, found $predB, right $hitB | precision ${_pc(hitB, predB)} recall ${_pc(hitB, goldB)} F1 ${(p + rc == 0 ? 0 : 200 * p * rc / (p + rc)).toStringAsFixed(1)}')
      ..writeln('Sentences exactly right: $exactS/$goldS (${_pc(exactS, goldS)}); paragraphs of 2+ sentences fully right: $parasRight/$parasMulti (${_pc(parasRight, parasMulti)})')
      ..writeln('Word positions: $wordsFound/$words (${_pc(wordsFound, words)}) written words are one token at the same place')
      ..writeln('Base form (nouns, verbs, adjectives, adverbs): the word alone $lemOk/$lemN (${_pc(lemOk, lemN)}); of the meaning shown in the sentence $ctxOk/$ctxN (${_pc(ctxOk, ctxN)})')
      ..writeln('Part of speech of the meaning shown, words with 2+ parts of speech: asked $posN, shown $posShown (${_pc(posShown, posN)}), right $posOk (${_pc(posOk, posShown)} of shown); "sure" $posSure, of them wrong $posSureWrong (${_pc(posSureWrong, posSure)})')
      ..writeln('  by gold part of speech [asked, shown, right]: $posBy')
      ..writeln('Expressions of 2+ words: $matches, crossing a sentence end: $cross');
    // ignore: avoid_print
    print(out);
    final dump = Platform.environment['TEXT_EVAL_OUT'];
    if (dump != null) File(dump).writeAsStringSync('$out\n$miss');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

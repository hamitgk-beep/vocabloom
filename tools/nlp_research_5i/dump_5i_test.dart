// Task 5I: what the SenseEngine says on a set, one JSON line per row; checks nothing.
// Run from the repository root:
//
//   NLP_5I_SETS=dev=/path/dev5h_magpie.tsv NLP_5I_OUT=/path/out NLP_5I_MODE=base|rec|head|both \
//   flutter test tools/nlp_research_5i/dump_5i_test.dart
//
// base: the 5H engine (literal cues and guard on). rec: + SenseEngine.idiomRecovery. head: +
// SenseEngine.headFromPattern. both: both. Set formats as in tools/nlp_research_5h.
// Adapted from tools/nlp_research_5h/dump_5h_test.dart (variants left out: they stay off).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

const _pron = {'my', 'your', 'his', 'her', 'its', 'our', 'their'};

/// The variant class of a match the wider matcher found: possessive-pronoun
/// ("his" for "someone's"), possessive-name ("Oliver's"), possessive-noun
/// ("the company's"), insertion-adj/adv/ing/ed/other, or several joined by "+".
String variantClass(Match m, List<Token> toks) {
  final out = <String>[];
  final pat = m.expr.pattern;
  final kinds = (m.variant ?? '').split('+');
  if (kinds.contains('possessive')) {
    for (final i in m.tokens) {
      final t = toks[i];
      if (_pron.contains(t.lower) && pat.contains("someone's")) out.add('possessive-pronoun');
      if ((t.lower.endsWith("'s") || t.lower.endsWith('’s')) && t.lower.length > 3 && !pat.contains(t.lower)) {
        out.add(t.text[0] != t.text[0].toLowerCase() ? 'possessive-name' : 'possessive-noun');
      }
    }
  }
  if (kinds.contains('insertion')) {
    for (var k = 1; k < m.tokens.length; k++) {
      if (m.tokens[k] - m.tokens[k - 1] == 2) {
        final w = toks[m.tokens[k] - 1].lower;
        out.add('insertion-${w.endsWith('ing') ? 'ing' : w.endsWith('ed') ? 'ed' : w.endsWith('ly') ? 'ly' : 'other'}');
      }
    }
  }
  return out.isEmpty ? (m.variant ?? 'other') : out.toSet().join('+');
}

void main() {
  final sets = Platform.environment['NLP_5I_SETS'];
  final out = Platform.environment['NLP_5I_OUT'];
  final mode = Platform.environment['NLP_5I_MODE'] ?? 'base';
  if (sets == null || out == null) return;
  test('dump', () {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    Directory(out).createSync(recursive: true);
    for (final spec in sets.split(',')) {
      final name = spec.substring(0, spec.indexOf('='));
      final path = spec.substring(spec.indexOf('=') + 1);
      final rec = mode == 'rec' || mode == 'both', head = mode == 'head' || mode == 'both';
      final eng = SenseEngine(d, literalCues: true, literalGuard: true, idiomRecovery: rec, headFromPattern: head);
      final wordEng = SenseEngine(d, literalCues: true, literalGuard: true);
      final sink = StringBuffer();
      final sw = Stopwatch();
      var n = 0;
      for (final l in File(path).readAsLinesSync()) {
        if (l.startsWith('#') || l.trim().isEmpty) continue;
        final p = l.split('\t');
        final claude = p[0] == 'dev' || p[0] == 'final';
        final phrase = claude ? p[1] : p[0];
        final gold = claude ? p[2] : (p[1] == 'i' ? 'idiom' : 'literal');
        final s = p[4];
        final row = <String, Object?>{
          'set': name,
          'part': claude ? p[0] : name,
          'phrase': phrase,
          'gold': gold,
          'case': claude ? p[3] : p[5],
          'id': claude ? '' : p[3],
          'sentence': s,
        };
        final toks = tokenize(s);
        final plain = d.matcher.match(toks, text: s).where((m) => m.expr.phrase == phrase).toList();
        final ms = plain;
        row['found'] = ms.isNotEmpty;
        row['foundPlain'] = plain.isNotEmpty;
        if (ms.isNotEmpty) {
          final m = ms.first;
          row['idx'] = m.tokens;
          row['variant'] = m.variant == null ? null : variantClass(m, toks);
          sw.start();
          final c = eng.resolve(SenseQuery(sentence: s, tokens: toks, index: m.tokens.first, expr: m.expr, exprTokens: m.tokens));
          sw.stop();
          n++;
          final b = c.best;
          final headI = m.tokens.firstWhere((i) => !stopWords.contains(toks[i].lower), orElse: () => m.tokens.first);
          row.addAll({
            'cat': m.expr.cat,
            'conf': c.confidence.name,
            'asIdiom': c.cat != null && c.literalPhrase == null && c.shown,
            'literal': c.literalPhrase != null,
            'shown': c.shown,
            'tr': c.tr,
            'gap': c.gap?.name,
            'reason': c.reason,
            'head': toks[headI].lower,
            'best': b?.id,
            'bestLemma': b?.lemma,
            'bestSrc': b?.source,
            'bestEn': b?.en != null && b!.en!.isNotEmpty,
            'bestDraft': b?.unverified,
            'bestDerived': b?.trDerived,
            'litCands': c.ranked.where((x) => x.literal).length,
            'litCandsTr': c.ranked.where((x) => x.literal && x.tr.isNotEmpty).length,
            'litCandsCheckedTr': c.ranked.where((x) => x.literal && x.tr.isNotEmpty && !x.unverified).length,
            'idiomTr': c.ranked.where((x) => !x.literal && x.tr.isNotEmpty && !x.unverified).length,
            'idiomDraftTr': c.ranked.where((x) => !x.literal && x.tr.isNotEmpty && x.unverified).length,
            'sI': c.ranked.where((x) => !x.literal).firstOrNull?.score,
            'sL': c.ranked.where((x) => x.literal).firstOrNull?.score,
            'bestLit': c.ranked.where((x) => x.literal).firstOrNull?.lemma,
          });
          // The word panel when the learner taps the head word (ContextSenseCard.resolve).
          final tap = eng.resolveTap(SenseQuery(sentence: s, tokens: toks, index: headI), plain.isEmpty ? ms : d.matcher.match(toks, text: s));
          row['tap'] = {
            'shown': tap.shown, 'conf': tap.confidence.name, 'tr': tap.tr, 'literal': tap.literalPhrase != null,
            'draft': tap.best?.unverified, 'derived': tap.best?.trDerived, 'gap': tap.gap?.name, 'cat': tap.cat,
          };
          // The head word tapped alone (the word panel), for the empty-panel diagnosis.
          final wq = SenseQuery(sentence: s, tokens: toks, index: headI);
          final wr = wordEng.resolve(wq);
          row['word'] = {'shown': wr.shown, 'conf': wr.confidence.name, 'tr': wr.tr, 'cat': wr.cat, 'lemma': wr.best?.lemma, 'draft': wr.best?.unverified, 'gap': wr.gap?.name};
        }
        final e = d.exprs.where((x) => x.phrase == phrase).firstOrNull;
        if (e?.tr != null) {
          final f = eng.fit(phrase, s, e!.tr!);
          row['fit'] = f.fit.name;
          row['fitWhy'] = f.why;
        }
        // The word card: does the head word's own Turkish (first main meaning) get confirmed?
        if (ms.isNotEmpty) {
          final hw = row['head'] as String;
          final lem = eng.lemmaOf(hw);
          final ft = eng.mainTr(lem);
          if (ft.isNotEmpty) {
            final f = eng.fit(lem, s, ft.first.split(',').first.trim());
            row['wfit'] = f.fit.name;
          }
        }
        sink.writeln(jsonEncode(row));
      }
      File('$out/$name.jsonl').writeAsStringSync(sink.toString());
      // ignore: avoid_print
      print('$name: $n resolved, ${(sw.elapsedMicroseconds / (n == 0 ? 1 : n) / 1000).toStringAsFixed(3)} ms each');
    }
  });
}

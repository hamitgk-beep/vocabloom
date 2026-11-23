// Task 5M: sentence parse + syntactic templates + unit scorer (lib/nlp/construction.dart), OFF by default.
// The sentences were written by Claude as regression cases (not human labels); the measurement is in
// docs/nlp_engine_research/SENTENCE_PARSER_TEMPLATES_5M.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/construction.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/nlp/unit_weights_5m.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:sqlite3/sqlite3.dart';

late DictDb d;
late AppState app;

/// Expression phrase -> its underlined words, for every token the reader underlines.
Map<String, String> shown(String s, {required bool on}) {
  sentenceAnalyzer5m = on;
  try {
    final a = analyze(app, s);
    final out = <String, String>{};
    for (var i = 0; i < a.tokens.length; i++) {
      final m = a.expressionsAt(app, i).firstOrNull;
      if (m != null) out[m.expr.phrase] = m.tokens.map((k) => a.tokens[k].text).join(' ');
    }
    return out;
  } finally {
    sentenceAnalyzer5m = false;
  }
}

void main() {
  setUpAll(() {
    d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_5m'));
    app = AppState(d, u)..localAi = KeyAi(u);
    app.enabledCats.addAll(categories.map((c) => c.id));
  });

  test('off by default, and off means the reader of 5L', () {
    expect(sentenceAnalyzer5m, isFalse);
    expect(shown("Don't waste your time on that shop.", on: false)["waste one's time"], 'waste your time');
    expect(shown('The TV was on all night.', on: false)['be on'], 'was on');
  });

  test('the parse: parts of speech and noun phrases', () {
    const s = 'Please turn the kitchen light off.';
    final p = ConstructionParser(d).parse(s, tokenize(s));
    expect(p.tags[2], Tag.det);
    expect(p.npEnd[2], 5); // "the kitchen light"
    expect(p.toks[p.npHead[2]].text, 'light');
  });

  test('a possessive slot is not a word of the expression', () {
    expect(shown("Don't waste your time on that shop.", on: true)["waste one's time"], 'waste time');
    expect(shown('He changed his mind again.', on: true)["change one's mind"], 'changed mind');
  });

  test('idioms are frozen: the written determiner, no extra modifier', () {
    expect(shown('That name rings a bell.', on: true)['ring a bell'], 'rings a bell');
    expect(shown('Be sure to ring the little bell.', on: true).containsKey('ring a bell'), isFalse);
  });

  test('a template keeps the dictionary words and adds the parse variants', () {
    final c = TemplateCompiler(d);
    final waste = d.exprs.firstWhere((e) => e.phrase == "waste one's time");
    final t = c.compile(waste)!;
    expect(t.parts.first, isA<Lex>());
    expect((t.parts[1] as NounPhrase).head, 'time');
    expect((t.parts[1] as NounPhrase).det, 'poss');
    // a sequence-only expression gets no template (the sequence matcher is exact for it)
    expect(c.compile(d.exprs.firstWhere((e) => e.phrase == 'on hand')), isNull);
  });

  test('5L regression sentences keep their reading with the analyzer on', () {
    final blacky = shown('Blacky the Crow was on hand promptly that afternoon.', on: true);
    expect(blacky['on hand'], 'on hand');
    expect(blacky.containsKey('be on'), isFalse);
    expect(shown('The prisoner was on the run for three weeks.', on: true)['on the run'], 'on the run');
    expect(shown('Hot air rises and cold air sinks.', on: true)['hot air'], 'Hot air');
  });

  test('known trade-off: the unit scorer hides "be on" in "The TV was on all night"', () {
    // Measured: human annotators of STREUSLE, DiMSUM and PARSEME never mark be + particle as one unit, so the
    // scorer learnt to hide it; the 5L reader shows "be on" (sure) here. Kept visible in the report.
    expect(shown('The TV was on all night.', on: true).containsKey('be on'), isFalse);
  });

  test('the unit scorer is a probability and reads the context engine', () {
    const s = 'We need to go back home now.';
    final toks = tokenize(s);
    final p = ConstructionParser(d).parse(s, toks);
    final e = d.exprs.firstWhere((e) => e.phrase == 'go back');
    final sure = unitScorer5m.score(unitFeatures(p, e, [3, 4], conf: 'sure'));
    final none = unitScorer5m.score(unitFeatures(p, e, [3, 4], conf: 'none'));
    expect(sure, inInclusiveRange(0, 1));
    expect(none, inInclusiveRange(0, 1));
    expect(sure, isNot(none));
  });
}

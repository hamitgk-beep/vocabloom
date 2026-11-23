// Task 5L: "be" + particle with its own noun phrase is read word by word
// (SenseEngine.defaultOverlap = OverlapRules(copulaObject: true)), so the
// underline, the panel and card grading agree, and "on hand" keeps its "on".
// The sentences here were written by Claude as regression cases (not human
// labels); the measurement is in
// docs/nlp_engine_research/EXPRESSION_OVERLAP_RESOLVER_5L.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/overlap_rules.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:sqlite3/sqlite3.dart';

late DictDb d;
late SenseEngine on, off;
late AppState app;

const blacky = 'Blacky the Crow was on hand promptly that afternoon.';
const bridge = 'He was on the bridge.';
const tv = 'The TV was on all night.';
const run = 'The prisoner was on the run for three weeks.';
const hot = 'Hot air rises and cold air sinks.';

ContextSense read(SenseEngine e, String s, String phrase) {
  final q = SenseQuery.find(d, s, phrase);
  expect(q.expr, isNotNull, reason: '$phrase in "$s"');
  return e.resolve(q);
}

bool hidden(SenseEngine e, String s, String phrase) {
  final q = SenseQuery.find(d, s, phrase);
  return e.isLiteral(q.expr!, q.tokens, q.exprTokens, sentence: s);
}

/// What the reader underlines and opens on [word] (with every expression filter on).
String? underlined(String s, String word) {
  final a = analyze(app, s);
  final i = a.tokens.indexWhere((t) => t.lower == word);
  return a.expressionsAt(app, i).firstOrNull?.expr.phrase;
}

void main() {
  setUpAll(() {
    d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    on = SenseEngine(d);
    off = SenseEngine(d, overlap: OverlapRules.none);
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_5l'));
    app = AppState(d, u)..localAi = KeyAi(u);
    app.enabledCats.addAll(categories.map((c) => c.id));
  });

  test('the default is the measured rule only', () {
    expect(SenseEngine.defaultOverlap.copulaObject, isTrue);
    expect(SenseEngine.defaultOverlap.senseFrame || SenseEngine.defaultOverlap.prepPhraseTakesParticle, isFalse);
    expect(SenseEngine.defaultOverlap.sharedNotSure || SenseEngine.defaultOverlap.copulaNeverSure, isFalse);
    final q = SenseQuery.find(d, blacky, 'be on');
    expect(on.cacheKey(q), isNot(off.cacheKey(q)), reason: 'a reading of the other engine is never reused');
  });

  test('"was on hand": be on is read word by word, on hand keeps its "on"', () {
    expect(off.resolve(SenseQuery.find(d, blacky, 'be on')).confidence, SenseConfidence.sure, reason: 'the 5K engine (the bug)');
    final r = read(on, blacky, 'be on');
    expect(r.literalPhrase, 'be on');
    expect(r.confidence, isNot(SenseConfidence.sure));
    expect(r.tr ?? '', isNot(contains('yayında')));
    expect(hidden(on, blacky, 'be on'), isTrue);
    expect(underlined(blacky, 'on'), 'on hand');
    expect(underlined(blacky, 'hand'), 'on hand');
    expect(underlined(blacky, 'was'), isNot('be on'), reason: 'only the irregular verb "be" may stay');
    final h = read(on, blacky, 'on hand');
    expect(h.cat, 'prepositional_phrases');
    expect(h.tr, contains('hazırda'));
  });

  test('"was on the bridge": no expression underlined, no "sure" meaning', () {
    expect(hidden(off, bridge, 'be on'), isFalse);
    expect(hidden(on, bridge, 'be on'), isTrue);
    expect(underlined(bridge, 'was'), isNot('be on'));
    expect(underlined(bridge, 'on'), isNull);
    expect(read(on, bridge, 'be on').confidence, isNot(SenseConfidence.sure));
  });

  test('"The TV was on all night": be on is still offered, as before', () {
    final a = read(off, tv, 'be on'), b = read(on, tv, 'be on');
    expect(b.literalPhrase, isNull);
    expect(b.confidence, a.confidence);
    expect(b.tr, a.tr);
    expect(underlined(tv, 'on'), 'be on');
  });

  test('time phrases, stranded particles and objects the dictionary allows', () {
    for (final s in ['The game is on tonight.', 'All the lights were on.', 'Is the party still on?', 'The film is on at the local cinema.']) {
      expect(hidden(on, s, 'be on'), isFalse, reason: s);
    }
    for (final s in ['Dinner was on the table.', 'The meeting is on Monday.', 'He was on the phone all night.']) {
      expect(hidden(on, s, 'be on'), isTrue, reason: s);
    }
    // "be after" has no checked examples without an object: never touched.
    expect(hidden(on, 'The police are after the thief.', 'be after'), isFalse);
  });

  test('5I/5H readings of "on the run" and "hot air" do not change', () {
    for (final (s, p) in [(run, 'on the run'), (hot, 'hot air'), ('The prisoner was on the run.', 'on the run')]) {
      final a = read(off, s, p), b = read(on, s, p);
      expect(b.confidence, a.confidence, reason: s);
      expect(b.tr, a.tr, reason: s);
      expect(b.literalPhrase, a.literalPhrase, reason: s);
      expect(b.gap, a.gap, reason: s);
    }
    expect(underlined(run, 'run'), 'on the run');
  });

  test('cards: be on is not graded in "was on hand"; elsewhere grading is as before', () {
    final tr = d.exprs.firstWhere((e) => e.phrase == 'be on').tr!;
    expect(on.fit('be on', blacky, tr).confirmed, isFalse);
    expect(on.fit('be on', bridge, tr).confirmed, isFalse);
    for (final s in [tv, run, hot]) {
      for (final w in ['on', 'run', 'air', 'night']) {
        expect(on.fit(w, s, 'x').fit, off.fit(w, s, 'x').fit, reason: '$w in $s');
      }
    }
    expect(on.fit('be on', tv, tr).fit, off.fit('be on', tv, tr).fit);
  });

  test('word panel: tapping "on" is about "on", not the verb read word by word', () {
    for (final s in [bridge, blacky]) {
      final toks = tokenize(s);
      final i = toks.indexWhere((t) => t.lower == 'on');
      final r = on.resolveTap(SenseQuery(sentence: s, tokens: toks, index: i), d.matcher.match(toks));
      expect(r.headword, isNot('be'), reason: s);
      expect(r.tr ?? '', isNot(contains('olmak')), reason: s);
    }
    final toks = tokenize(bridge);
    final r = on.resolveTap(SenseQuery(sentence: bridge, tokens: toks, index: 1), d.matcher.match(toks));
    expect(r.literalPhrase, 'be on', reason: 'tapping "was" still says the words are meant one by one');
  });

  test('helpers: noun phrase and time phrase after the particle', () {
    final t = tokenize('He was on the bridge all night.');
    expect(npStartsAt(d, t, 3, clauseBreaks('He was on the bridge all night.', t)), isTrue);
    expect(timePhraseAt(t, 5), isTrue);
    final u = tokenize('The TV was on, so we stayed.');
    expect(particleHasObject(d, u, 3, clauseBreaks('The TV was on, so we stayed.', u)), isFalse);
    expect(OverlapRules.parse('A+B').key, 'AB');
  });
}

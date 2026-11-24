// Task 6A: checked readings of the bundled stories (lib/nlp/verified_readings.dart) and the person-noun fix.
//
// The sentences "The dog sees a bird." and "The fat king has a thin dog." are from a bundled CC BY 4.0 story
// (assets/library/stories.json.gz); "The boy kicked the bucket across the yard." was written for the 5N tests.
// The overlays below are written by hand for the tests; they are not the audit's answers.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/nlp/verified_readings.dart';
import 'package:sqlite3/sqlite3.dart';

VerifiedReadings overlay(Map<String, Object?> s) => VerifiedReadings.fromBytes(gzip.encode(utf8.encode(jsonEncode({'v': 1, 's': s}))));

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();

  ContextSense word(SenseEngine e, String s, String w) {
    final t = tokenize(s);
    return e.resolve(SenseQuery(sentence: s, tokens: t, index: t.indexWhere((x) => x.text == w)));
  }

  test('a checked meaning is the answer, sure when its Turkish is written for it', () {
    const s = 'The dog sees a bird.';
    final e = SenseEngine(d);
    final before = word(e, s, 'sees');
    final see = before.ranked.firstWhere((c) => c.en != null && c.en!.startsWith('perceive by sight') && c.tr.isNotEmpty);
    e.verified = overlay({s: {'w': {'2': see.id}}});
    final after = word(e, s, 'sees');
    expect(after.best!.id, see.id);
    expect(after.tr, see.trShown);
    expect(after.confidence, see.trDerived || see.unverified ? SenseConfidence.likely : SenseConfidence.sure);
    expect(after.reason, startsWith('checked 6A'));
    // other words and other sentences are untouched
    expect(word(e, s, 'bird').reason, isNot(startsWith('checked')));
    expect(word(e, 'The cat sees a bird.', 'sees').reason, isNot(startsWith('checked')));
  });

  test('"no dictionary meaning fits" shows no meaning; an id the engine did not consider changes nothing', () {
    const s = 'The dog sees a bird.';
    final e = SenseEngine(d)..verified = overlay({s: {'w': {'2': '-', '4': 'wn:0'}}});
    final r = word(e, s, 'sees');
    expect(r.shown, isFalse);
    expect(r.tr, isNull);
    final plain = word(SenseEngine(d), s, 'bird');
    expect(word(e, s, 'bird').tr, plain.tr);
  });

  test('an expression checked as separate words is literal and not the tap answer', () {
    const s = 'The boy kicked the bucket across the yard.';
    final t = tokenize(s);
    final m = d.matcher.match(t, text: s).firstWhere((m) => m.expr.phrase == 'kick the bucket');
    final key = '${m.expr.phrase}|${m.expr.cat}|${m.tokens.join(',')}';
    final e = SenseEngine(d)..verified = overlay({s: {'e': {key: 0}}});
    expect(e.isLiteral(m.expr, t, m.tokens, sentence: s), isTrue);
    expect(e.verifiedUnit(s, m.expr, m.tokens), isFalse);
    final tap = e.resolveTap(SenseQuery(sentence: s, tokens: t, index: m.tokens.first), [m]);
    expect(tap.cat, isNull);
    expect(tap.literalPhrase, isNull);
    final on = SenseEngine(d)..verified = overlay({s: {'e': {key: 1}}});
    expect(on.isLiteral(m.expr, t, m.tokens, sentence: s), isFalse);
  });

  test('a broken or missing file means no checked readings', () {
    expect(() => VerifiedReadings.fromBytes([1, 2, 3]), throwsA(anything));
    expect(SenseEngine(d).verified, isNull);
  });

  test('person nouns have meanings; pronouns stay grammar words', () {
    final e = SenseEngine(d);
    final king = word(e, 'The fat king has a thin dog.', 'king');
    expect(king.reason, isNot('grammar word'));
    expect(king.shown, isTrue);
    for (final (s, w) in [('The boy runs.', 'boy'), ('The baby sleeps.', 'baby'), ('A man came in.', 'man')]) {
      expect(word(e, s, w).reason, isNot('grammar word'), reason: w);
    }
    expect(word(e, 'He has a thin dog.', 'He').reason, 'grammar word');
  });

  test('the meaning cache keeps a reader sentence and the same sentence tokenized alone apart', () {
    // "the" in the paragraph starts at the same number as "old" in the sentence alone.
    const s = 'This time, the villagers were waiting for the stupid old man to arrive.';
    final gap = s.indexOf('old') - s.indexOf('the villagers');
    final p = 'Hi.${' ' * (gap - 3)}$s';
    final e = SenseEngine(d);
    final alone = tokenize(s);
    final old = e.resolve(SenseQuery(sentence: s, tokens: alone, index: alone.indexWhere((t) => t.text == 'old')));
    expect(old.headword, 'old');
    final ptoks = tokenize(p);
    final ti = ptoks.indexWhere((t) => t.text == 'the');
    final at = sentenceAt(p, ptoks, ti);
    expect(at.text, s);
    expect(at.tokens[ti - at.first].start, alone.firstWhere((t) => t.text == 'old').start);
    final the = e.resolve(SenseQuery(sentence: at.text, tokens: at.tokens, index: ti - at.first));
    expect(the.headword, 'the');
    // the same word read both ways is one cache entry
    final villagers = e.resolve(SenseQuery(sentence: at.text, tokens: at.tokens, index: ti - at.first + 1));
    final n = e.computed;
    e.resolve(SenseQuery(sentence: s, tokens: alone, index: alone.indexWhere((t) => t.text == 'villagers')));
    expect(e.computed, n);
    expect(villagers.headword, 'villager');
  });

  test('the bundled checked readings load and give "sees" its seeing meaning', () {
    final v = VerifiedReadings.fromBytes(File(VerifiedReadings.asset).readAsBytesSync());
    expect(v.length, greaterThan(8000));
    final e = SenseEngine(d)..verified = v;
    final r = word(e, 'The dog sees a bird.', 'sees');
    expect(r.tr, contains('görmek'));
    expect(r.confidence, SenseConfidence.sure);
  });
}

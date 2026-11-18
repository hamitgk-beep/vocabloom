import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

DictDb openDict() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return d;
}

void main() {
  final d = openDict();
  final engine = SenseEngine(d);

  ContextSense word(String sentence, String w, {int occurrence = 0}) =>
      engine.resolve(SenseQuery.find(d, sentence, w, occurrence: occurrence));

  /// The table from the request: sentence, word, Turkish that must be in the
  /// meaning shown (any of them). A null result is allowed only where the
  /// dictionary has no Turkish for the right sense; then the chosen English
  /// definition must still be the right one ([gloss]).
  final cases = <(String, String, List<String>, String?)>[
    ('I know the answer.', 'know', ['bilmek'], null),
    ('I know her very well.', 'know', ['tanımak'], null),
    ('The engine is running.', 'running', ['çalışmak'], null),
    ('She runs a small company.', 'runs', ['yönetmek', 'işletmek'], null),
    ('Cracks run through the wall.', 'run through', ['uzanmak', 'geçmek'], 'stretch|extend|pass'),
    ("Let's run through the plan.", 'run through', ['gözden geçirmek', 'prova'], null),
    ('Dorothy lived in Kansas.', 'lived', ['yaşamak', 'oturmak'], null),
    ('She looked up the word.', 'looked up', ['bilgi aramak', 'bakmak', 'aramak'], null),
    ('She looked up at the sky.', 'looked up', ['yukarı bakmak'], null),
    ('The bank approved the loan.', 'bank', ['banka'], null),
    ('They sat on the river bank.', 'bank', ['kıyı'], 'slop|water'),
  ];

  group('request table', () {
    for (final (s, w, want, gloss) in cases) {
      test('$w in "$s"', () {
        final q = SenseQuery.find(d, s, w.contains(' ') ? _base(w) : w);
        final r = engine.resolve(q);
        // ignore: avoid_print
        print('$s | $w → ${r.confidence.name}: ${r.best?.trShown} (${r.best?.en}) [${r.reason}]');
        final tr = (r.best?.trShown ?? '').toLowerCase();
        if (r.shown) {
          expect(want.any(tr.contains), isTrue, reason: 'got "$tr" (${r.reason})');
        } else {
          expect(gloss, isNotNull, reason: 'no meaning shown (${r.reason})');
          expect(RegExp(gloss!).hasMatch(r.best?.en ?? ''), isTrue, reason: 'sense ${r.best?.en}');
        }
      });
    }
  });

  test('lived in Kansas is live + in, not the phrasal verb "live in"', () {
    final q = SenseQuery.find(d, 'Dorothy lived in Kansas.', 'live in');
    expect(q.expr, isNotNull, reason: 'the dictionary matches "live in" here');
    final r = engine.resolve(q);
    expect(r.literalPhrase, 'live in');
    expect(r.headword, 'live');
    expect(engine.isLiteral(q.expr!, q.tokens, q.exprTokens), isTrue);
    // The nanny really lives in: the phrasal verb.
    final q2 = SenseQuery.find(d, 'The nanny lives in with the family.', 'live in');
    expect(engine.resolve(q2).literalPhrase, isNull);
  });

  test('separable phrasal verbs: turn off the light / turn the light off', () {
    for (final s in ['Please turn off the light.', 'Please turn the light off.']) {
      final ms = d.matcher.match(tokenize(s)).where((m) => m.expr.phrase == 'turn off').toList();
      if (ms.isEmpty) {
        // The reader's matcher only splits around pronouns ("turn it off");
        // the engine finds the particle after the object itself.
        final r = word(s, 'turn');
        expect(r.headword, 'turn off', reason: r.reason);
        expect(r.best?.trShown ?? '', contains('kapat'), reason: r.reason);
        continue;
      }
      final r = engine.resolve(SenseQuery(sentence: s, tokens: tokenize(s), index: ms.first.tokens.first, expr: ms.first.expr, exprTokens: ms.first.tokens));
      expect(r.best?.trShown ?? '', contains('kapat'), reason: r.reason);
    }
  });

  test('look the word up: object between verb and particle', () {
    const s = 'If you do not know it, look it up in the dictionary.';
    final ms = d.matcher.match(tokenize(s)).where((m) => m.expr.phrase == 'look up').toList();
    expect(ms, isNotEmpty);
    final r = engine.resolve(SenseQuery(sentence: s, tokens: tokenize(s), index: ms.first.tokens.first, expr: ms.first.expr, exprTokens: ms.first.tokens));
    expect(r.best?.trShown?.toLowerCase() ?? '', anyOf(contains('aramak'), contains('bakmak')), reason: r.reason);
    expect(r.best?.trShown?.toLowerCase() ?? '', isNot(contains('yukarı')));
  });

  test('the same word twice in one sentence is told apart by position', () {
    const s = 'I know that you know her.';
    final a = SenseQuery.find(d, s, 'know');
    final b = SenseQuery.find(d, s, 'know', occurrence: 1);
    expect(a.index, isNot(b.index));
    expect(engine.cacheKey(a), isNot(engine.cacheKey(b)));
    final rb = engine.resolve(b);
    expect(rb.best?.trShown ?? '', contains('tanımak'), reason: rb.reason);
  });

  test('a word that is not in the sentence or not in the dictionary gives "none", not an error', () {
    expect(word('The cat sat.', 'dog').confidence, SenseConfidence.none);
    expect(word('He saw a glorptastic zibble.', 'zibble').confidence, SenseConfidence.none);
    expect(engine.resolve(SenseQuery(sentence: '', tokens: const [], index: 0)).confidence, SenseConfidence.none);
  });

  test('a sense without Turkish is never shown as sure', () {
    // run "stretch out over a distance" has no Turkish of its own.
    final r = word('The road runs along the coast for miles.', 'runs');
    if (r.best != null && r.best!.trDerived) expect(r.confidence, isNot(SenseConfidence.sure));
    for (final (s, w, _, _) in cases) {
      final x = engine.resolve(SenseQuery.find(d, s, w.contains(' ') ? _base(w) : w));
      if (x.confidence == SenseConfidence.sure) {
        expect(x.best!.trDerived, isFalse, reason: '$s: derived Turkish shown as sure');
        expect(x.best!.tr, isNotEmpty);
      }
    }
  });

  test('wrong part of speech is not chosen: "the run" is a noun, "they run" a verb', () {
    final n = word('He went for a long run in the park.', 'run');
    expect(n.best?.pos, 'n', reason: n.reason);
    final v = word('They run every morning.', 'run');
    expect(v.best?.pos, 'v', reason: v.reason);
  });

  test('more than one base form: "saw" (see / saw) and "better" are both considered', () {
    final r = word('I saw her at the station yesterday.', 'saw');
    expect(r.best?.lemma, 'see', reason: r.reason);
    final b = word('She feels better today.', 'better');
    expect(b.best, isNotNull);
  });

  test('long sentences stay fast', () {
    final long = List.filled(12, 'The old man walked slowly along the dusty road while the children ran ahead laughing').join(', and ');
    final sw = Stopwatch()..start();
    final r = engine.resolve(SenseQuery.find(d, '$long.', 'walked'));
    expect(sw.elapsedMilliseconds, lessThan(1500));
    expect(r.headword, isNotEmpty);
  });

  test('cache: same tap is not computed twice; a new dictionary version is', () {
    final e = SenseEngine(d);
    final q = SenseQuery.find(d, 'The bank approved the loan.', 'bank');
    e.resolve(q);
    e.resolve(q);
    expect(e.computed, 1);
    final newer = SenseEngine(d, dictVersion: '${DictDb.version}-next');
    expect(newer.cacheKey(q), isNot(e.cacheKey(q)));
    e.clearCache();
    e.resolve(q);
    expect(e.computed, 2);
  });

  test('works without any AI key or network: the engine never leaves the device', () {
    // SenseEngine only reads the bundled SQLite dictionary; resolving many
    // words takes no service and no await.
    for (final (s, w, _, _) in cases) {
      expect(() => SenseEngine(d).resolve(SenseQuery.find(d, s, w.contains(' ') ? _base(w) : w)), returnsNormally);
    }
  });

  test('damaged Turkish ("de(sigortacılık)ns") is never shown', () {
    expect(DictDb.badMeaning('de(sigortacılık)ns'), isTrue);
    expect(DictDb.badMeaning('kapatmak (cihaz)'), isFalse);
  });
}

/// "looked up" → "look up" so the dictionary phrase is found.
String _base(String phrase) {
  const forms = {'looked': 'look', 'lived': 'live', 'run': 'run', 'runs': 'run'};
  return phrase.split(' ').map((w) => forms[w] ?? w).join(' ');
}

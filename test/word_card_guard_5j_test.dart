// Task 5J: a word card is not graded alone when the word may be part of an
// expression of its sentence ("run" in "on the run"), unless the
// expression's own Turkish carries the card's answer ("hapis" / "hapiste").
// The sentences here were written by Claude (AI) for these tests; they are not
// human-labelled data and take part in no measurement
// (docs/nlp_engine_research/IDIOM_WORD_CARD_SAFETY_5J.md).
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review.dart';
import 'package:kelime_okur/data/review_quiz.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/nlp/context_sense.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/review_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

const prisoner = 'The prisoner was on the run for three weeks.';
const hotLiteral = 'Hot air rises and cold air sinks.';
const loan = 'The bank approved the loan.';
const gaveUp = 'I gave up smoking last year.';

/// J5_SHOTS=<folder> also saves screenshots of the review note (fonts loaded like test/context_sense_ui_test.dart).
final shots = Platform.environment['J5_SHOTS'];

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  final fonts = Directory('assets/fonts').listSync().whereType<File>().map((f) => f.path).toList();
  await family('Inter', fonts.where((f) => f.contains('Inter')).toList());
  await family('Literata', fonts.where((f) => f.contains('Literata')).toList());
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

Future<void> saveShot(WidgetTester tester, String name) async {
  if (shots == null) return;
  await tester.runAsync(() async {
    final img = await captureImage(find.byType(MaterialApp).evaluate().first);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

SavedWord card(String lemma, String? ctx, {String? meaning}) => SavedWord(lemma, WordStatus.learning, ctx, null, meaning, DateTime(2026));

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  final on = SenseEngine(d);
  final off = SenseEngine(d, wordCardGuard: WordCardGuard.off);

  test('defaults: the 5G/5H/5I switches are as they were; the 5J guard', () {
    expect(SenseEngine.defaultLiteralCues, isTrue);
    expect(SenseEngine.defaultLiteralGuard, isTrue);
    expect(SenseEngine.defaultIdiomRecovery, isFalse);
    expect(SenseEngine.defaultHeadFromPattern, isFalse);
    expect(SenseEngine.defaultCardCarries, isTrue);
    // Off by default (the locked final did not support it): the app grades cards as the 5I engine did.
    expect(SenseEngine.defaultWordCardGuard, WordCardGuard.off);
    expect(on.wordCardGuard, WordCardGuard.off);
    expect(on.fit('run', prisoner, 'koşmak').fit, SentenceFit.confirmed);
    expect(AppState(d, UserDb.open(Directory.systemTemp.createTempSync('rq5j0'))).senses.wordCardGuard, WordCardGuard.off);
  });

  group('SenseEngine.fit for a word inside an expression', () {
    test('"run" in "on the run": the word alone is not graded (it was before)', () {
      expect(off.fit('run', prisoner, 'koşmak').fit, SentenceFit.confirmed, reason: 'the 5I engine (the bug)');
      final f = SenseEngine(d, wordCardGuard: WordCardGuard.idiom).fit('run', prisoner, 'koşmak');
      expect(f.fit, SentenceFit.unknown);
      expect(f.why, 'in expression');
      expect(f.inExpression?.phrase, 'on the run');
      // Already the narrowest guard: the panel says it cannot tell here.
      expect(SenseEngine(d, wordCardGuard: WordCardGuard.undecided).fit('run', prisoner, 'koşmak').why, 'in expression');
    });

    test('a literal use the engine reads word by word stays graded ("hot air rises")', () {
      for (final e in [on, off]) {
        expect(e.fit('hot', hotLiteral, 'sıcak').fit, SentenceFit.confirmed);
      }
    });

    test('no expression in the sentence: nothing changes', () {
      for (final g in WordCardGuard.values) {
        expect(SenseEngine(d, wordCardGuard: g).fit('bank', loan, 'banka').fit, SentenceFit.confirmed, reason: g.name);
      }
    });

    test('phrasal verbs, also split and inflected', () {
      final g = SenseEngine(d, wordCardGuard: WordCardGuard.idiom);
      expect(off.fit('give', gaveUp, 'vermek').fit, SentenceFit.confirmed);
      expect(g.fit('give', gaveUp, 'vermek').inExpression?.phrase, 'give up');
      expect(g.fit('give', 'She gave it up after a week.', 'vermek').confirmed, isFalse);
    });

    test('negation and a mention of the expression are not graded either', () {
      final g = SenseEngine(d, wordCardGuard: WordCardGuard.idiom);
      expect(g.fit('run', 'The suspects were not on the run anymore.', 'koşmak').why, 'in expression');
      expect(g.fit('run', 'The idiom "on the run" means fleeing.', 'koşmak').why, 'in expression');
    });

    test('the expression\'s Turkish carries the answer: still graded ("have breakfast" = "kahvaltı etmek")', () {
      final e = d.exprs.firstWhere((x) => x.phrase == 'have breakfast');
      expect(on.exprCarries(e, 'kahvaltı'), isTrue);
      final give = d.exprs.firstWhere((x) => x.phrase == 'give up');
      expect(on.exprCarries(give, 'vermek'), isFalse, reason: 'vazgeçmek, bırakmak');
      final run = d.exprs.firstWhere((x) => x.phrase == 'on the run');
      expect(on.exprCarries(run, 'koşmak'), isFalse, reason: '"koşturmaca" is not "koş-" with a short ending');
      final carries = SenseEngine(d, wordCardGuard: WordCardGuard.idiom);
      final strict = SenseEngine(d, wordCardGuard: WordCardGuard.idiom, cardCarries: false);
      const s = 'Someone told a joke to break the ice at the meeting.';
      expect(carries.cardBlocker(s, tokenize(s), 'ice', answer: 'buz'), isNull, reason: 'buzları eritmek (a known limit: shared imagery)');
      expect(strict.cardBlocker(s, tokenize(s), 'ice', answer: 'buz')?.expr.phrase, 'break the ice');
      expect(carries.cardBlocker(s, tokenize(s), 'break', answer: 'kırmak')?.expr.phrase, 'break the ice');
    });

    test('Turkish endings and softening in exprCarries', () {
      final e = Expr(0, 'x y', 'idioms', 'kitabı okumak, uyumaya gitmek; tatilde', null, 'x y'.split(' '));
      expect(on.exprCarries(e, 'kitap'), isTrue);
      expect(on.exprCarries(e, 'uyumak'), isTrue);
      expect(on.exprCarries(e, 'tatil'), isTrue);
      expect(on.exprCarries(e, 'okumak'), isTrue, reason: 'a verb by its stem');
      expect(on.exprCarries(e, 'ok'), isFalse, reason: 'shorter than three letters: never');
      expect(on.exprCarries(e, 'masa'), isFalse);
      final draft = Expr(0, 'x y', 'idioms', null, null, 'x y'.split(' '))..trDraft = 'kitap';
      expect(on.exprCarries(draft, 'kitap'), isFalse, reason: 'an AI draft never carries');
    });

    test('the word twice, once inside the expression: not graded (the card does not know which)', () {
      const s = 'The weather was cold, and I felt under the weather.';
      final g = SenseEngine(d, wordCardGuard: WordCardGuard.idiom);
      expect(g.fit('weather', s, 'hava').why, 'in expression');
    });

    test('a sentence boundary splits an expression', () {
      const s = 'She left her keys on the. Run home now.';
      expect(on.cardBlocker(s, tokenize(s), 'run', answer: 'koşmak'), isNull);
    });

    test('grammar words keep their own reason', () {
      expect(SenseEngine(d, wordCardGuard: WordCardGuard.idiom).fit('still', 'The water was still and clear.', 'hâlâ').why, isNot('in expression'));
    });

    test('expression cards and every reading are unchanged; cache and order do not matter', () {
      final e = d.exprs.firstWhere((x) => x.phrase == 'on the run');
      final a = SenseEngine(d), b = SenseEngine(d, wordCardGuard: WordCardGuard.off);
      expect(a.fit('on the run', prisoner, e.tr!).fit, b.fit('on the run', prisoner, e.tr!).fit);
      final toks = tokenize(prisoner);
      final q = SenseQuery(sentence: prisoner, tokens: toks, index: 4);
      expect(a.cacheKey(q), b.cacheKey(q), reason: 'the guard changes no reading');
      expect(a.resolve(q).toString(), b.resolve(q).toString());
      // The word card first, then the expression, then the word again: same answers as a fresh engine.
      final c = SenseEngine(d);
      final first = c.fit('run', prisoner, 'koşmak').why;
      c.fit('on the run', prisoner, e.tr!);
      expect(c.fit('run', prisoner, 'koşmak').why, first);
      final fresh = SenseEngine(d)..fit('on the run', prisoner, e.tr!);
      expect(fresh.fit('run', prisoner, 'koşmak').why, first);
    });
  });

  group('review cards (ReviewQuiz)', () {
    late UserDb u;
    setUp(() => u = UserDb.open(Directory.systemTemp.createTempSync('rq5j')));

    test('inside an idiom: a plain flashcard that says why; outside: four choices', () {
      final q = ReviewQuiz(d, u, rnd: Random(1), senses: SenseEngine(d, wordCardGuard: WordCardGuard.idiom));
      final a = q.answerFor(card('run', prisoner));
      expect(a.choice, isFalse);
      expect(a.unconfirmed, isTrue);
      expect(a.inExpression, 'on the run');
      expect(q.choiceFor(card('run', prisoner)), isNull);
      expect(q.choiceFor(card('bank', loan)), isNotNull);
      expect(q.answerFor(card('bank', loan)).inExpression, isNull);
    });

    test('a meaning saved on an old card is kept as it was, and not graded there', () {
      final q = ReviewQuiz(d, u, rnd: Random(1), senses: SenseEngine(d, wordCardGuard: WordCardGuard.idiom));
      final a = q.answerFor(card('run', prisoner, meaning: 'koşmak'));
      expect(a.tr, 'koşmak');
      expect(a.saved, isTrue);
      expect(a.choice, isFalse);
      expect(a.inExpression, 'on the run');
    });

    test('a card with no sentence is not touched', () {
      final g = ReviewQuiz(d, u, rnd: Random(1), senses: SenseEngine(d, wordCardGuard: WordCardGuard.idiom));
      final o = ReviewQuiz(d, u, rnd: Random(1), senses: SenseEngine(d, wordCardGuard: WordCardGuard.off));
      for (final w in ['bank', 'run', 'course']) {
        expect(g.answerFor(card(w, null)).choice, o.answerFor(card(w, null)).choice, reason: w);
      }
    });
  });

  group('screens', () {
    setUpAll(() async {
      if (shots != null) await loadFonts();
    });
    late Directory dir;
    late AppState app;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('storilex_5j');
      AppState.debugWordCardGuard = WordCardGuard.idiom; // the experimental guard, switched on for these screens
      app = AppState(d, UserDb.open(dir));
    });
    tearDown(() {
      AppState.debugWordCardGuard = null;
      uiEnglish = false;
      dir.deleteSync(recursive: true);
    });

    Future<void> pump(WidgetTester tester, Widget child, {double width = 390, Brightness b = Brightness.light}) async {
      tester.view.physicalSize = Size(width * 2, 1400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(b), home: Scaffold(body: child)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    for (final english in [false, true]) {
      testWidgets('review: the card says it is not graded and why; the learner rates it (${english ? 'EN' : 'TR'})', (tester) async {
        uiEnglish = english;
        app.setWord('run', WordStatus.learning, context: prisoner);
        await pump(tester, ReviewPage(app: app, cards: [ReviewCard(card('run', prisoner), 0)]));
        expect(find.byKey(const ValueKey('review-option-0')), findsNothing, reason: 'no automatic grading');
        await tester.tap(find.text(english ? 'Show answer' : 'Cevabı göster'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('review-in-expression')), findsOneWidget);
        expect(find.textContaining('on the run'), findsWidgets);
        expect(find.textContaining(english ? 'not graded automatically' : 'otomatik puanlanmıyor'), findsOneWidget);
        await saveShot(tester, english ? 'en_review_in_expression_5j' : 'tr_review_in_expression_5j');
        // The learner's own rating is kept apart and still recorded.
        await tester.tap(find.byKey(const ValueKey('review-good')));
        await tester.pumpAndSettle();
        final r = app.user.db.select('SELECT box FROM review WHERE lemma = ?', ['run']);
        expect(r, isNotEmpty);
        expect(r.first['box'], 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('review: 320 px, dark theme, no overflow', (tester) async {
      await pump(tester, ReviewPage(app: app, cards: [ReviewCard(card('run', prisoner), 0)]), width: 320, b: Brightness.dark);
      await tester.tap(find.text('Cevabı göster'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('review-in-expression')), findsOneWidget);
      await saveShot(tester, 'tr_review_in_expression_320_dark_5j');
      expect(tester.takeException(), isNull);
    });

    WordContext ctxFor(String sentence, String word) {
      final toks = tokenize(sentence);
      final idx = toks.indexWhere((t) => t.lower == word);
      final ms = d.matcher.match(toks, text: sentence).where((m) => m.tokens.contains(idx)).toList();
      return WordContext(sentence, toks, idx, ms, null, 1, 'Test book', paraId: 7);
    }

    testWidgets('word panel: "To learn" saves no meaning when the word may be in an expression', (tester) async {
      await pump(tester, WordPanel(app: app, surface: 'bank', ctx: ctxFor(loan, 'bank')));
      await tester.tap(find.byKey(const ValueKey('word-learning')));
      await tester.pump();
      final bank = app.user.words(WordStatus.learning).firstWhere((w) => w.lemma == 'bank');
      expect(bank.context, loan);
      // Unchanged where no expression holds the word: the sure meaning is saved.
      expect(bank.meaning, isNotNull);
      const s = 'I feel under the weather today.';
      await pump(tester, WordPanel(app: app, surface: 'weather', ctx: ctxFor(s, 'weather')));
      await tester.tap(find.byKey(const ValueKey('word-learning')));
      await tester.pump();
      final w = app.user.words(WordStatus.learning).firstWhere((w) => w.lemma == 'weather');
      expect(w.context, s, reason: 'the card is still saved with its sentence');
      expect(w.meaning, isNull);
      // "Learned" stays the learner's own choice.
      await tester.tap(find.byKey(const ValueKey('word-learned')));
      await tester.pump();
      expect(app.user.words(WordStatus.learned).any((x) => x.lemma == 'weather'), isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

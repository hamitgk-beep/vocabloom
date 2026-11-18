// "My journey": active reading time, words read counted once, lookups, reviews and
// grammar answers kept per attempt, old data kept, and the screen shows only real numbers.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/stats.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/journey_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

late DictDb dict;

AppState newApp() {
  final u = UserDb.open(Directory.systemTemp.createTempSync('vb_journey'));
  return AppState(dict, u)..localAi = KeyAi(u);
}

int addBook(UserDb u, List<String> paras) => u.insertBook(ImportedBook('Test book', null, 'txt', [
      ImportedChapter('One', [for (final p in paras) ('p', p)]),
    ]));

void main() {
  setUpAll(() {
    dict = DictDb();
    dict.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    dict.load();
  });

  group('ActiveTimer', () {
    late DateTime now;
    late ActiveTimer t;
    setUp(() {
      now = DateTime(2026, 1, 1, 10);
      t = ActiveTimer(idleLimit: const Duration(minutes: 2), clock: () => now);
    });

    test('counts time between uses, each second once', () {
      t.touch();
      now = now.add(const Duration(seconds: 30));
      t.touch();
      expect(t.take(), 30);
      expect(t.take(), 0);
      now = now.add(const Duration(seconds: 20));
      expect(t.take(), 20);
    });

    test('a long pause counts at most the idle limit', () {
      t.touch();
      now = now.add(const Duration(minutes: 30));
      expect(t.take(), 120);
      now = now.add(const Duration(minutes: 5));
      expect(t.take(), 0, reason: 'the book only lying open is not reading');
      t.touch();
      now = now.add(const Duration(seconds: 10));
      expect(t.take(), 10);
    });

    test('background time is not counted, coming back needs a new use', () {
      t.touch();
      now = now.add(const Duration(seconds: 40));
      t.setForeground(false);
      now = now.add(const Duration(minutes: 1));
      expect(t.take(), 40);
      t.setForeground(true);
      now = now.add(const Duration(minutes: 1));
      expect(t.take(), 0);
      t.touch();
      now = now.add(const Duration(seconds: 5));
      expect(t.take(), 5);
    });

    test('many small touches lose no time', () {
      t.touch();
      for (var i = 0; i < 100; i++) {
        now = now.add(const Duration(milliseconds: 300));
        t.touch();
      }
      expect(t.take(), 30);
    });
  });

  group('StatsStore', () {
    test('a paragraph read again is counted once; reading time adds up by day and book', () {
      final app = newApp();
      final id = addBook(app.user, ['One two three.', 'Four five.', "It's six."]);
      final paras = app.user.paras(id, 0);
      app.stats.markRead(id, 0, paras, 1);
      app.stats.markRead(id, 0, paras, 1);
      expect(app.stats.wordsRead(bookId: id), 5);
      app.stats.markRead(id, 0, paras, 2);
      expect(app.stats.wordsRead(), 7);
      expect(app.stats.bookWords(id), 7);

      final d = DateTime(2026, 3, 10, 12);
      app.stats.addReadingSeconds(id, 60, now: d);
      app.stats.addReadingSeconds(id, 30, now: d);
      app.stats.addReadingSeconds(id, 600, now: d.subtract(const Duration(days: 8)));
      expect(app.stats.readingSeconds(from: DateTime(2026, 3, 10)), 90);
      expect(app.stats.readingSeconds(bookId: id), 690);
      expect(app.stats.readingSeconds(from: DateTime(2026, 3, 3), before: DateTime(2026, 3, 10)), 0);
      expect(app.stats.readingDays(), 2);
    });

    test('deleting a book keeps the totals; a new book with the same id starts at zero', () {
      final app = newApp();
      final id = addBook(app.user, ['One two three four.']);
      app.stats.markRead(id, 0, app.user.paras(id, 0), 0);
      app.stats.addReadingSeconds(id, 120);
      app.stats.forgetBook(id);
      app.user.deleteBook(id);
      expect(app.stats.wordsRead(), 4);
      expect(app.stats.readingSeconds(), 120);
      final again = addBook(app.user, ['Five six.']);
      expect(app.stats.wordsRead(bookId: again), 0);
      expect(app.stats.readingSeconds(bookId: again), 0);
    });

    test('every grammar answer is kept; reviews and lookups are logged', () {
      final app = newApp();
      final g = GrammarProgress(app.user);
      g.record('present_perfect', 'e1', right: false);
      g.record('present_perfect', 'e1', right: true);
      g.record('present_perfect', 'e2', right: true);
      expect(app.stats.grammarByTopic()['present_perfect'], (3, 2));
      expect(g.done('present_perfect'), {'e1', 'e2'});

      app.stats.logReview('run', 'again', false);
      app.stats.logReview('run', 'good', true);
      expect(app.stats.reviewSuccess(), (2, 1));
      expect(app.stats.learnedByReview(), 1);

      app.stats.logLookup('word', 'Bank');
      app.stats.logLookup('word', 'bank');
      app.stats.logLookup('expr', 'look up');
      expect(app.stats.lookups(), 3);
      expect(app.stats.uniqueLookups(), 2);
    });

    test('an existing database keeps its books, words and position', () {
      final dir = Directory.systemTemp.createTempSync('vb_journey_old');
      final u1 = UserDb.open(dir);
      final id = addBook(u1, ['Hello world.']);
      u1.saveProgress(id, 0, 120);
      u1.setWord('run', WordStatus.learning);
      u1.db.dispose();

      final u2 = UserDb.open(dir);
      final app = AppState(dict, u2)..localAi = KeyAi(u2);
      expect(app.stats.readingSeconds(), 0);
      expect(u2.books().single.lastParagraph, 120);
      expect(u2.statuses['run'], WordStatus.learning);
      expect(app.stats.since.isAfter(DateTime(2020)), isTrue);
    });
  });

  test('week comparison only when both weeks have reading time', () {
    expect(Journey.compareWeeks(0, 600), isNull);
    expect(Journey.compareWeeks(600, 0), isNull);
    uiEnglish = true;
    expect(Journey.compareWeeks(3000, 900), 'In the last 7 days you read 35 min more than the week before.');
    uiEnglish = false;
    expect(Journey.compareWeeks(900, 3000), 'Son 7 günde önceki haftadan 35 dk daha az okudun.');
    expect(formatDuration(7 * 3600 + 45 * 60), '7 sa 45 dk');
    expect(formatNumber(12789), '12.789');
  });

  for (final width in [360.0, 820.0]) {
    testWidgets('journey screen at width $width: real numbers, no overflow', (tester) async {
      final app = newApp();
      final id = addBook(app.user, ['One two three.', 'Four five.']);
      app.stats.markRead(id, 0, app.user.paras(id, 0), 0);
      app.stats.addReadingSeconds(id, 7 * 3600 + 45 * 60);
      tester.view.physicalSize = Size(width * 2, 1800 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: JourneyPage(app: app)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('journey-since')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('journey-total')), matching: find.text('7 sa 45 dk')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('journey-words')), matching: find.text('3')), findsOneWidget);
      expect(find.byKey(ValueKey('journey-book-$id')), findsOneWidget);
      // Too few answers: no made-up percentage.
      expect(find.descendant(of: find.byKey(const ValueKey('journey-review-success')), matching: find.text('Henüz az veri')), findsOneWidget);
      expect(find.byKey(const ValueKey('journey-week')), findsNothing);
    });
  }
}

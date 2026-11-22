// PR #112 final check: a Turkish base word found only by cutting endings is a
// guess. When several roots fit, all are offered; none is taken as sure in the
// word sheet, the dictionary search or review grading, and only the reader's
// own tap saves one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/tr_word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;
late TrEnDict tr;

Future<void> pumpPanel(WidgetTester tester, Widget panel) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(Brightness.light), home: Scaffold(body: panel)));
  await tester.pump();
}

void main() {
  setUpAll(() {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    tr = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_trg'));
    app = AppState(d, u)
      ..localAi = KeyAi(u)
      ..trEn = tr
      ..learnLang = 'tr';
  });

  group('several roots', () {
    test('a short stem and a longer one are both kept (ima / iman)', () {
      final (ls, g) = tr.lemmasWithGuess('imanın');
      expect(g, isTrue);
      expect(ls, containsAll(['ima', 'iman']));
    });

    test('a verb root and a noun root are both kept (sanmak / sandık)', () {
      final (ls, g) = tr.lemmasWithGuess('sandığını');
      expect(g, isTrue);
      expect(ls, containsAll(['sanmak', 'sandık']));
    });

    test('softened consonants are put back, and a word in the tables is no guess', () {
      expect(tr.lemmasWithGuess('hesabına').$1, contains('hesap'));
      expect(tr.isGuess('ev'), isFalse);
      expect(tr.isGuess('evlerimizden'), isFalse);
    });

    test('at most three roots are offered', () {
      for (final w in ['imanın', 'sıkıya', 'sandığını', 'temizce', 'peşinden', 'tehlikesi']) {
        expect(tr.lemmas(w).length, lessThanOrEqualTo(3), reason: w);
      }
    });
  });

  group('word sheet', () {
    testWidgets('a tapped guessed form says it is a guess and offers every root', (tester) async {
      await pumpPanel(tester, TrWordPanel(app: app, surface: 'imanın'));
      expect(find.byKey(const ValueKey('tr-lemma-guess')), findsOneWidget);
      expect(find.byKey(const ValueKey('tr-lemma-ima')), findsOneWidget);
      expect(find.byKey(const ValueKey('tr-lemma-iman')), findsOneWidget);
      // Picking the other root keeps the note: it is a guess too.
      await tester.tap(find.byKey(const ValueKey('tr-lemma-iman')));
      await tester.pump();
      expect(find.byKey(const ValueKey('tr-lemma-guess')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a root picked from the search list is still shown as a guess', (tester) async {
      await pumpPanel(tester, TrWordPanel(app: app, surface: 'imanın', lemma: 'iman'));
      expect(find.byKey(const ValueKey('tr-lemma-guess')), findsOneWidget);
      expect(find.text('iman'), findsWidgets);
      expect(find.byKey(const ValueKey('tr-lemma-ima')), findsOneWidget);
    });

    testWidgets('a word opened by itself has no guess note', (tester) async {
      await pumpPanel(tester, TrWordPanel(app: app, surface: 'ev', lemma: 'ev'));
      expect(find.byKey(const ValueKey('tr-lemma-guess')), findsNothing);
      await pumpPanel(tester, TrWordPanel(app: app, surface: 'evlerimizden'));
      expect(find.byKey(const ValueKey('tr-lemma-guess')), findsNothing);
    });

    testWidgets('only the reader\'s tap saves a root, and it saves the one shown', (tester) async {
      expect(app.user.statuses.containsKey('iman'), isFalse);
      expect(app.user.statuses.containsKey('ima'), isFalse);
      await pumpPanel(tester, TrWordPanel(app: app, surface: 'imanın'));
      // Opening the sheet saves nothing.
      expect(app.user.statuses.containsKey('ima'), isFalse);
      await tester.tap(find.byKey(const ValueKey('tr-lemma-iman')));
      await tester.pump();
      await tester.tap(find.text('Öğreneceğim'));
      await tester.pump();
      expect(app.user.statuses['iman'], WordStatus.learning);
      expect(app.user.statuses.containsKey('ima'), isFalse);
    });
  });
}

// Phone screens for the theme / menu / settings changes, day and night:
// the home page (top and scrolled to the end), the More menu, Settings (top
// and end) and the grammar answer box for a right and a wrong answer.
//
// Run:  flutter test qa_test/theme_menus_look_test.dart   (writes qa-report/theme-menus/*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/main.dart';
import 'package:kelime_okur/ui/grammar/grammar_page.dart';
import 'package:kelime_okur/ui/settings_page.dart';
import 'package:kelime_okur/ui/theme.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/theme-menus');

Widget shell(Widget home, Brightness b) => MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: uiLocale,
      supportedLocales: uiLocales,
      localizationsDelegates: uiLocalizationsDelegates,
      theme: buildTheme(b),
      home: home,
    );

Future<void> shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  final el = find.byType(MaterialApp).evaluate().first;
  await tester.runAsync(() async {
    final img = await captureImage(el);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${outDir.path}/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Scrolls the first scrollable on screen to its end.
Future<void> toEnd(WidgetTester tester) async {
  final s = find.byType(Scrollable).first;
  final state = tester.state<ScrollableState>(s);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  late AppState app;
  late List<GrammarTopic> lessons;
  setUpAll(() async {
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_tm')))..localAi = KeyAi(UserDb.open(Directory.systemTemp.createTempSync('vb_tm_ai')));
    for (final f in ['test/fixtures/sample.txt', 'test/fixtures/sample.docx', 'test/fixtures/sample.epub', 'test/fixtures/sample.txt', 'test/fixtures/sample.docx']) {
      final id = app.user.insertBook(await importFile(f, isWord: app.isWord));
      app.user.saveProgress(id, 0, 3);
    }
    for (final w in ['mysterious', 'bitter', 'frost', 'gale']) {
      app.user.setWord(w, WordStatus.learning);
    }
    lessons = parseGrammarTopics(File('assets/grammar/lessons.json').readAsStringSync(), File('assets/grammar/lessons_en.json').readAsStringSync());
  });

  for (final b in Brightness.values) {
    testWidgets('phone ${b.name}', (tester) async {
      uiEnglish = false;
      app.setTheme(b == Brightness.dark ? ThemeMode.dark : ThemeMode.light);
      tester.view.physicalSize = const Size(393 * 2, 852 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final n = b.name;

      await tester.pumpWidget(shell(HomePage(app: app), b));
      await shot(tester, '${n}_home');
      await toEnd(tester);
      await shot(tester, '${n}_home_end');
      await tester.tap(find.byKey(const ValueKey('nav-menu')));
      await shot(tester, '${n}_more_menu');
      // Settings from the More menu, at the top and scrolled to the end.
      await tester.tap(find.byKey(const ValueKey('nav_6')));
      await shot(tester, '${n}_settings');
      final settings = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable));
      final pos = tester.state<ScrollableState>(settings.first).position;
      pos.jumpTo(pos.maxScrollExtent);
      await shot(tester, '${n}_settings_end');
      // Grammar from the More menu, scrolled to the end.
      await tester.tap(find.byKey(const ValueKey('nav-menu')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('nav_3')));
      final grammar = find.descendant(of: find.byType(GrammarPage), matching: find.byType(Scrollable));
      // The lessons load from the asset bundle.
      for (var i = 0; i < 30 && grammar.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (grammar.evaluate().isNotEmpty) {
        final gp = tester.state<ScrollableState>(grammar.first).position;
        gp.jumpTo(gp.maxScrollExtent);
        await shot(tester, '${n}_grammar_end');
      }
      await tester.pump(const Duration(seconds: 5));

      // The answer box: a right and a wrong answer to a gap sentence.
      final topic = lessons.firstWhere((t) => t.exercises.any((e) => e.isGap));
      final gx = topic.exercises.firstWhere((e) => e.isGap);
      await tester.pumpWidget(shell(GrammarPracticePage(app: app, topic: topic, round: [gx]), b));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, gx.answers.first);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await shot(tester, '${n}_grammar_right');
      await tester.pumpWidget(shell(GrammarPracticePage(app: app, topic: topic, round: [gx]), b));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'xyz');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await shot(tester, '${n}_grammar_wrong');
      await tester.pumpWidget(const SizedBox());
    });
  }
}

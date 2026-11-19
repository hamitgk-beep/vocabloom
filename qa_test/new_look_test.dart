// Screens of the gold look (night and day, phone and desktop): library,
// reader, word panel, dictionary, grammar, my words, stats and settings.
//
// Run:  flutter test qa_test/new_look_test.dart   (writes qa-report/new-look/*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/main.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/sentence_sheet.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/new-look');

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

void main() {
  late AppState app;
  setUpAll(() async {
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_newlook')))
      ..localAi = KeyAi(UserDb.open(Directory.systemTemp.createTempSync('vb_newlook_ai')));
    for (final f in ['test/fixtures/sample.txt', 'test/fixtures/sample.docx', 'test/fixtures/sample.epub']) {
      final id = app.user.insertBook(await importFile(f, isWord: app.isWord));
      app.user.saveProgress(id, 0, 3);
      app.stats.addReadingSeconds(id, 900 + id * 300);
      app.stats.addReadingSeconds(id, 1200, now: DateTime.now().subtract(Duration(days: id)));
    }
    for (final w in ['mysterious', 'bitter', 'frost', 'gale']) {
      app.user.setWord(w, WordStatus.learning);
    }
    app.user.setWord("think", WordStatus.learned);
  });

  for (final b in Brightness.values) {
    for (final (size, dev) in [(const Size(393, 852), 'phone'), (const Size(1440, 900), 'desktop')]) {
      testWidgets('$dev ${b.name}', (tester) async {
        uiEnglish = false;
        await tester.binding.setSurfaceSize(size);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final pre = '${dev}_${b.name}';
        await tester.pumpWidget(shell(HomePage(app: app), b));
        await shot(tester, '${pre}_1_library');
        final phone = dev == 'phone';
        Future<void> go(int i, String name) async {
          if (phone && i >= 3) {
            // Grammar, free library, stats and settings live in the bottom bar's menu.
            await tester.tap(find.byKey(const ValueKey('nav-menu')));
            await tester.pump(const Duration(milliseconds: 400));
            if (i == 3) await shot(tester, '${pre}_menu_open');
          }
          await tester.tap(find.byKey(ValueKey(phone ? 'nav_$i' : 'side-menu-$i')));
          await tester.pump(const Duration(milliseconds: 400));
          await shot(tester, '${pre}_$name');
          if (phone && i >= 4) {
            await tester.tap(find.byKey(const ValueKey('nav_0')));
            await tester.pump(const Duration(milliseconds: 300));
          }
        }

        await go(1, '2_words');
        await go(2, '3_dictionary');
        await go(3, '4_grammar');
        if (phone) await go(0, '1_library_again');
        await go(6, '5_settings');
        if (phone) await go(0, '1_library_again');
        await go(5, '6_stats');
        if (phone) await go(0, '1_library_again');
        await go(4, '7_free_library');

        final bk = app.user.books().last;
        await tester.pumpWidget(shell(ReaderPage(app: app, book: bk), b));
        await tester.pump(const Duration(milliseconds: 500));
        await shot(tester, '${pre}_8_reader');
        const sentence = 'He had been doing this for forty years, and he never once thought of giving it up.';
        final para = Para(1, 0, 'p', sentence);
        final a = analyze(app, sentence);
        final ti = a.tokens.indexWhere((t) => t.text == 'thought');
        showWordSheet(tester.element(find.byType(ReaderPage)), app, 'thought', ctx: buildContext(app, para, a, ti));
        await tester.pump(const Duration(milliseconds: 600));
        await shot(tester, '${pre}_9_word_panel');

        // Sepia page: the filter menu, the panels and the mouse bubble take its colour.
        if (b == Brightness.light) {
          final paper0 = app.paper;
          app.setReading(paper: 'sepia');
          app.setTone('sepia', 0.7);
          await tester.pumpWidget(shell(ReaderPage(app: app, book: bk), b));
          await tester.pump(const Duration(milliseconds: 500));
          if (!phone) {
            await tester.tap(find.byKey(const ValueKey('reader-filters')));
            await tester.pump(const Duration(milliseconds: 400));
          }
          await shot(tester, '${pre}_10_sepia_filters');
          final pv = find.byType(ParagraphView);
          final word = pv.at(pv.evaluate().length > 2 ? 2 : pv.evaluate().length - 1);
          final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          final box = tester.getRect(word);
          await mouse.moveTo(box.topLeft + const Offset(40, 14));
          await tester.pump(const Duration(milliseconds: 300));
          await shot(tester, '${pre}_11_sepia_hover');
          await mouse.moveTo(Offset.zero);
          await tester.pump(const Duration(milliseconds: 100));
          showSentenceSheet(tester.element(find.byType(ReaderPage)), app, para, a, ti, bookId: bk.id, bookTitle: bk.title);
          await tester.pump(const Duration(milliseconds: 600));
          await shot(tester, '${pre}_12_sepia_sentence');
          app.setReading(paper: paper0);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
}

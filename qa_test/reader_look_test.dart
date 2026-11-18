// Screens of the new reading pieces: the library with book covers and the
// sideways-scrolling bottom bar, and the reading view sheet with its shade
// slider for white, sepia and night.
//
// Run:  BOOK=/path/to/book.pdf flutter test qa_test/reader_look_test.dart
//       (writes qa-report/reader-look/*.png; needs PDFIUM_PATH for a PDF)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/main.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/reading_sheet.dart';
import 'package:kelime_okur/ui/theme.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/reader-look');
final book = Platform.environment['BOOK'] ?? 'test/fixtures/sample.epub';
final needsPdfium = book.endsWith('.pdf') && (Platform.environment['PDFIUM_PATH'] ?? '').isEmpty;

Widget shell(Widget home, AppState app) => MaterialApp(
  key: UniqueKey(),
  debugShowCheckedModeBanner: false,
  locale: uiLocale,
  supportedLocales: uiLocales,
  localizationsDelegates: uiLocalizationsDelegates,
  theme: buildTheme(Brightness.light),
  darkTheme: buildTheme(Brightness.dark),
  themeMode: app.themeMode,
  home: home,
);

Future<void> shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));
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
  late int bookId;
  setUpAll(() async {
    if (needsPdfium) return;
    if (book.endsWith('.pdf')) pdfrxInitialize();
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_look')));
    bookId = app.user.insertBook(await importFile(book, isWord: app.isWord));
  });

  testWidgets('library, bottom bar and reading view', skip: needsPdfium, (tester) async {
    uiEnglish = false;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell(HomePage(app: app), app));
    await shot(tester, 'library');
    // The bar scrolls to show the last tabs.
    await tester.tap(find.byKey(const ValueKey('nav_4')));
    await shot(tester, 'free_library_tab');

    final bk = app.user.books().firstWhere((x) => x.id == bookId)..lastPage = 2;
    for (final (theme, mode, tone) in [('white', ThemeMode.light, 0.8), ('sepia', ThemeMode.light, 1.0), ('night', ThemeMode.dark, 0.7)]) {
      app.themeMode = mode;
      app.paper = theme == 'night' ? 'white' : theme;
      app.setTone(theme, tone);
      await tester.pumpWidget(shell(ReaderPage(app: app, book: bk), app));
      await tester.pump();
      final ctx = tester.element(find.byType(ReaderPage));
      showReadingSheet(ctx, app);
      await tester.pump(const Duration(milliseconds: 400));
      await shot(tester, 'reading_${theme}_$tone');
    }
  });
}

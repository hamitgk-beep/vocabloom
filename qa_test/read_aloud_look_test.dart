// Screens of read aloud in the reader: the book with the spoken sentence
// highlighted and the control card at the page's foot, day and night.
//
// Run:  flutter test qa_test/read_aloud_look_test.dart
//       (writes qa-report/read-aloud/*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/tts/read_aloud.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/read-aloud');

void main() {
  late AppState app;
  late int bookId;
  setUpAll(() async {
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_ra')));
    bookId = app.user.insertBook(await importFile('test/fixtures/sample.epub', isWord: app.isWord));
  });

  testWidgets('read aloud keeps the book on screen', (tester) async {
    uiEnglish = false;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    for (final (name, mode) in [('day', ThemeMode.light), ('night', ThemeMode.dark)]) {
      app.themeMode = mode;
      final bk = app.user.books().firstWhere((x) => x.id == bookId)..lastPage = 0;
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        locale: uiLocale,
        supportedLocales: uiLocales,
        localizationsDelegates: uiLocalizationsDelegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: ReaderPage(app: app, book: bk),
      ));
      await tester.pump();
      // Reading starts at the first paragraph under the title.
      final ReadAloud reader = (tester.state(find.byType(ReaderPage)) as dynamic).reader;
      reader.start(1);
      // Hold reading on the first sentence (as when a word is said), then
      // show the card as playing.
      Speech.instance.onSay!();
      reader.paused = false;
      app.themeMode = mode; // redraws the page
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('speech-bar')), findsOneWidget);
      await tester.runAsync(() async {
        final img = await captureImage(find.byType(MaterialApp).evaluate().first);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${outDir.path}/$name.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
      reader.stop();
      await tester.pumpWidget(const SizedBox());
    }
  });
}

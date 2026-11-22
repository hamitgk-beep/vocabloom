// Windows title bar drawn by the app, the summary card's book at several
// window widths, and the gear on Settings.
//
// Run:  flutter test qa_test/window_frame_look_test.dart   (writes qa-report/window-frame/*.png)
import 'dart:io';

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
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/window_frame.dart';

import 'new_look_test.dart' as look show shot, outDir;
import 'picture_book_test.dart' show loadFonts;

Widget framed(Widget home, Brightness b) => MaterialApp(
  key: UniqueKey(),
  debugShowCheckedModeBanner: false,
  locale: uiLocale,
  supportedLocales: uiLocales,
  localizationsDelegates: uiLocalizationsDelegates,
  theme: buildTheme(b),
  builder: (context, child) => WindowFrame(force: true, child: child!),
  home: home,
);

void main() {
  late AppState app;
  setUpAll(() async {
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_frame')))
      ..localAi = KeyAi(UserDb.open(Directory.systemTemp.createTempSync('vb_frame_ai')));
    for (final f in ['test/fixtures/sample.txt', 'test/fixtures/sample.docx', 'test/fixtures/sample.epub']) {
      final id = app.user.insertBook(await importFile(f, isWord: app.isWord));
      app.user.saveProgress(id, 0, 3);
      app.stats.addReadingSeconds(id, 900 + id * 300);
    }
  });

  for (final b in Brightness.values) {
    for (final w in [1440.0, 1300.0, 1200.0, 1100.0, 900.0, 760.0, 393.0]) {
      testWidgets('frame $w ${b.name}', (tester) async {
        uiEnglish = true;
        final size = Size(w, w < 500 ? 852 : 760);
        await tester.binding.setSurfaceSize(size);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(framed(HomePage(app: app), b));
        expect(find.byKey(const ValueKey('window-close')), findsOneWidget);
        await look.shot(tester, '../window-frame/${b.name}_${w.toInt()}_library');
        if (w == 1100) {
          await tester.pumpWidget(framed(ReaderPage(app: app, book: app.user.books().last), b));
          await tester.pump(const Duration(milliseconds: 500));
          await look.shot(tester, '../window-frame/${b.name}_${w.toInt()}_reader');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  }
  test('out dir', () => expect(look.outDir.path, isNotEmpty));
}

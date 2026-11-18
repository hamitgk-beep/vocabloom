// Screens of an illustrated PDF book in the reader: every page of the book is
// a page of the reader, with its pictures and captions where the book has
// them, its titles large and centred, and its text justified.
//
// Run:  BOOK=/path/to/book.pdf PAGES=1,2,6,7,9 flutter test qa_test/picture_book_test.dart
//       (writes qa-report/picture-book/*.png; without BOOK the test book of
//       test/fixtures/import is used)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/pages.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/picture-book');
final book = Platform.environment['BOOK'] ?? 'test/fixtures/import/book.pdf';
final shown = (Platform.environment['PAGES'] ?? '1,2,3').split(',').map((s) => int.parse(s.trim())).toList();

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
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

Widget shell(Widget home, Brightness b) => MaterialApp(
  key: UniqueKey(),
  debugShowCheckedModeBanner: false,
  locale: uiLocale,
  supportedLocales: uiLocales,
  localizationsDelegates: uiLocalizationsDelegates,
  theme: buildTheme(b),
  home: home,
);

void main() {
  late AppState app;
  late int bookId;
  setUpAll(() async {
    pdfrxInitialize();
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_pictures')));
    final b = await importFile(book, isWord: app.isWord);
    bookId = app.user.insertBook(b);
  });

  testWidgets('pages of the book in the reader', (tester) async {
    uiEnglish = false;
    for (final (size, name) in [(const Size(430, 900), 'phone'), (const Size(1280, 860), 'desktop')]) {
      for (final b in [Brightness.light, if (size.width < 500) Brightness.dark]) {
        await tester.binding.setSurfaceSize(size);
        for (final want in shown) {
          // The chapter and the page of the chapter that hold page [want] of the book.
          final chapters = app.user.chapters(bookId);
          var ch = 0, pg = 0;
          for (final c in chapters) {
            final ps = app.user.paras(bookId, c.idx);
            final pages = pagesOf(ps);
            final k = pages.indexWhere((r) => r.$1 < ps.length && (ps[r.$1].page ?? -1) + 1 >= want);
            if (k >= 0) {
              ch = c.idx;
              pg = k;
              break;
            }
          }
          final bk = app.user.books().firstWhere((x) => x.id == bookId)
            ..lastChapter = ch
            ..lastPage = pg
            ..lastParagraph = 0;
          await tester.pumpWidget(shell(ReaderPage(app: app, book: bk), b));
          await tester.pump();
          // Pictures are read from their files outside the fake clock.
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
            await tester.pump(const Duration(milliseconds: 50));
          }
          final el = find.byType(MaterialApp).evaluate().first;
          await tester.runAsync(() async {
            final img = await captureImage(el);
            final png = await img.toByteData(format: ui.ImageByteFormat.png);
            final f = File('${outDir.path}/${name}_${b.name}_page$want.png');
            f.parent.createSync(recursive: true);
            f.writeAsBytesSync(png!.buffer.asUint8List());
          });
        }
      }
    }
  });
}

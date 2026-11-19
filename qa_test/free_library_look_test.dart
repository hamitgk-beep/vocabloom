// Screens of the free library's illustrated texts in the reader: a picture
// book page by page, a Beatrix Potter tale, and an illustrated classic.
//
// Run:  PB_IMAGEBANK=/path/to/pb-imagebank flutter test qa_test/free_library_look_test.dart
//       (writes qa-report/free-library-look/*.png; without PB_IMAGEBANK the
//       stories show plain stand-in pictures)
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/free_library.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/free-library-look');

Future<List<int>?> localPicture(String address) async {
  if (address.startsWith('lib:')) return File('library/images/${address.substring(4)}').readAsBytesSync();
  final bank = Platform.environment['PB_IMAGEBANK'];
  final f = File('$bank/medium/${address.substring(3)}');
  if (bank != null && f.existsSync()) return f.readAsBytesSync();
  final img = im.Image(width: 480, height: 400);
  im.fill(img, color: im.ColorRgb8(200, 220, 240));
  return im.encodeJpg(img);
}

Widget shell(Widget home) => MaterialApp(
  key: UniqueKey(),
  debugShowCheckedModeBanner: false,
  locale: uiLocale,
  supportedLocales: uiLocales,
  localizationsDelegates: uiLocalizationsDelegates,
  theme: buildTheme(Brightness.light),
  home: home,
);

void main() {
  late AppState app;
  late FreeLibrary lib;
  setUpAll(() async {
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_free_look')));
    FreeLibrary.debugBookText = (it) async => utf8.decode(gzip.decode(File('library/books/${it.id}.md.gz').readAsBytesSync()));
    FreeLibrary.debugPicture = localPicture;
    lib = await FreeLibrary.load();
  });

  testWidgets('illustrated library texts in the reader', (tester) async {
    uiEnglish = false;
    await tester.binding.setSurfaceSize(const Size(430, 900));
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ids = (Platform.environment['ITEMS'] ?? 'pb-0002:0,pb-0002:1,pg-14407:2,pg-120:1,pg-13853:1').split(',');
    for (final spec in ids) {
      final [id, page] = spec.split(':');
      final it = lib.items.firstWhere((x) => x.id == id);
      final book = (await tester.runAsync(() => addLibraryItem(app.user, lib, it)))!
        ..lastChapter = int.parse(page) > 0 && id.startsWith('pg-120') ? 1 : 0
        ..lastPage = id.startsWith('pg-120') ? 0 : int.parse(page)
        ..lastParagraph = 0;
      await tester.pumpWidget(shell(ReaderPage(app: app, book: book)));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final el = find.byType(MaterialApp).evaluate().first;
      await tester.runAsync(() async {
        final img = await captureImage(el);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        final f = File('${outDir.path}/${id}_$page.png');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}

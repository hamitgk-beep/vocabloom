// The free library: every level has something to read, every story and book
// file is there, the texts import as books, and the page adds and opens them.
// LIB_SHOTS=<folder> also saves screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/free_library.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/free_library_page.dart';
import 'package:kelime_okur/ui/library_page.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;
final shots = Platform.environment['LIB_SHOTS'];

Future<String> localBook(LibraryItem it) async => utf8.decode(gzip.decode(File('library/books/${it.id}.md.gz').readAsBytesSync()));

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

Future<void> shot(WidgetTester tester, String name) async {
  if (shots == null) return;
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    final img = await captureImage(find.byType(MaterialApp).evaluate().first);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$shots/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Widget shell(Widget home, {Brightness b = Brightness.light}) => MaterialApp(
    key: UniqueKey(),
    debugShowCheckedModeBanner: false,
    locale: uiLocale,
    supportedLocales: uiLocales,
    localizationsDelegates: uiLocalizationsDelegates,
    theme: buildTheme(b),
    home: home);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FreeLibrary lib;

  setUpAll(() async {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_lib'));
    app = AppState(d, u)..localAi = KeyAi(u);
    FreeLibrary.debugBookText = localBook;
    lib = await FreeLibrary.load();
    if (shots != null) await loadFonts();
  });

  tearDown(() => uiEnglish = false);

  test('every level has stories or books, and every text is there', () async {
    for (final l in libraryLevels) {
      expect(lib.items.where((it) => it.level == l), isNotEmpty, reason: l);
    }
    expect(lib.items.where((it) => !it.isBook).length, greaterThan(250));
    expect(lib.items.where((it) => it.isBook).length, greaterThanOrEqualTo(25));
    expect(lib.items.map((it) => it.id).toSet().length, lib.items.length);
    for (final it in lib.items) {
      // Only licences that allow use in a free app with ads.
      expect(['CC BY 4.0', 'Public domain'], contains(it.license), reason: it.id);
      if (it.isBook) {
        expect(File('library/books/${it.id}.md.gz').existsSync(), isTrue, reason: it.id);
        expect(it.chapters, greaterThan(0), reason: it.id);
      }
    }
  });

  test('a story imports with its credits, a book with its chapters', () async {
    final story = lib.items.firstWhere((it) => it.id == 'pb-0002'); // Fat King Thin Dog
    final s = await lib.fetch(story);
    expect(s.title, 'Fat King Thin Dog');
    final paras = s.chapters.expand((c) => c.paragraphs).map((p) => p.$2).toList();
    expect(paras.first, 'Fat King Thin Dog');
    expect(paras, contains('This is a fat king.'));
    expect(paras.last, contains('Parismita'));
    expect(paras.last, contains('CC BY 4.0'));

    final book = lib.items.firstWhere((it) => it.id == 'pg-1342'); // Pride and Prejudice
    final b = await lib.fetch(book);
    expect(b.author, 'Jane Austen');
    expect(b.format, 'C1');
    expect(b.chapters.first.title, 'Chapter 1');
    expect(b.chapters.first.paragraphs[1].$2, startsWith('It is a truth universally acknowledged'));
    expect(b.chapters.length, greaterThanOrEqualTo(61));
    final all = b.chapters.expand((c) => c.paragraphs).map((p) => p.$2).join(' ');
    expect(all, isNot(contains('Gutenberg')));
    expect(all, contains('Elizabeth'));
  });

  testWidgets('the library opens the free library; a tap adds a story and opens it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell(LibraryPage(app: app)));
    await tester.pump();
    expect(find.byKey(const ValueKey('free-library')), findsOneWidget);
    await shot(tester, 'library_empty');
    await tester.tap(find.text('Ücretsiz kütüphane'));
    await tester.pumpAndSettle();
    expect(find.byType(FreeLibraryPage), findsOneWidget);
    await tester.pump();
    await shot(tester, 'free_library_all');

    await tester.tap(find.byKey(const ValueKey('lib-level-A1')));
    await tester.pump();
    expect(find.textContaining('A1 · Başlangıç'), findsOneWidget);
    await shot(tester, 'free_library_a1');
    final first = lib.items.firstWhere((it) => it.level == 'A1' && !it.isBook);
    await tester.tap(find.byKey(ValueKey('lib-${first.id}')));
    for (var i = 0; i < 20 && find.byType(ReaderPage).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(app.user.booksBySource()[first.id]?.title, first.title);
    await shot(tester, 'free_library_story_reader');
  });

  testWidgets('B2 shows the classics; a book is added once', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell(FreeLibraryPage(app: app), b: Brightness.dark));
    for (var i = 0; i < 10 && find.byType(ListView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('lib-level-B2')));
    await tester.pump();
    final it = lib.items.firstWhere((x) => x.level == 'B2' && x.isBook);
    expect(find.text(it.title), findsOneWidget);
    expect(find.text(lib.items.firstWhere((x) => x.level == 'A1').title), findsNothing);
    await shot(tester, 'free_library_b2_dark');
    final b1 = await tester.runAsync(() => addLibraryItem(app.user, lib, it));
    final b2 = await tester.runAsync(() => addLibraryItem(app.user, lib, it));
    expect(b1!.id, b2!.id);
    expect(b1.format, 'B2');
    expect(b1.chapterCount, greaterThanOrEqualTo(it.chapters!));
    await tester.tap(find.byIcon(Icons.info_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Kamu malı (telifsiz)'), findsOneWidget);
    await shot(tester, 'free_library_info_dark');
  });
}

// Turkish books for English speakers: the language settings, a Turkish book
// and the Turkish -> English word panel.
//
// Run:  flutter test qa_test/turkish_look_test.dart   (writes qa-report/turkish/*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/dictionary_page.dart';
import 'package:kelime_okur/ui/free_library_page.dart';
import 'package:kelime_okur/ui/library_page.dart';
import 'package:kelime_okur/ui/other_pages.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/review_page.dart';
import 'package:kelime_okur/ui/settings_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/turkish');

Widget shell(Widget home, AppState app, Brightness b) => MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: uiLocale,
      supportedLocales: uiLocales,
      localizationsDelegates: uiLocalizationsDelegates,
      theme: buildTheme(b),
      home: home,
    );

Future<void> shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
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
    await loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_tr')));
    app.trEn = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));
    bookId = app.user.insertBook(await importFile('test/fixtures/turkish_sample.txt', isWord: app.isWord));
  });

  Future<void> phone(WidgetTester tester) async {
    const size = Size(400, 860);
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('settings: native and learned language', (tester) async {
    await phone(tester);
    app.setLanguages(native: 'tr', learn: 'en');
    await tester.pumpWidget(shell(SettingsPage(app: app), app, Brightness.light));
    await shot(tester, 'settings_tr_learn_en');
    expect(find.byKey(const ValueKey('setting-learn')), findsOneWidget);
    // Learning Turkish makes English the native language.
    app.setLanguages(learn: 'tr');
    expect(app.nativeLang, 'en');
    expect(app.learnTurkish, isTrue);
    await tester.pumpWidget(shell(SettingsPage(app: app), app, Brightness.light));
    await shot(tester, 'settings_en_learn_tr');
    await tester.tap(find.byKey(const ValueKey('setting-learn')));
    await tester.pumpAndSettle();
    await shot(tester, 'settings_en_learn_menu');
    await tester.pumpWidget(const SizedBox());
  });

  for (final b in Brightness.values) {
    testWidgets('turkish book and word panel ${b.name}', (tester) async {
      await phone(tester);
      app.setLanguages(native: 'en', learn: 'tr');
      app.themeMode = b == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
      final bk = app.user.books().firstWhere((x) => x.id == bookId);
      await tester.pumpWidget(shell(ReaderPage(app: app, book: bk), app, b));
      await shot(tester, 'reader_${b.name}');
      expect(find.byKey(const ValueKey('reader-filters')), findsNothing);
      final home = tester.element(find.byType(ReaderPage));
      for (final w in ['Evlerimizden', 'gülümsedi', 'kitap']) {
        showWordSheet(home, app, w);
        await tester.pump(const Duration(milliseconds: 600));
        await shot(tester, 'panel_${w.toLowerCase()}_${b.name}');
        Navigator.of(home).pop();
        await tester.pump(const Duration(milliseconds: 600));
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('learning Turkish: every menu shows Turkish content only', (tester) async {
    await phone(tester);
    app.themeMode = ThemeMode.light;
    app.setLanguages(native: 'tr', learn: 'en');
    app.setWord('house', WordStatus.learning, meaning: 'ev');
    app.user.insertBook(await importFile('test/fixtures/sample.txt', isWord: app.isWord));
    app.setLanguages(native: 'en', learn: 'tr');
    for (final w in ['kitap', 'ev', 'gülümsemek', 'köpek']) {
      app.setWord(w, WordStatus.learning, meaning: app.trEn!.shortMeaning(w));
    }
    app.setWord('su', WordStatus.learned, meaning: app.trEn!.shortMeaning('su'));
    await tester.pumpWidget(shell(WordsPage(app: app), app, Brightness.light));
    await shot(tester, 'mywords_learn_tr');
    expect(find.text('house'), findsNothing);
    expect(find.text('kitap'), findsOneWidget);

    await tester.pumpWidget(shell(DictionaryPage(app: app), app, Brightness.light));
    await shot(tester, 'dictionary_learn_tr');
    await tester.enterText(find.byType(TextField), 'kitab');
    await tester.pump();
    await shot(tester, 'dictionary_search_kitab');
    await tester.enterText(find.byType(TextField), 'dog');
    await tester.pump();
    await shot(tester, 'dictionary_search_dog');
    expect(find.text('köpek'), findsWidgets);

    await tester.pumpWidget(shell(LibraryPage(app: app), app, Brightness.light));
    await shot(tester, 'library_learn_tr');
    expect(app.user.books().every((b) => b.title != 'sample_en'), isTrue);

    await tester.pumpWidget(shell(FreeLibraryPage(app: app), app, Brightness.light));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await shot(tester, 'free_library_learn_tr');

    final cards = app.review.due();
    expect(cards.map((c) => c.word.lemma), isNot(contains('house')));
    await tester.pumpWidget(shell(ReviewPage(app: app, cards: cards), app, Brightness.light));
    await shot(tester, 'review_learn_tr');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}

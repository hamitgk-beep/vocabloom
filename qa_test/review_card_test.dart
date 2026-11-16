// Review card checks on a phone-sized screen: the right answer is the meaning
// in the card's sentence, the asked word cannot be tapped (it would show the
// answer) while the other words can, and a book with a UUID file name shows a
// real title. Screenshots go to $QA_OUT/review (default qa-report/review).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/review_page.dart';
import 'package:kelime_okur/ui/theme.dart';

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/review');
const phone = Size(450, 1000);
const uuid = '9bfdefed-8b6d-4c1e-9a7b-2f3c4d5e6f70';
const golf = 'American-style supermarkets and a new golf course can now be found in Ho Chi Minh City.';

Future<void> _loadFonts() async {
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

Widget shell(Widget home) => MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: uiLocale,
      supportedLocales: uiLocales,
      localizationsDelegates: uiLocalizationsDelegates,
      theme: buildTheme(Brightness.light),
      home: home,
    );

Future<void> shot(WidgetTester tester, String name) async {
  for (var i = 0; i < 10; i++) {
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
  setUpAll(() async {
    await _loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_review'));
    app = AppState(d, u);
    app.localAi = KeyAi(u);
    u.insertBook(ImportedBook(uuid, null, 'pdf', [
      ImportedChapter('Chapter 1', [('h', 'Vietnam Opens Its Doors'), ('p', golf)])
    ]));
    // Saved the way the old version did: under the UUID title, with the wrong meaning.
    u.setWord('course', WordStatus.learning, context: golf, book: uuid, meaning: 'akmak, hızla akmak');
    for (final w in ['narrow', 'storm', 'decision', 'island', 'village', 'important']) {
      u.setWord(w, WordStatus.learned);
    }
    u.repairBookTitles(looksGeneratedTitle, titleFromContent);
  });

  Future<void> open(WidgetTester tester) async {
    final cards = app.review.due(now: DateTime.now().add(const Duration(days: 1))).where((c) => c.word.lemma == 'course').toList();
    await tester.pumpWidget(shell(ReviewPage(app: app, cards: cards)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('golf course card', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    tester.view.physicalSize = phone * 2;
    tester.view.devicePixelRatio = 2;

    // 1. Dictionary only: it has no Turkish for "a ground laid out for a
    // sport", so the card is a flashcard instead of offering a wrong answer.
    await open(tester);
    expect(find.textContaining('9bfdefed'), findsNothing);
    expect(find.text('Vietnam Opens Its Doors'), findsOneWidget);
    expect(find.textContaining('akmak'), findsNothing);
    await shot(tester, 'course_dictionary_only');
    await tester.tap(find.text(L('Cevabı göster', 'Show answer')));
    await shot(tester, 'course_dictionary_only_answer');

    // 2. With the meaning from the AI service: four choices, the right one is "saha".
    app.user.setContextAi('course', golf, 'saha, golf sahası');
    await open(tester);
    final st = tester.state(find.byType(ReviewPage)) as dynamic;
    expect(st.debugRight, 'saha, golf sahası');
    expect(find.text('saha, golf sahası'), findsOneWidget);
    await shot(tester, 'course_question');

    // 3. Tapping the underlined asked word opens nothing; another word opens its panel.
    final rich = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('golf course'));
    expect(rich, findsOneWidget);
    Offset at(String word) {
      final ro = tester.renderObject<RenderParagraph>(rich);
      final text = ro.text.toPlainText();
      final i = text.indexOf(word);
      final boxes = ro.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + word.length));
      return ro.localToGlobal(boxes.first.toRect().center);
    }

    await tester.tapAt(at('course'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tapAt(at('supermarkets'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsOneWidget);
    await shot(tester, 'course_other_word_tapped');
    await tester.binding.setSurfaceSize(null);
  });
}

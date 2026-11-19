// The word panel and the sentence panel side by side, so they keep one look.
//
// Run:  flutter test qa_test/panels_look_test.dart   (writes qa-report/panels/*.png)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/sentence_sheet.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';

import 'picture_book_test.dart' show loadFonts;

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/panels');

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
    app = AppState(d, UserDb.open(Directory.systemTemp.createTempSync('vb_panels')))
      ..localAi = KeyAi(UserDb.open(Directory.systemTemp.createTempSync('vb_panels_ai')));
  });

  const sentence = "'Well, my boy, tomorrow we must get a new coat for you.";
  const tr = 'Şimdilik, evladım, yarın sana yeni bir palto almalıyız.';

  for (final b in Brightness.values) {
    for (final lang in ['tr', 'en']) {
      testWidgets('panels ${b.name} $lang', (tester) async {
        uiEnglish = lang == 'en';
        const size = Size(1440, 1000);
        await tester.binding.setSurfaceSize(size);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        app.user.setSentenceAi(sentence.substring(1), tr, null);
        app.user.setSentenceAi(sentence, tr, null);
        final para = Para(1, 0, 'p', sentence);
        final a = analyze(app, sentence);
        final ti = a.tokens.indexWhere((t) => t.text == 'Well');
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: uiLocale,
          supportedLocales: uiLocales,
          localizationsDelegates: uiLocalizationsDelegates,
          theme: buildTheme(b),
          home: const Scaffold(body: SizedBox.expand()),
        ));
        final home = tester.element(find.byType(Scaffold));
        showWordSheet(home, app, 'Well', ctx: buildContext(app, para, a, ti));
        await tester.pump(const Duration(milliseconds: 600));
        await shot(tester, '${b.name}_${lang}_word');
        Navigator.of(home).pop();
        await tester.pump(const Duration(milliseconds: 600));
        showSentenceSheet(home, app, para, a, ti);
        await tester.pump(const Duration(milliseconds: 600));
        await shot(tester, '${b.name}_${lang}_sentence');
        await tester.drag(find.byType(ListView).last, const Offset(0, -800));
        await tester.pump(const Duration(milliseconds: 400));
        await shot(tester, '${b.name}_${lang}_sentence_words');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 5));
        uiEnglish = false;
      });
    }
  }
}

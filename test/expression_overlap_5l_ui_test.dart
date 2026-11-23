// Task 5L: the word panel for "on" in "was on hand" / "was on the bridge" /
// "The TV was on": no "sure" broadcast meaning where the particle has its own
// noun phrase, every meaning still reachable, TR/EN, phone width, dark theme.
// OVERLAP_SHOTS=<folder> also saves screenshots. Sentences written by Claude
// (regression cases, not human labels).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;
final shots = Platform.environment['OVERLAP_SHOTS'];

const blacky = 'Blacky the Crow was on hand promptly that afternoon.';
const bridge = 'He was on the bridge.';
const tv = 'The TV was on all night.';

WordContext ctxFor(String sentence, String word) {
  final toks = tokenize(sentence);
  final idx = toks.indexWhere((t) => t.lower == word);
  final ms = app.dict.matcher.match(toks).where((m) => m.tokens.contains(idx)).toList();
  return WordContext(sentence, toks, idx, ms, null, 1, 'Test book', paraId: 7);
}

Future<void> pumpAt(WidgetTester tester, Widget panel, {double width = 390, double height = 3000, Brightness b = Brightness.light, double ratio = 1}) async {
  tester.view.physicalSize = Size(width * ratio, height * ratio);
  tester.view.devicePixelRatio = ratio;
  await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: uiLocale,
      supportedLocales: uiLocales,
      localizationsDelegates: uiLocalizationsDelegates,
      theme: buildTheme(b),
      home: Scaffold(body: SafeArea(child: panel))));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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

void main() {
  setUpAll(() {
    final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_5l_ui'));
    app = AppState(d, u)..localAi = KeyAi(u);
  });
  tearDown(() => uiEnglish = false);

  for (final english in [false, true]) {
    for (final (width, b) in [(390.0, Brightness.light), (320.0, Brightness.dark)]) {
      final tag = '${english ? 'EN' : 'TR'} ${width.toInt()} ${b.name}';
      testWidgets('5L $tag: "was on hand" shows on hand, be on only as "may not be meant here"', (tester) async {
        uiEnglish = english;
        await pumpAt(tester, WordPanel(app: app, surface: 'on', ctx: ctxFor(blacky, 'on')), width: width, b: b);
        expect(find.textContaining('hazırda'), findsWidgets, reason: 'on hand');
        expect(find.byKey(const ValueKey('expr-card-maybe-not-here')), findsOneWidget, reason: 'be on kept, with the note');
        expect(tester.takeException(), isNull);
      });
      testWidgets('5L $tag: "was on the bridge": be on only as "may not be meant here"', (tester) async {
        uiEnglish = english;
        await pumpAt(tester, WordPanel(app: app, surface: 'on', ctx: ctxFor(bridge, 'on')), width: width, b: b);
        expect(find.byKey(const ValueKey('expr-card-maybe-not-here')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
      testWidgets('5L $tag: "The TV was on": be on is the expression, no note', (tester) async {
        uiEnglish = english;
        await pumpAt(tester, WordPanel(app: app, surface: 'on', ctx: ctxFor(tv, 'on')), width: width, b: b);
        expect(find.byKey(const ValueKey('expr-card-maybe-not-here')), findsNothing);
        expect(find.textContaining('yayında', findRichText: true), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('5L screenshots', (tester) async {
    if (shots == null) return;
    await tester.runAsync(loadFonts);
    Future<void> shot(String name, String s, {bool en = false, double width = 390, Brightness b = Brightness.light}) async {
      uiEnglish = en;
      await pumpAt(tester, WordPanel(app: app, surface: 'on', ctx: ctxFor(s, 'on')), width: width, height: 1500, b: b, ratio: 2);
      await tester.runAsync(() async {
        final img = await captureImage(find.byType(MaterialApp).evaluate().first);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$shots/$name.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot('tr_was_on_hand_5l', blacky);
    await shot('en_was_on_hand_320_dark_5l', blacky, en: true, width: 320, b: Brightness.dark);
    await shot('tr_was_on_the_bridge_5l', bridge);
    await shot('tr_tv_was_on_5l', tv);
    await shot('en_tv_was_on_320_5l', tv, en: true, width: 320);
  });
}

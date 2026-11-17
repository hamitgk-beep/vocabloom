// The grammar filters in the reader: they are in the Filters menu, colour the
// words in the book, and a tap opens the explanation with a link to the
// Grammar topic. GRAMMAR_SHOTS=<folder> also saves screenshots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/nlp/grammar_marks.dart';
import 'package:kelime_okur/ui/grammar/grammar_page.dart';
import 'package:kelime_okur/ui/grammar_mark_sheet.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;
final shots = Platform.environment['GRAMMAR_SHOTS'];

const text =
    'If she had studied harder, she would have passed the exam. The man who lives next door said that he was tired. '
    'I enjoy reading and want to learn more. This is the most beautiful garden in the city.';

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

Widget shell(Widget home, {Brightness b = Brightness.light}) =>
    MaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, locale: uiLocale, supportedLocales: uiLocales, localizationsDelegates: uiLocalizationsDelegates, theme: buildTheme(b), home: home);

/// Colour of each word in the paragraph's RichText.
Map<String, Color?> wordColors(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.descendant(of: find.byType(ParagraphView), matching: find.byType(RichText)).first);
  final out = <String, Color?>{};
  rich.text.visitChildren((s) {
    final t = (s as TextSpan).text ?? '';
    if (RegExp(r'^[A-Za-z]+$').hasMatch(t)) out.putIfAbsent(t, () => s.style?.color);
    return true;
  });
  return out;
}

void main() {
  setUpAll(() async {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_gf'));
    app = AppState(d, u)..localAi = KeyAi(u);
    if (shots != null) await loadFonts();
  });

  tearDown(() => uiEnglish = false);

  Future<void> reader(WidgetTester tester, {Brightness b = Brightness.light, void Function(ParaAnalysis a, int i)? onTap}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      shell(
        b: b,
        Scaffold(
          body: Builder(
            builder: (context) => ListenableBuilder(
              listenable: app,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ParagraphView(
                    app: app,
                    para: Para(1, 0, 'p', text),
                    onWord: (p, a, i) {
                      onTap?.call(a, i);
                      final marks = a.grammarAt(app, i);
                      if (a.shownAt(app, i).mark != null) showGrammarMarkSheet(context, app, a, marks, i, onWord: () {});
                    },
                    onSentence: (_, __, ___) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // The Grammar topics are read from the assets once.
    await tester.runAsync(loadGrammarTopics);
  }

  testWidgets('the six grammar filters are in the Filters menu', (tester) async {
    app.setAllCats(false);
    tester.view.physicalSize = Size(390, shots == null ? 6000 : 1600); // the test font is wider than the app's
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell(Scaffold(body: FilterPanel(app: app))));
    await tester.pump();
    // Three groups; the grammar group opens with a tap.
    expect(find.text('Kalıplar ve deyimler'), findsOneWidget);
    expect(find.text('Kelime türleri'), findsOneWidget);
    expect(find.byKey(const ValueKey('filter-g_tenses')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('filter-group-1')));
    await tester.pump();
    for (final id in grammarCatIdsForTest) {
      expect(find.byKey(ValueKey('filter-$id')), findsOneWidget, reason: id);
    }
    expect(find.text('Zamanlar'), findsOneWidget);
    expect(find.text('Koşul cümleleri'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filter-g_tenses')));
    await tester.pump();
    expect(app.enabledCats, contains('g_tenses'));
    // The three tense colours are explained under the filter.
    expect(find.text('geçmiş'), findsOneWidget);
    await shot(tester, 'filters_tr');
    app.setAllCats(true);
    expect(app.enabledCats, containsAll(grammarCatIdsForTest));
    app.setAllCats(false);
  });

  testWidgets('words are coloured by their grammar filter', (tester) async {
    app.setAllCats(false);
    await reader(tester);
    var c = wordColors(tester);
    expect(c['studied'], isNull);
    app.toggleCat('g_tenses');
    await tester.pump();
    c = wordColors(tester);
    expect(c['studied'], tenseToneColors[1]); // past perfect: past
    expect(c['lives'], tenseToneColors[0]); // present
    app.toggleCat('g_tenses');
    app.toggleCat('g_conditionals');
    app.toggleCat('g_relative');
    app.toggleCat('g_gerund_inf');
    app.toggleCat('g_comparison');
    app.toggleCat('g_reported');
    await tester.pump();
    c = wordColors(tester);
    expect(c['If'], categoryById['g_conditionals']!.color);
    expect(c['who'], categoryById['g_relative']!.color);
    expect(c['enjoy'], categoryById['g_gerund_inf']!.color);
    expect(c['beautiful'], categoryById['g_comparison']!.color);
    expect(c['said'], categoryById['g_reported']!.color);
    app.toggleCat('g_tenses');
    await tester.pump();
    await shot(tester, 'reader_all_grammar');
    app.setAllCats(false);
  });

  testWidgets('tapping a coloured word explains it and links to the Grammar topic', (tester) async {
    app.setAllCats(false);
    app.toggleCat('g_tenses');
    app.toggleCat('g_conditionals');
    await reader(tester);
    await tester.tap(find.byType(ParagraphView), warnIfMissed: false);
    // Tap "studied": the paragraph's first line.
    final a = analyze(app, text);
    final i = a.tokens.indexWhere((t) => t.text == 'studied');
    final marks = a.grammarAt(app, i);
    expect(marks.map((m) => m.key), ['past_perfect', 'cond_3']);
    final ctx = tester.element(find.byType(ParagraphView));
    showGrammarMarkSheet(ctx, app, a, marks, i, onWord: () {});
    await tester.pumpAndSettle();
    expect(find.text('Past Perfect'), findsOneWidget);
    expect(find.text('Third Conditional'), findsOneWidget);
    expect(find.byKey(const ValueKey('gm-lesson-third_conditional')), findsOneWidget);
    await shot(tester, 'sheet_conditional_tr');
    await tester.ensureVisible(find.byKey(const ValueKey('gm-lesson-third_conditional')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('gm-lesson-third_conditional')));
    await tester.pumpAndSettle();
    expect(find.byType(GrammarTopicPage), findsOneWidget);
    app.setAllCats(false);
  });

  testWidgets('English interface and dark mode', (tester) async {
    uiEnglish = true;
    app.setAllCats(false);
    app.toggleCat('g_reported');
    app.toggleCat('g_tenses');
    await reader(tester, b: Brightness.dark);
    final a = analyze(app, text);
    final i = a.tokens.indexWhere((t) => t.text == 'said');
    final ctx = tester.element(find.byType(ParagraphView));
    showGrammarMarkSheet(ctx, app, a, a.grammarAt(app, i), i, onWord: () {});
    await tester.pumpAndSettle();
    expect(find.text('Reported Speech (statement)'), findsOneWidget);
    expect(find.textContaining('Grammar topic:'), findsWidgets);
    await shot(tester, 'sheet_reported_en_dark');
    app.setAllCats(false);
  });
}

const grammarCatIdsForTest = grammarCatIds;

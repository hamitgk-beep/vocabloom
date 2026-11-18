// The "meaning in this sentence" card in the word and expression panels:
// sure / possible / none, the "Wrong meaning" report (kept apart from the
// learner's data) and "Ask the AI" without a key. CONTEXT_SHOTS=<folder>
// also saves screenshots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:kelime_okur/ui/expr_sheet.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;
final shots = Platform.environment['CONTEXT_SHOTS'];

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

Future<void> shot(WidgetTester tester, String name, Widget panel, {Brightness b = Brightness.light, double height = 1100}) async {
  tester.view.physicalSize = Size(420 * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      locale: uiLocale,
      supportedLocales: uiLocales,
      localizationsDelegates: uiLocalizationsDelegates,
      theme: buildTheme(b),
      home: Scaffold(body: SafeArea(child: panel))));
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

WordContext ctxFor(String sentence, String word, {int occurrence = 0}) {
  final toks = tokenize(sentence);
  var seen = 0, idx = -1;
  for (var i = 0; i < toks.length; i++) {
    if (toks[i].lower == word && seen++ == occurrence) idx = i;
  }
  final ms = app.dict.matcher.match(toks).where((m) => m.tokens.contains(idx)).toList();
  return WordContext(sentence, toks, idx, ms, null, 1, 'Test book', paraId: 7);
}

Future<void> pumpPanel(WidgetTester tester, Widget panel, {double height = 844}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(key: UniqueKey(), theme: buildTheme(Brightness.light), home: Scaffold(body: panel)));
  await tester.pump();
}

void main() {
  setUpAll(() {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_cs'));
    app = AppState(d, u)..localAi = KeyAi(u);
  });

  testWidgets('word panel: the meaning in the sentence comes first, other meanings after', (tester) async {
    await pumpPanel(tester, WordPanel(app: app, surface: 'bank', ctx: ctxFor('The bank approved the loan.', 'bank')));
    expect(find.byKey(const ValueKey('ctx-sense-card')), findsOneWidget);
    expect(find.text('BU CÜMLEDEKİ ANLAMI'), findsOneWidget);
    expect(find.text('banka'), findsWidgets);
    expect(find.text('DİĞER SÖZLÜK ANLAMLARI'), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx-sense-wrong')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx-sense-ai')), findsOneWidget);
    // The rest of the panel is still there.
    expect(find.text('Öğreneceğim'), findsOneWidget);
    expect(find.text('Kelime ailesi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a guess is shown as a guess', (tester) async {
    await pumpPanel(tester, WordPanel(app: app, surface: 'bank', ctx: ctxFor('They sat on the river bank.', 'bank')));
    expect(find.text('BU CÜMLEDEKİ OLASI ANLAMI'), findsOneWidget);
    expect(find.textContaining('tahmin'), findsWidgets);
    expect(find.text('BU CÜMLEDEKİ ANLAMI'), findsNothing);
  });

  testWidgets('no meaning found: short note, dictionary below, panel stays open', (tester) async {
    await pumpPanel(tester, WordPanel(app: app, surface: 'run', ctx: ctxFor('Cracks run through the wall.', 'run')));
    expect(find.byKey(const ValueKey('ctx-sense-card')), findsOneWidget);
    expect(find.text('BU CÜMLEDEKİ ANLAMI'), findsNothing);
    expect(find.byKey(const ValueKey('ctx-sense-wrong')), findsNothing);
    expect(find.byKey(const ValueKey('ctx-sense-ai')), findsOneWidget);
    // "run through" is literal here: the word's own sense is the one that
    // takes the particle into account, not a guess that ignores it.
    expect(find.textContaining('stretch'), findsWidgets);
    expect(find.text('progress by being changed'), findsNothing);
    expect(find.text('koşmak'), findsNothing); // not offered above the card as the answer
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Wrong meaning" writes a report and nothing else', (tester) async {
    final words = app.user.db.select('SELECT COUNT(*) AS n FROM words').first['n'];
    final before = app.user.senseFeedbackCount();
    await pumpPanel(tester, WordPanel(app: app, surface: 'know', ctx: ctxFor('I know her very well.', 'know')));
    await tester.ensureVisible(find.byKey(const ValueKey('ctx-sense-wrong')));
    await tester.tap(find.byKey(const ValueKey('ctx-sense-wrong')));
    await tester.pump();
    expect(app.user.senseFeedbackCount(), before + 1);
    expect(find.text('Bildirildi'), findsOneWidget);
    final tsv = app.user.senseFeedbackTsv().trim().split('\n');
    expect(tsv.first, startsWith('time\tword\tsentence\tsense_id\tshown_tr\tconfidence\tdict_version\tengine_version'));
    final row = tsv.last.split('\t');
    expect(row[1], 'know');
    expect(row[2], 'I know her very well.');
    expect(row[3], startsWith('wn:'));
    expect(row[4], contains('tanımak'));
    expect(row[6], DictDb.version);
    // The word list is untouched.
    expect(app.user.db.select('SELECT COUNT(*) AS n FROM words').first['n'], words);
  });

  testWidgets('expression panel: "looked up at the sky" marks the "raise eyes" sense', (tester) async {
    const s = 'She looked up at the sky.';
    final c = ctxFor(s, 'looked');
    final e = app.dict.exprs.firstWhere((e) => e.phrase == 'look up' && e.cat == 'phrasal_verbs');
    await pumpPanel(tester, ExprPanel(app: app, expr: e, ctx: c, words: const ['looked', 'up']), height: 3000);
    expect(find.byKey(const ValueKey('ctx-sense-card')), findsOneWidget);
    expect(find.text('yukarı bakmak'), findsOneWidget);
    expect(find.text('Bu cümledeki anlamı'), findsOneWidget); // on the matching sense card below
    expect(tester.takeException(), isNull);
  });

  testWidgets('opened from a list (no sentence): no card, panel as before', (tester) async {
    await pumpPanel(tester, WordPanel(app: app, surface: 'bank', lemma: 'bank'));
    expect(find.byKey(const ValueKey('ctx-sense-card')), findsNothing);
    expect(find.text('banka'), findsWidgets);
  });

  testWidgets('"I don\'t understand" opens the plain explanation and the request is kept', (tester) async {
    final reportsBefore = app.user.senseFeedbackCount();
    await pumpPanel(tester, WordPanel(app: app, surface: 'know', ctx: ctxFor('I know her very well.', 'know')));
    await tester.ensureVisible(find.byKey(const ValueKey('ctx-sense-help')));
    await tester.tap(find.byKey(const ValueKey('ctx-sense-help')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ctx-sense-help-text')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx-sense-help')), findsNothing);
    expect(app.user.senseHelpShown('know', 'I know her very well.'), isTrue);
    // A request is not a wrong-meaning report.
    expect(app.user.senseFeedbackCount(), reportsBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"I don\'t understand" without a written explanation says what the word means here', (tester) async {
    await pumpPanel(tester, WordPanel(app: app, surface: 'bank', ctx: ctxFor('The bank approved the loan.', 'bank')));
    await tester.ensureVisible(find.byKey(const ValueKey('ctx-sense-help')));
    await tester.tap(find.byKey(const ValueKey('ctx-sense-help')));
    await tester.pump();
    expect(find.textContaining('“banka” anlamında kullanılmış'), findsOneWidget);
    expect(find.textContaining('kısa açıklaması sözlükte yok'), findsNothing);
  });

  testWidgets('a report can be withdrawn; the state is still there after a restart', (tester) async {
    final old = app.user.activeSenseFeedbackId('know', 'I know her very well.');
    if (old != null) app.user.withdrawSenseFeedback(old);
    final before = app.user.senseFeedbackCount();
    await pumpPanel(tester, WordPanel(app: app, surface: 'know', ctx: ctxFor('I know her very well.', 'know')), height: 1300);
    await tester.ensureVisible(find.byKey(const ValueKey('ctx-sense-wrong')));
    await tester.tap(find.byKey(const ValueKey('ctx-sense-wrong')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ctx-sense-undo')), findsOneWidget);
    // A new panel, as after a restart: the report is still active, not sent twice.
    await pumpPanel(tester, WordPanel(app: app, surface: 'know', ctx: ctxFor('I know her very well.', 'know')), height: 1300);
    await tester.pump();
    expect(find.byKey(const ValueKey('ctx-sense-undo')), findsOneWidget);
    expect(find.text('Bildirildi'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('ctx-sense-undo')));
    await tester.tap(find.byKey(const ValueKey('ctx-sense-undo')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ctx-sense-undo')), findsNothing);
    expect(app.user.senseFeedbackCount(), before + 1, reason: 'the row stays, marked as withdrawn');
    expect(app.user.activeSenseFeedbackId('know', 'I know her very well.'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screenshots', (tester) async {
    if (shots == null) return;
    await tester.runAsync(loadFonts);
    ExprPanel expr(String s, String phrase, List<String> words, String first) => ExprPanel(
        app: app,
        expr: app.dict.exprs.firstWhere((e) => e.phrase == phrase && e.cat == 'phrasal_verbs'),
        ctx: ctxFor(s, first),
        words: words);
    await shot(tester, 'tr_run_through_plan', expr("Let's run through the plan.", 'run through', const ['run', 'through'], 'run'));
    await shot(tester, 'tr_know_her', WordPanel(app: app, surface: 'know', ctx: ctxFor('I know her very well.', 'know')));
    await shot(tester, 'tr_river_bank_olasi', WordPanel(app: app, surface: 'bank', ctx: ctxFor('They sat on the river bank.', 'bank')));
    await shot(tester, 'tr_cracks_yok', WordPanel(app: app, surface: 'run', ctx: ctxFor('Cracks run through the wall.', 'run')));
    await shot(tester, 'tr_lived_in_dark', WordPanel(app: app, surface: 'lived', ctx: ctxFor('Dorothy lived in Kansas.', 'lived')),
        b: Brightness.dark);
    uiEnglish = true;
    await shot(tester, 'en_looked_up_sky', expr('She looked up at the sky.', 'look up', const ['looked', 'up'], 'looked'));
    uiEnglish = false;
  });
}

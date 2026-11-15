// Interface language check: opens every screen, menu, dialog and panel twice,
// once with the app language set to Türkçe and once to English, and fails when
// a heading, button, hint, tooltip or explanation is in the other language.
//
//   * English UI: no Turkish text outside learning content (Turkish meanings
//     and practice sentences are allowed only where they are the lesson).
//   * Turkish UI: no English interface text. A line that reads as English and
//     looks exactly the same in both languages is reported; English learning
//     content (example sentences, words, book text) is told apart by its blue
//     "English" colour or by coming from the dictionary, the book or a lesson.
//
// Screenshots of every screen in both languages go to qa-report/lang/ and the
// full text of each screen to qa-report/lang/texts-<lang>.tsv.
//
// Run:  flutter test qa_test/language_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/ai/local_ai.dart';
import 'package:kelime_okur/ai/packages.dart';
import 'package:kelime_okur/ai/tutor.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/main.dart';
import 'package:kelime_okur/nlp/text.dart' show displayPhrase;
import 'package:kelime_okur/online/ai_service.dart';
import 'package:kelime_okur/ui/ai/ai_page.dart';
import 'package:kelime_okur/ui/ai/ai_tools.dart';
import 'package:kelime_okur/ui/expr_sheet.dart';
import 'package:kelime_okur/ui/grammar/grammar_page.dart';
import 'package:kelime_okur/ui/key_guide.dart';
import 'package:kelime_okur/ui/library_page.dart';
import 'package:kelime_okur/ui/onboarding.dart';
import 'package:kelime_okur/ui/other_pages.dart';
import 'package:kelime_okur/ui/settings_page.dart';
import 'package:kelime_okur/ui/panel.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/review_page.dart';
import 'package:kelime_okur/ui/sentence_sheet.dart';
import 'package:kelime_okur/ui/tap_text.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';

final outDir = Directory('${Platform.environment['QA_OUT'] ?? 'qa-report'}/lang');
final bool shots = Platform.environment['QA_SHOTS'] != '0';
const phone = Size(390, 844);

/// A model that answers instantly, so the AI screens can be opened.
class _FakeAi extends LocalAi {
  bool fail = false;
  @override
  List<AiPackage> get packages => aiPackages;
  @override
  Future<Set<String>> installed() async => fail ? {} : {aiPackages.first.id};
  @override
  Map<String, AiDownload> get downloads => {};
  @override
  Stream<AiDownload> download(String id) => const Stream.empty();
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  String? get activeId => fail ? null : aiPackages.first.id;
  @override
  Future<void> setActive(String id) async {}
  @override
  bool get premiumUnlocked => false;
  @override
  Future<int?> deviceRamMb() async => 8192;
  @override
  bool get loaded => true;
  @override
  Stream<String> generate(String system, List<(String, String)> messages, {int maxTokens = 512, double temperature = 0.3}) =>
      fail ? Stream.error(Exception('no model')) : Stream.fromIterable([L('**Tamam.**', '**OK.**')]);
  @override
  void stop() {}
  @override
  Future<void> unload() async {}
}

late AppState app;
late _FakeAi fakeAi;
late List<GrammarTopic> lessons;

/// Text that is the lesson, not the interface: dictionary words, book text,
/// grammar examples and practice sentences.
final content = <String>{};

/// Each screen's text per interface language: screen -> lang -> lines.
final texts = <String, Map<String, List<(String, bool)>>>{};
final failures = <String>[];

// ------------------------------------------------------------------ language

final _trLetters = RegExp(r'[çğışöüÇĞİŞÖÜâÂ]');
const _trWords = {
  've', 'bir', 'bu', 'için', 'ile', 'kelime', 'kelimeler', 'kitap', 'kitaplar', 'ses', 'gibi', 'daha', 'çok', 'değil',
  'var', 'yok', 'sonra', 'önce', 'her', 'şu', 'veya', 'ya', 'da', 'de', 'mi', 'ne', 'olarak', 'kadar', 'göre', 'tüm',
  'sil', 'iptal', 'tamam', 'kapat', 'aç', 'ekle', 'indir', 'ayarlar', 'dinle', 'tekrar', 'konu', 'cümle', 'anlam',
  'seç', 'geri', 'ileri', 'devam', 'başla', 'bitir', 'kaydet', 'yükleniyor', 'hazır', 'yeni', 'eski', 'büyük', 'küçük',
};
const _enWords = {
  'the', 'and', 'of', 'to', 'your', 'you', 'with', 'for', 'this', 'is', 'are', 'an', 'in', 'on', 'not', 'no', 'it',
  'be', 'can', 'will', 'from', 'or', 'all', 'words', 'word', 'book', 'books', 'settings', 'open', 'add', 'delete',
  'cancel', 'close', 'download', 'voice', 'try', 'again', 'more', 'show', 'hide', 'tap', 'press', 'here', 'when',
  'save', 'next', 'back', 'done', 'skip', 'retry', 'loading', 'start', 'stop', 'listen', 'read', 'reading',
  'meaning', 'meanings', 'example', 'examples', 'sentence', 'sentences', 'level', 'topic', 'topics', 'practice',
  'review', 'learn', 'learned', 'learning', 'library', 'dictionary', 'about', 'version', 'language', 'app', 'new',
  'continue', 'later', 'update', 'help', 'test', 'connection', 'key', 'model', 'models', 'tutor', 'grammar',
  'explain', 'correct', 'chat', 'quiz', 'family', 'filter', 'filters', 'speed', 'font', 'size', 'theme', 'dark',
  'light', 'day', 'night', 'off', 'none', 'yes', 'ok',
};
/// Names, brands and terms that are written the same in both languages.
final _sameInBoth = <RegExp>[
  RegExp(r'^VocaBloom'), RegExp(r'^(Türkçe|English)$'), RegExp(r'^[A-C][12]$'), RegExp(r'^(BETA|OK|PDF|EPUB|API)$'),
  RegExp(r'^(Anthropic|OpenAI|Google|Microsoft|DeepSeek|Mistral|xAI|Groq|OpenRouter|Ollama)\b'),
  RegExp(r'^(Kokoro|Piper|Fahrettin|Fettah|Supertonic)\b'),
  RegExp(r'^Qwen'), RegExp(r'^Aa$'), RegExp(r'^A$'),
  // The language switch is labelled in both languages so anyone can find it.
  RegExp(r'^Uygulama dili / App language$'),
  // Names: the developer, and the KeNet authors in the licence list.
  RegExp(r'Hamit Gök|Özyeğin'),
];

bool _looksTurkish(String s) {
  // A Turkish phrase in quotes inside an English explanation is the example.
  s = s.replaceAll(RegExp(r'"[^"]*"|“[^”]*”'), '');
  if (_trLetters.hasMatch(s)) return true;
  final w = s.toLowerCase().split(RegExp(r'[^a-zçğışöü]+')).where((x) => x.isNotEmpty);
  return w.where(_trWords.contains).length >= 2;
}

bool _looksEnglish(String s) {
  if (_trLetters.hasMatch(s)) return false;
  final w = s.toLowerCase().split(RegExp(r"[^a-z']+")).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return false;
  final hits = w.where(_enWords.contains).length;
  return hits >= 2 || (w.length <= 3 && hits >= 1);
}

bool _isContent(String s) {
  final t = s.trim();
  if (content.contains(t)) return true;
  // Quoted examples, word lists and dictionary headwords.
  for (final c in content) {
    if (c.length > 12 && t.contains(c)) return true;
  }
  return false;
}

// ------------------------------------------------------------------ capture

Color _en(BuildContext c) => enColor(Theme.of(c));

/// Every piece of text on screen, with "this is English-coloured" flag.
List<(String, bool)> _collect(WidgetTester tester) {
  final out = <(String, bool)>[];
  final root = find.byType(MaterialApp).evaluate().first;
  final en = _en(root);
  int? shownIndex;
  void visit(Element e) {
    final w = e.widget;
    if (w is Offstage && w.offstage) return;
    if (w is Visibility && !w.visible) return;
    if (w is IndexedStack) {
      shownIndex = w.index ?? 0;
    } else if (shownIndex != null && w.runtimeType.toString() == '_RawIndexedStack') {
      final only = shownIndex;
      shownIndex = null;
      var i = 0;
      e.visitChildren((k) {
        if (i++ == only) visit(k);
      });
      return;
    }
    // English learning text: every word can be tapped.
    if (w is TapText || w is ParagraphView || w is SentenceText) {
      final before = out.length;
      e.visitChildren(visit);
      for (var i = before; i < out.length; i++) {
        out[i] = (out[i].$1, true);
      }
      return;
    }
    if (w is RichText) {
      void span(InlineSpan s, Color? inherited) {
        if (s is! TextSpan) return;
        final c = s.style?.color ?? inherited;
        final t = s.text ?? '';
        if (t.trim().isNotEmpty) out.add((t.trim(), c != null && c.toARGB32() == en.toARGB32()));
        for (final k in s.children ?? const <InlineSpan>[]) {
          span(k, c);
        }
      }

      span(w.text, w.text.style?.color);
    } else if (w is Tooltip && (w.message ?? '').isNotEmpty) {
      out.add((w.message!, false));
    } else if (w is EditableText && w.controller.text.isNotEmpty) {
      // Typed text is the learner's, not the interface.
    }
    e.visitChildren(visit);
  }

  visit(root);
  return out;
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!shots) return;
  final el = find.byType(MaterialApp).evaluate().first;
  await tester.runAsync(() async {
    final img = await captureImage(el);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${outDir.path}/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  Object? ex;
  while ((ex = tester.takeException()) != null) {
    // A longer translation must not break the layout.
    if ('$ex'.contains('overflowed')) failures.add('${uiEnglish ? 'en' : 'tr'}\tlayout\t${'$ex'.split('\n').first}');
  }
}

String get _lang => uiEnglish ? 'en' : 'tr';

/// Records what is on screen now under [screen].
Future<void> capture(WidgetTester tester, String screen) async {
  await _settle(tester);
  texts.putIfAbsent(screen, () => {})[_lang] = _collect(tester);
  await _shot(tester, '${_lang}_$screen');
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

Future<BuildContext> blank(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(shell(Scaffold(body: Builder(builder: (c) {
    ctx = c;
    return const SizedBox.expand();
  }))));
  return ctx;
}

Future<void> tapText(WidgetTester tester, String tr, String en) async {
  final f = find.text(L(tr, en));
  if (f.evaluate().isEmpty) {
    failures.add('could not find "${L(tr, en)}" to tap');
    return;
  }
  await tester.ensureVisible(f.first);
  await tester.tap(f.first, warnIfMissed: false);
  await _settle(tester);
}

Future<void> tapIcon(WidgetTester tester, IconData icon) async {
  final f = find.byIcon(icon);
  if (f.evaluate().isEmpty) {
    failures.add('could not find icon $icon to tap');
    return;
  }
  await tester.tap(f.first, warnIfMissed: false);
  await _settle(tester);
}

// ------------------------------------------------------------------ screens

const sentence = 'Although it was very muddy, he never once thought of giving up the game.';

late int bookId;
const quizWords = ['though', 'work', 'although', 'differ'];

Future<void> allScreens(WidgetTester tester) async {
  // Learning panels show the meanings in the learner's language.
  app.showTr = !uiEnglish;
  app.showEn = true;

  // First launch.
  app.user.setSetting('onboarded', null);
  final booksBefore = app.user.books();
  for (final b in booksBefore) {
    app.user.deleteBook(b.id);
  }
  await tester.pumpWidget(shell(OnboardingPage(app: app, onDone: () {})));
  for (var i = 0; i < 3; i++) {
    await capture(tester, 'onboarding_${i + 1}');
    final next = find.byType(FilledButton);
    if (next.evaluate().isNotEmpty && i < 2) {
      await tester.tap(next.last);
      await _settle(tester);
    }
  }
  app.user.setSetting('onboarded', '1');

  // Empty library.
  await tester.pumpWidget(shell(LibraryPage(app: app)));
  await capture(tester, 'library_empty');
  bookId = await tester.runAsync(() => importForTest(app, 'test/fixtures/sample.epub')) ?? 0;
  await tester.runAsync(() => importForTest(app, 'test/fixtures/sample.txt'));

  // Main tabs, as the app shows them.
  app.user.setSetting('ai_tab', '1');
  await tester.pumpWidget(shell(HomePage(app: app)));
  await capture(tester, 'tab_library');
  final names = ['library', 'my_words', 'dictionary', 'grammar', 'ai', 'settings'];
  for (var i = 1; i < names.length && find.byKey(ValueKey('nav_$i')).evaluate().isNotEmpty; i++) {
    await tester.tap(find.byKey(ValueKey('nav_$i')));
    await capture(tester, 'tab_${names[i]}');
  }

  // Library: book menu and delete dialog.
  await tester.pumpWidget(shell(LibraryPage(app: app)));
  await _settle(tester);
  final menus = find.byType(PopupMenuButton<String>);
  if (menus.evaluate().isNotEmpty) {
    await tester.tap(menus.first);
    await capture(tester, 'library_book_menu');
    final del = find.text(L('Sil', 'Delete'));
    if (del.evaluate().isNotEmpty) {
      await tester.tap(del.last);
      await capture(tester, 'library_delete_dialog');
    }
  }

  // Words.
  for (final w in ['though', 'work', 'although', 'differ']) {
    app.setWord(w, WordStatus.learning, meaning: null);
  }
  app.setWord('give up', WordStatus.learned, meaning: null);
  await tester.pumpWidget(shell(WordsPage(app: app)));
  await capture(tester, 'my_words');

  // Dictionary categories and one list.
  await tester.pumpWidget(shell(CategoriesPage(app: app)));
  await capture(tester, 'dictionary');
  final tiles = find.byType(InkWell);
  if (tiles.evaluate().length > 3) {
    final firstCat = find.text(uiEnglish ? categories.first.name : categories.first.tr);
    if (firstCat.evaluate().isNotEmpty) {
      await tester.tap(firstCat.first);
      await capture(tester, 'dictionary_category');
    }
  }

  // Reader with its menus, opened from its own buttons.
  final book = app.user.books().firstWhere((b) => b.id == bookId);
  Future<void> reader() async {
    await tester.pumpWidget(shell(ReaderPage(app: app, book: book)));
    await _settle(tester);
  }

  await reader();
  await capture(tester, 'reader');
  await tapIcon(tester, Icons.text_fields_rounded);
  await capture(tester, 'reader_reading_settings');
  await reader();
  await tapIcon(tester, Icons.list);
  await capture(tester, 'reader_chapters');
  await reader();
  await tapIcon(tester, Icons.filter_alt_outlined);
  await capture(tester, 'reader_filters');

  // Panels opened from the text.
  {
    final c = await blank(tester);
    final para = Para(1, 0, 'p', sentence);
    final a = analyze(app, sentence);
    final ti = a.tokens.indexWhere((t) => t.text == 'thought');
    showWordSheet(c, app, 'thought', ctx: buildContext(app, para, a, ti));
    await capture(tester, 'panel_word');
    final fam = find.text(L('Kelime ailesi', 'Word Family'));
    if (fam.evaluate().isNotEmpty) {
      await tester.tap(fam.first);
      await capture(tester, 'panel_word_family');
    }
    final c2 = await blank(tester);
    showSentenceSheet(c2, app, para, a, ti);
    await capture(tester, 'panel_sentence');
    final c3 = await blank(tester);
    final e = app.dict.exprs.firstWhere((x) => x.phrase == 'give up');
    showExprSheet(c3, app, e, null);
    await capture(tester, 'panel_expression');
  }

  // Review.
  await tester.pumpWidget(shell(ReviewPage(app: app, cards: app.review.due(now: DateTime.now().add(const Duration(days: 1)), limit: 5))));
  await capture(tester, 'review_question');
  final show = find.byType(FilledButton);
  if (show.evaluate().isNotEmpty) {
    await tester.tap(show.first);
    await capture(tester, 'review_answer');
  }

  // Grammar: list, a topic, practice (with and without a model).
  await tester.pumpWidget(shell(GrammarPage(app: app)));
  await capture(tester, 'grammar');
  final topic = lessons.firstWhere((t) => t.id == 'although_despite', orElse: () => lessons.first);
  await tester.pumpWidget(shell(GrammarTopicPage(app: app, topic: topic)));
  await capture(tester, 'grammar_topic');
  fakeAi.fail = true;
  final tx = topic.exercises.firstWhere((e) => !e.isGap), gx = topic.exercises.firstWhere((e) => e.isGap);
  // Tall enough that the whole practice page (answer card, buttons) is built.
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  await tester.pumpWidget(shell(GrammarPracticePage(app: app, topic: topic, round: [tx, gx])));
  await capture(tester, 'grammar_practice');
  await tester.enterText(find.byType(TextField).first, 'I am going to the school');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await capture(tester, 'grammar_practice_no_model');
  fakeAi.fail = false;
  // The gap sentence, its hint, a wrong answer and the round score.
  await tapText(tester, 'Sıradaki cümle', 'Next sentence');
  await capture(tester, 'grammar_gap');
  await tester.tap(find.byKey(const ValueKey('grammar-hint')));
  await capture(tester, 'grammar_gap_hint');
  await tester.enterText(find.byType(TextField).first, 'xyz');
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await capture(tester, 'grammar_gap_answer');
  await tapText(tester, 'Sonucu gör', 'See your score');
  await capture(tester, 'grammar_score');
  await tester.binding.setSurfaceSize(null);

  // AI: without a model, with a model and each tool.
  fakeAi.fail = true;
  await tester.pumpWidget(shell(AiPage(ai: fakeAi, tutor: Tutor(app, fakeAi))));
  await capture(tester, 'ai_no_model');
  fakeAi.fail = false;
  await tester.pumpWidget(shell(AiPage(ai: fakeAi, tutor: Tutor(app, fakeAi))));
  await capture(tester, 'ai');
  for (final tool in AiTool.values) {
    await tester.pumpWidget(shell(AiToolPage(tool: tool, ai: fakeAi, tutor: Tutor(app, fakeAi), quizWords: quizWords)));
    await capture(tester, 'ai_tool_${tool.name}');
  }

  // Settings and the API key guides.
  await tester.pumpWidget(shell(SettingsPage(app: app)));
  await capture(tester, 'settings');
  final dd = find.byType(DropdownButton<ThemeMode>);
  if (dd.evaluate().isNotEmpty) {
    await tester.tap(dd.first);
    await capture(tester, 'settings_theme_menu');
  }
  final sub = <String, Widget>{
    'settings_voices': const VoiceSettingsPage(),
    'settings_ai_service': AiServicePage(app: app),
    'settings_about': const AboutPage(),
    'settings_licenses': const LicensesPage(),
  };
  for (final MapEntry(key: name, value: page) in sub.entries) {
    await tester.pumpWidget(shell(page));
    await capture(tester, name);
  }
  for (final p in providers) {
    await tester.pumpWidget(shell(Scaffold(body: SingleChildScrollView(child: KeyGuideCard(providerId: p.id)))));
    await capture(tester, 'key_guide_${p.id}');
  }
}

// ------------------------------------------------------------------ report

void check() {
  final rows = <String>[];
  for (final MapEntry(key: screen, value: byLang) in texts.entries) {
    final tr = byLang['tr'] ?? const [];
    final en = byLang['en'] ?? const [];
    final trSet = {for (final (t, _) in tr) t};
    final enSet = {for (final (t, _) in en) t};
    for (final (t, isEn) in en) {
      if (isEn || _isContent(t) || _sameInBoth.any((r) => r.hasMatch(t))) continue;
      if (_looksTurkish(t)) rows.add('en\t$screen\tTurkish in the English interface\t$t');
    }
    for (final (t, isEn) in tr) {
      if (isEn || _isContent(t) || _sameInBoth.any((r) => r.hasMatch(t))) continue;
      if (enSet.contains(t) && _looksEnglish(t)) rows.add('tr\t$screen\tEnglish in the Turkish interface\t$t');
    }
    // A screen whose text did not change at all did not switch language.
    if (tr.isNotEmpty && en.isNotEmpty && trSet.length > 3 && trSet.difference(enSet).isEmpty) {
      rows.add('both\t$screen\tsame text in both languages\t${trSet.take(5).join(' | ')}');
    }
  }
  outDir.createSync(recursive: true);
  final uniq = rows.toSet().toList();
  File('${outDir.path}/problems.tsv').writeAsStringSync('lang\tscreen\tproblem\ttext\n${uniq.join('\n')}\n');
  for (final lang in ['tr', 'en']) {
    final b = StringBuffer('screen\tenglish_colour\ttext\n');
    for (final MapEntry(key: screen, value: byLang) in texts.entries) {
      for (final (t, isEn) in byLang[lang] ?? const <(String, bool)>[]) {
        b.writeln('$screen\t${isEn ? 1 : 0}\t${t.replaceAll(RegExp(r'\s+'), ' ')}');
      }
    }
    File('${outDir.path}/texts-$lang.tsv').writeAsStringSync(b.toString());
  }
  failures.addAll(uniq);
}

// ------------------------------------------------------------------ test

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

void main() {
  setUpAll(() async {
    await _loadFonts();
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_lang'));
    app = AppState(d, u);
    fakeAi = _FakeAi();
    app.localAi = fakeAi;
    lessons = parseGrammarTopics(
        File('assets/grammar/lessons.json').readAsStringSync(), File('assets/grammar/lessons_en.json').readAsStringSync());
    for (final t in lessons) {
      content.addAll([for (final e in t.examples) ...[e.$1, e.$2]]);
      for (final e in t.exercises) {
        content.addAll([e.tr, ...e.answers]);
        if (e.isGap) {
          content.addAll([e.gap!, e.gapSolved, '"${e.gapSolved}"', e.gap!.replaceAll(GrammarExercise.gapMark, '  ______  ')]);
          content.addAll(hintWords(e));
        }
      }
    }
    content.add(sentence);
    // Dictionary expressions and their English definitions.
    for (final e in d.exprs) {
      content.addAll([e.phrase, displayPhrase(e.phrase)]);
      if (e.en != null) content.addAll(e.en!.split('\n').map((x) => x.trim()));
    }
    // Meanings shown in the word lists and the quiz.
    for (final w in [...quizWords, 'give up', 'decide', 'remember', 'improve', 'careful', 'borrow', 'journey', 'achieve', 'enough', 'suddenly', 'weather', 'appreciate']) {
      final m = app.shortMeaning(w);
      if (m != null) content.addAll([m, ...m.split(', ')]);
      final info = d.lookup(w);
      for (final t in [...info.trFreeDict, for (final s in info.senses) ...s.tr]) {
        content.addAll([t, ...t.split(',').map((x) => x.trim())]);
      }
    }
    // The English name of a grammar structure is shown under its Turkish title.
    for (final t in lessons) {
      content.add(t.titleEn);
    }
    // The first-launch demo of a word panel.
    content.addAll(['vazgeçmek, bırakmak', 'dar, ensiz', 'He never once thought of', 'the sea was', 'giving up', 'stormy', 'although', 'narrow', 'give up']);
  });

  testWidgets('every screen follows the interface language', (tester) async {
    await tester.binding.setSurfaceSize(phone);
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    for (final en in [false, true]) {
      uiEnglish = en;
      await allScreens(tester);
    }
    uiEnglish = false;
    // Book text and dictionary words are content.
    for (final b in app.user.books()) {
      for (final ch in app.user.chapters(b.id)) {
        content.add(ch.title);
        for (final p in app.user.paras(b.id, ch.idx)) {
          content.add(p.text);
        }
      }
    }
    check();
    expect(failures, isEmpty, reason: failures.take(80).join('\n'));
  });
}

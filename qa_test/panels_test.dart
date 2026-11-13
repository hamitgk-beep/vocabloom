// Release quality check: opens every kind of panel the way a reader does and
// looks for what Hamit keeps finding by hand.
//
//   * an English line (definition or example) with no Turkish under it
//   * a section heading with nothing under it
//   * text overflowing its box, or a panel that does not fit on the screen
//   * any exception while building a page
//
// Run:  flutter test qa_test            (writes qa-report/ui-*.tsv and screens/)
//       QA_WORDS=1000 QA_EXPRS=50 flutter test qa_test   (wider sweep)
//
// Content gaps that the nightly translation job is still filling are reported,
// not failed. Layout problems and empty headings fail the test.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/ui/expr_sheet.dart';
import 'package:kelime_okur/ui/other_pages.dart';
import 'package:kelime_okur/ui/panel.dart';
import 'package:kelime_okur/ui/paragraph_view.dart';
import 'package:kelime_okur/ui/review_page.dart';
import 'package:kelime_okur/ui/sentence_sheet.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';

final outDir = Directory(Platform.environment['QA_OUT'] ?? 'qa-report');
final int nWords = int.tryParse(Platform.environment['QA_WORDS'] ?? '') ?? 200;
final int nExprs = int.tryParse(Platform.environment['QA_EXPRS'] ?? '') ?? 15;
final bool shots = Platform.environment['QA_SHOTS'] != '0';

const phone = Size(390, 844);
const desktop = Size(1280, 800);

/// Sentences from Hamit's reviews: the reader panels he opened.
const readerCases = <(String, String)>[
  ('Though it is risky, it is worth taking the chance.', 'Though'),
  ('I will work hard to improve my grades.', 'work'),
  ('Although it was very muddy, the football game went on.', 'Although'),
  ('Their opinions differ on this matter.', 'differ'),
  ('We need to work out a better plan before Monday.', 'work'),
  ('The bird flew above the grass and landed on the fence.', 'above'),
  ('She usually takes the bus to school.', 'usually'),
  ('He gave up smoking last year.', 'gave'),
];

late AppState app;
final findings = <List<String>>[]; // kind, where, mode, text
final failures = <String>[];

final _seen = <String>{};

void note(String kind, String where, String mode, String text) {
  // The same line in the same panel is reported once (with the first mode).
  if (!_seen.add('$kind|$where|$text')) return;
  findings.add([kind, where, mode, text.replaceAll(RegExp(r'\s+'), ' ')]);
  if (kind == 'layout' || kind == 'empty-heading' || kind == 'exception') failures.add('$kind | $where | $mode | $text');
}

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      l.addFont(Future.value(ByteData.sublistView(bytes)));
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

AppState openApp() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_qa'));
  return AppState(d, u);
}

// ------------------------------------------------------------------ checks

bool _isEn(TextStyle? s, Color en) => s?.color != null && s!.color!.toARGB32() == en.toARGB32();

/// Language of the text inside [e]: 'en' (only English-coloured text),
/// 'tr' (some other-coloured text with letters), or null (no text).
String? _langOf(Element e, Color en) {
  var hasEn = false, hasOther = false;
  void visit(Element x) {
    final w = x.widget;
    if (w is RichText) {
      w.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').trim().isNotEmpty && RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(span.text!)) {
          // The colour is inherited from the parent span when not set.
          if (_isEn(span.style, en)) {
            hasEn = true;
          } else {
            hasOther = true;
          }
        }
        return true;
      });
      final root = w.text;
      if (root is TextSpan && (root.text ?? '').trim().isNotEmpty) {
        if (_isEn(root.style, en)) {
          hasEn = true;
        } else {
          hasOther = true;
        }
      }
      return;
    }
    x.visitChildren(visit);
  }

  visit(e);
  return hasOther ? 'tr' : (hasEn ? 'en' : null);
}

String _textOf(Element e) {
  final b = StringBuffer();
  void visit(Element x) {
    if (x.widget is RichText) {
      b.write((x.widget as RichText).text.toPlainText());
      b.write(' ');
      return;
    }
    x.visitChildren(visit);
  }

  visit(e);
  return b.toString().trim();
}

/// Walks every Column/ListView under [root] and reports English lines that
/// have no Turkish line right after them, and headings with nothing under them.
void auditTree(Element root, String where, String mode, Color en) {
  void visit(Element e) {
    final w = e.widget;
    if (w is RichText) {
      final t = w.text.toPlainText();
      if (t.contains('henüz hazır değil') || t.startsWith('Kelime kelime:')) note('no-turkish-yet', where, mode, t);
    }
    if ((w is Flex && w.direction == Axis.vertical) || w is SliverMultiBoxAdaptorWidget) {
      final kids = <Element>[];
      e.visitChildren(kids.add);
      for (var i = 0; i < kids.length; i++) {
        final lang = _langOf(kids[i], en);
        if (lang != 'en') continue;
        // An English block is fine if it contains its own Turkish (handled by
        // the recursion) or the next sibling is Turkish.
        final next = i + 1 < kids.length ? _langOf(kids[i + 1], en) : null;
        if (next == 'tr' && !_notTurkishLine(_textOf(kids[i + 1]))) continue;
        if (_hasVerticalChildren(kids[i])) continue; // look deeper instead
        note('english-only', where, mode, _textOf(kids[i]));
      }
      // Section: [title, Divider] and nothing else.
      if (kids.length == 2 && kids[1].widget is Divider) {
        note('empty-heading', where, mode, _textOf(kids[0]));
      }
      // A label like "Bu cümledeki anlamı:" as the last child of a column.
      if (kids.isNotEmpty) {
        final last = _textOf(kids.last);
        if (last.endsWith(':') && kids.last.widget is Text) note('empty-heading', where, mode, last);
      }
    }
    e.visitChildren(visit);
  }

  visit(root);
}

/// Lines that follow an English line but are not its Turkish: a section
/// heading in capitals, or the "not ready yet" notice.
bool _notTurkishLine(String t) {
  final letters = t.replaceAll(RegExp(r'[^A-Za-zÇĞİÖŞÜçğıöşü]'), '');
  if (letters.length > 3 && letters == letters.toUpperCase()) return true;
  return t.contains('henüz hazır değil') || t.startsWith('Kelime kelime:');
}

bool _hasVerticalChildren(Element e) {
  var found = false;
  void visit(Element x) {
    if (found) return;
    final w = x.widget;
    if ((w is Flex && w.direction == Axis.vertical) || w is SliverMultiBoxAdaptorWidget) {
      var n = 0;
      x.visitChildren((_) => n++);
      if (n > 1) {
        found = true;
        return;
      }
    }
    x.visitChildren(visit);
  }

  visit(e);
  return found;
}

void collectExceptions(WidgetTester tester, String where, String mode) {
  Object? ex;
  while ((ex = tester.takeException()) != null) {
    final s = ex.toString();
    note(s.contains('overflowed') ? 'layout' : 'exception', where, mode, s.split('\n').first);
  }
}

/// The open panel (bottom sheet or dialog) must fit on the screen.
void checkFits(WidgetTester tester, String where, String mode, Size screen) {
  for (final f in [find.byType(BottomSheet), find.byType(Dialog)]) {
    for (final e in f.evaluate()) {
      final box = e.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.bottom > screen.height + 0.5 || r.right > screen.width + 0.5 || r.top < -0.5) {
        note('layout', where, mode, 'panel is outside the screen: $r on $screen');
      }
    }
  }
}

// ------------------------------------------------------------------ helpers

/// A fresh app each time (a new key), so panels opened earlier are gone.
Widget shell(Brightness b, Widget home) => MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: buildTheme(b),
      home: home,
    );

Future<void> setSize(WidgetTester tester, Size s) async {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(s);
}

Future<void> shot(WidgetTester tester, String name) async {
  if (!shots) return;
  final el = find.byType(MaterialApp).evaluate().first;
  await tester.runAsync(() async {
    final img = await captureImage(el);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${outDir.path}/screens/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

/// Opens a panel from a button, the way the app does, checks it and closes it.
Future<void> openPanel(WidgetTester tester, Brightness b, Size size, String where, String mode,
    Future<void> Function(BuildContext) open, {String? shotName}) async {
  await setSize(tester, size);
  late BuildContext ctx;
  await tester.pumpWidget(shell(b, Scaffold(body: Builder(builder: (c) {
    ctx = c;
    return const SizedBox.expand();
  }))));
  open(ctx);
  await tester.pumpAndSettle();
  collectExceptions(tester, where, mode);
  checkFits(tester, where, mode, size);
  final panel = find.byType(ListView).evaluate();
  for (final e in panel) {
    auditTree(e, where, mode, enColor(Theme.of(ctx)));
  }
  if (shotName != null) await shot(tester, shotName);
}

/// Renders a panel body on a very tall surface so the whole content can be
/// looked at in one picture.
Future<void> fullLength(WidgetTester tester, Brightness b, String name, Widget body) async {
  if (!shots) return;
  await setSize(tester, const Size(430, 3200));
  await tester.pumpWidget(shell(b, Scaffold(body: body)));
  await tester.pumpAndSettle();
  collectExceptions(tester, name, 'full');
  await shot(tester, name);
}

String safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').toLowerCase();

void writeReport() {
  outDir.createSync(recursive: true);
  final f = File('${outDir.path}/ui-findings.tsv');
  final b = StringBuffer('kind\twhere\tmode\ttext\n');
  for (final r in findings) {
    b.writeln(r.map((x) => x.replaceAll('\t', ' ')).join('\t'));
  }
  f.writeAsStringSync(b.toString());
  final counts = <String, int>{};
  for (final r in findings) {
    counts[r[0]] = (counts[r[0]] ?? 0) + 1;
  }
  File('${outDir.path}/ui-summary.txt').writeAsStringSync(
      [for (final e in counts.entries) '${e.key}\t${e.value}'].join('\n'));
}

// ------------------------------------------------------------------ tests

void main() {
  setUpAll(() async {
    await loadFonts();
    app = openApp();
  });
  tearDownAll(writeReport);

  final modes = <(String, bool, bool)>[('tr+en', true, true), ('tr', true, false)];

  testWidgets('reader word panels from the review sentences', (tester) async {
    for (final b in Brightness.values) {
      for (final size in [phone, desktop]) {
        for (final (mode, tr, en) in modes) {
          app.showTr = tr;
          app.showEn = en;
          for (final (sentence, word) in readerCases) {
            final para = Para(1, 0, 'p', sentence);
            final a = analyze(app, sentence);
            final ti = a.tokens.indexWhere((t) => t.text == word);
            final where = 'reader "$word" in "$sentence"';
            final dev = size == phone ? 'phone' : 'desktop';
            final name = '${dev}_${b.name}_${safe(mode)}_word_${safe(word)}';
            await openPanel(tester, b, size, where, '$mode $dev ${b.name}',
                (c) => showWordSheet(c, app, word, ctx: buildContext(app, para, a, ti)),
                shotName: mode == 'tr+en' ? name : null);
            // Word Family tab.
            final fam = find.text('Word Family');
            if (fam.evaluate().isNotEmpty) {
              await tester.tap(fam.first);
              await tester.pumpAndSettle();
              collectExceptions(tester, '$where / Word Family', mode);
              for (final e in find.byType(ListView).evaluate()) {
                auditTree(e, '$where / Word Family', '$mode $dev ${b.name}', enColor(Theme.of(e)));
              }
              if (mode == 'tr+en') await shot(tester, '${name}_family');
            }
            // Long press: sentence analysis.
            await openPanel(tester, b, size, 'sentence "$sentence"', '$mode $dev ${b.name}',
                (c) => showSentenceSheet(c, app, para, a, ti < 0 ? 0 : ti),
                shotName: mode == 'tr+en' && word == readerCases.first.$2 ? '${dev}_${b.name}_sentence' : null);
          }
        }
      }
    }
    app.showTr = app.showEn = true;
    for (final (sentence, word) in readerCases.take(3)) {
      final para = Para(1, 0, 'p', sentence);
      final a = analyze(app, sentence);
      final ti = a.tokens.indexWhere((t) => t.text == word);
      await fullLength(tester, Brightness.light, 'full_word_${safe(word)}',
          WordPanel(app: app, surface: word, ctx: buildContext(app, para, a, ti)));
    }
  });

  testWidgets('dictionary: frequent words opened from a list', (tester) async {
    final words = [
      for (final r in app.dict.db.select(
          'SELECT w.word FROM wfreq w WHERE EXISTS (SELECT 1 FROM sense s WHERE s.lemma=w.word) ORDER BY w.n DESC LIMIT ?',
          [nWords]))
        r['word'] as String
    ];
    for (final (mode, tr, en) in modes) {
      app.showTr = tr;
      app.showEn = en;
      for (final w in words) {
        await openPanel(tester, Brightness.light, phone, 'word "$w"', mode,
            (c) => showWordSheet(c, app, w, lemma: w));
      }
    }
    app.showTr = app.showEn = true;
  });

  testWidgets('dictionary: expressions of every category', (tester) async {
    for (final cat in categories) {
      final list = app.dict.byCategory(cat.id);
      if (list.isEmpty) {
        note('empty-heading', 'category ${cat.id}', '', 'category has no entries');
        continue;
      }
      // Evenly spread over the alphabetical list.
      final step = (list.length / nExprs).ceil().clamp(1, 1 << 30);
      for (var i = 0; i < list.length; i += step) {
        final e = list[i];
        for (final (mode, tr, en) in modes) {
          app.showTr = tr;
          app.showEn = en;
          await openPanel(tester, Brightness.light, phone, '${cat.id} "${e.phrase}"', mode,
              (c) => showExprSheet(c, app, e, null),
              shotName: i == 0 && mode == 'tr+en' ? 'phone_light_expr_${cat.id}' : null);
        }
      }
    }
    app.showTr = app.showEn = true;
    for (final p in ['above grass', 'although', 'work out']) {
      final e = app.dict.exprs.where((x) => x.phrase == p).firstOrNull;
      if (e == null) continue;
      await fullLength(tester, Brightness.light, 'full_expr_${safe(p)}', ExprPanel(app: app, expr: e, words: p.split(' ')));
    }
  });

  testWidgets('pages: dictionary, my words, review, settings', (tester) async {
    for (final w in ['though', 'work', 'although', 'differ', 'above grass']) {
      app.setWord(w, WordStatus.learning, meaning: null);
    }
    for (final b in Brightness.values) {
      for (final size in [phone, desktop]) {
        final dev = size == phone ? 'phone' : 'desktop';
        await setSize(tester, size);
        final pages = <String, Widget>{
          'dictionary': CategoriesPage(app: app),
          'my_words': WordsPage(app: app),
          'settings': SettingsPage(app: app),
          'review': ReviewPage(app: app, cards: app.review.due(now: DateTime.now().add(const Duration(days: 1)), limit: 5)),
        };
        for (final MapEntry(key: name, value: page) in pages.entries) {
          await tester.pumpWidget(shell(b, page));
          await tester.pumpAndSettle();
          collectExceptions(tester, 'page $name', '$dev ${b.name}');
          await shot(tester, '${dev}_${b.name}_page_$name');
        }
      }
    }
  });

  test('no layout problems or empty headings', () {
    writeReport();
    expect(failures, isEmpty, reason: failures.take(40).join('\n'));
  });
}

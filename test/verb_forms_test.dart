// Tapping an irregular verb form ("found") keeps that form in the panel
// header and shows V1 / V2 / V3 under it, with the tapped form in bold.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/ui/word_sheet.dart';
import 'package:sqlite3/sqlite3.dart';

late AppState app;

/// Words of the V1/V2/V3 row, with whether each is bold.
Map<String, bool> formsRow(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.descendant(of: find.byKey(const ValueKey('verb-forms')), matching: find.byType(RichText)));
  final out = <String, bool>{};
  rich.text.visitChildren((s) {
    final t = (s as TextSpan).text?.trim() ?? '';
    if (RegExp(r'^[a-z]+$').hasMatch(t)) out[t] = s.style?.fontWeight == FontWeight.w800;
    return true;
  });
  return out;
}

Future<void> open(WidgetTester tester, String surface, {Brightness b = Brightness.light}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
      key: UniqueKey(), theme: buildTheme(b), home: Scaffold(body: WordPanel(app: app, surface: surface))));
  await tester.pump();
}

void main() {
  setUpAll(() {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(Directory.systemTemp.createTempSync('vocabloom_vf'));
    app = AppState(d, u)..localAi = KeyAi(u);
  });

  test('irregular verbs are loaded with their forms', () {
    expect(app.dict.irregular['find'], ['find', 'found', 'found']);
    expect(app.dict.irregularOf['found'], contains('find'));
    expect(app.dict.irregularOf['fell'], contains('fall'));
  });

  testWidgets('tapped V2 form stays in the header and is bold in the row', (tester) async {
    await open(tester, 'found');
    expect(find.text('found'), findsWidgets);
    final row = formsRow(tester);
    expect(row.keys, ['find', 'found']); // V2 and V3 are the same word
    expect(row['found'], isTrue);
    expect(row['find'], isFalse);
    expect(find.textContaining('V1'), findsOneWidget);
  });

  testWidgets('"fell" is a form of fall, not the verb "to fell"', (tester) async {
    await open(tester, 'fell', b: Brightness.dark);
    final row = formsRow(tester);
    expect(row['fell'], isTrue);
    expect(row['fall'], isFalse);
    expect(row['fallen'], isFalse);
  });

  testWidgets('base form is bold when V1 is tapped; "be" lists was / were', (tester) async {
    await open(tester, 'were');
    final row = formsRow(tester);
    expect(row['were'], isTrue);
    expect(row['be'], isFalse);
    expect(row['was'], isFalse);
    expect(row['been'], isFalse);
  });

  testWidgets('regular verbs get no V1/V2/V3 row', (tester) async {
    await open(tester, 'worked');
    expect(find.byKey(const ValueKey('verb-forms')), findsNothing);
  });
}

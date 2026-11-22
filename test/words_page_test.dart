// Word notebook: To learn / Learned / By book chips, today's review card,
// and "review today / tomorrow" on each To learn word.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/review.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/other_pages.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late DictDb dict;
  setUpAll(() {
    dict = DictDb();
    dict.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    dict.load();
  });

  testWidgets('word notebook views', (tester) async {
    uiEnglish = false;
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_words'));
    final app = AppState(dict, u)..localAi = KeyAi(u);
    u.setWord('frost', WordStatus.learning, context: 'The grass was white with frost.', book: 'Winter Tales');
    u.setWord('gale', WordStatus.learning);
    u.setWord('bitter', WordStatus.learned, book: 'Winter Tales');
    // gale was answered "Knew it" once: its next review is not today.
    app.review.answer('gale', 0, ReviewAnswer.good);
    expect(app.review.dueCount(), 1);

    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: WordsPage(app: app)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.text('Öğreneceğim · 2'), findsOneWidget);
    expect(find.text('Öğrendim · 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('words-today-review')), findsOneWidget);
    expect(find.text('tekrar bugün'), findsOneWidget);
    expect(find.text('tekrar yarın'), findsOneWidget);
    expect(find.text('bitter'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('words-view-1')));
    await tester.pump();
    expect(find.text('bitter'), findsOneWidget);
    expect(find.text('frost'), findsNothing);
    expect(find.byKey(const ValueKey('words-today-review')), findsNothing);

    // By book: both lists, under the book they came from.
    await tester.ensureVisible(find.byKey(const ValueKey('words-view-2')));
    await tester.tap(find.byKey(const ValueKey('words-view-2')));
    await tester.pump();
    expect(find.text('Winter Tales'), findsOneWidget);
    expect(find.text('Kitap dışında eklenenler'), findsOneWidget);
    for (final w in ['frost', 'gale', 'bitter']) {
      expect(find.text(w), findsOneWidget, reason: w);
    }
  });
}

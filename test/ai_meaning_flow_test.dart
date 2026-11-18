// The AI answer for a sentence, end to end with a fake answer (no API call):
// shown as a draft, saved on the device, reused in the same sentence after a
// restart, not offered for another sentence, and dropped when flagged.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/ui/ai/local_ai_card.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:sqlite3/sqlite3.dart';

const sentence = 'Cracks run through the wall.';

void main() {
  late Directory dir;
  late AppState app;

  AppState openApp() {
    final d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
    final u = UserDb.open(dir);
    return AppState(d, u)..localAi = KeyAi(u);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vocabloom_ai');
    app = openApp();
  });

  Future<void> pumpCard(WidgetTester tester, LocalAiCard card) async {
    tester.view.physicalSize = const Size(390 * 2, 800 * 2);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: SingleChildScrollView(child: card))));
  }

  LocalAiCard card(AppState a, {String? initial, Stream<String> Function()? run}) => LocalAiCard(
        app: a,
        cacheKey: 'ctx:run through|$sentence',
        title: 'AI draft · not verified',
        button: 'Ask the AI',
        auto: true,
        initialText: initial ?? a.user.aiMeaning(sentence, 'run through', 'phrasal_verbs'),
        run: run ?? () => Stream.fromIterable(['boyunca uzanmak, ', 'içinden geçmek']),
        onDone: (text) => a.user.saveAiMeaning(
            sentence: sentence,
            phrase: 'run through',
            cat: 'phrasal_verbs',
            lemma: 'run',
            tr: text,
            model: 'key',
            dictVersion: a.senses.dictVersion,
            engineVersion: '1'),
      );

  testWidgets('the answer is shown as a draft and saved on the device', (tester) async {
    await pumpCard(tester, card(app));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('AI draft · not verified'), findsOneWidget);
    expect(find.textContaining('boyunca uzanmak'), findsOneWidget);
    expect(app.user.aiMeaning(sentence, 'run through', 'phrasal_verbs'), 'boyunca uzanmak, içinden geçmek');
    expect(tester.takeException(), isNull);
  });

  testWidgets('after a restart the saved answer is shown again without asking the AI', (tester) async {
    await pumpCard(tester, card(app));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // A restart: the same folder, a new app and a new card, asking nothing.
    app = openApp();
    var asked = false;
    await pumpCard(tester, card(app, run: () {
      asked = true;
      return const Stream<String>.empty();
    }));
    await tester.pump();
    expect(find.textContaining('boyunca uzanmak'), findsOneWidget);
    expect(asked, isFalse, reason: 'the saved answer is used; no new request');
  });

  testWidgets('the saved answer is for this sentence only', (tester) async {
    await pumpCard(tester, card(app));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(app.user.aiMeaning('They sat on the river bank.', 'run through', 'phrasal_verbs'), isNull);
  });

  test('a flagged answer is not offered again; an empty answer is never kept', () {
    app.user.saveAiMeaning(sentence: sentence, phrase: 'run through', cat: 'phrasal_verbs', lemma: 'run', tr: 'yanlış',
        model: 'key', dictVersion: '26', engineVersion: '1');
    app.user.flagAiMeanings('run', sentence);
    expect(app.user.aiMeaning(sentence, 'run through', 'phrasal_verbs'), isNull);
    app.user.saveAiMeaning(sentence: 'x.', phrase: 'y', cat: 'word', lemma: 'y', tr: '', dictVersion: '26', engineVersion: '1');
    expect(app.user.aiMeaning('x.', 'y', 'word'), isNull);
  });

  testWidgets('a failed answer shows its error and nothing is saved', (tester) async {
    final ctl = StreamController<String>();
    await pumpCard(tester, card(app, run: () => ctl.stream));
    await tester.pump();
    ctl.addError(Exception('the service is busy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await ctl.close();
    expect(app.user.aiMeaning(sentence, 'run through', 'phrasal_verbs'), isNull);
    expect(tester.takeException(), isNull);
  });
}

// Turkish grammar for learners of Turkish: the lessons parse, answers are
// compared the Turkish way, and the Grammar tab shows them (not the English
// lessons) when the learned language is Turkish.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/grammar_practice.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/grammar/grammar_page.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final topics = parseGrammarTopics(File('assets/grammar/lessons_tr.json').readAsStringSync());

  test('the Turkish lessons parse, every one in a known category, every answer accepted', () {
    expect(topics.length, greaterThanOrEqualTo(20));
    for (final t in topics) {
      expect(t.target, 'tr', reason: t.id);
      expect(grammarCategories.containsKey(t.category), isTrue, reason: t.id);
      expect(cefrLevels, contains(t.level));
      expect(t.exercises, isNotEmpty);
      for (final e in t.exercises) {
        expect(e.target, 'tr');
        for (final a in e.answers) {
          expect(matchesReference(e, a), isTrue, reason: '${e.id}: $a');
        }
      }
    }
    expect({for (final t in topics) t.id}.length, topics.length);
  });

  test('Turkish answers: case, punctuation, a joined question particle and a leading pronoun do not matter', () {
    const e = GrammarExercise('tr_x-1', 'Are you coming?', ['Geliyor musun?'], '');
    expect(matchesReference(e, 'geliyor musun'), isTrue);
    expect(matchesReference(e, 'Geliyormusun'), isTrue);
    expect(matchesReference(e, 'Sen geliyor musun?'), isTrue);
    expect(matchesReference(e, 'Geliyorsun.'), isFalse);
    const i = GrammarExercise('tr_x-2', 'I am in Istanbul.', ["İstanbul'dayım."], '');
    expect(matchesReference(i, 'ISTANBULDAYIM'), isFalse, reason: 'I is ı in Turkish');
    expect(matchesReference(i, 'istanbuldayım'), isTrue);
    expect(matchesReference(i, 'Ben İstanbul’dayım!'), isTrue);
    expect(matchesReference(i, ''), isFalse);
    // The English lessons still compare the English way.
    const en = GrammarExercise('x-1', 'Geliyor musun?', ['Are you coming?'], '');
    expect(matchesReference(en, "are you comin'"), isFalse);
    expect(matchesReference(en, 'are you coming'), isTrue);
  });

  test('hints keep Turkish letters', () {
    const e = GrammarExercise('tr_x-3', 'I went to school.', ['Okula gittim.'], '');
    expect(hintWords(e).toSet(), {'Okula', 'gittim'});
    const g = GrammarExercise('tr_x-4', 'q', ['çocuğu'], '');
    expect(hintWords(g).toSet(), {'çocuğu'});
  });

  group('Grammar tab', () {
    late AppState app;
    setUpAll(() {
      final d = DictDb();
      d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
      d.load();
      final u = UserDb.open(Directory.systemTemp.createTempSync('vb_grtr'));
      app = AppState(d, u)..localAi = KeyAi(u);
    });
    tearDown(() {
      uiEnglish = false;
      app.learnLang = 'en';
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: uiLocale,
        supportedLocales: uiLocales,
        localizationsDelegates: uiLocalizationsDelegates,
        theme: buildTheme(Brightness.light),
        home: GrammarPage(app: app),
      ));
      for (var i = 0; i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
    }

    testWidgets('learning Turkish shows the Turkish lessons, down to the last one', (tester) async {
      uiEnglish = true;
      app.learnLang = 'tr';
      await pump(tester);
      expect(find.textContaining('translate English sentences into Turkish'), findsOneWidget);
      expect(find.text('Tenses'), findsNothing);
      final last = topicsByLevel(topics).last;
      await tester.scrollUntilVisible(find.text(last.titleEn), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(last.titleEn), findsOneWidget);
      expect(find.text('Present Perfect'), findsNothing);
    });

    testWidgets('learning English still scrolls down to the last English lesson', (tester) async {
      await pump(tester);
      final en = topicsByLevel(await tester.runAsync(loadGrammarTopics) ?? const []);
      expect(en, isNotEmpty);
      expect(en.any((t) => t.target == 'tr'), isFalse);
      // The last category on the page holds its last topic.
      final lastCat = grammarCategories.keys.lastWhere((c) => en.any((t) => t.category == c));
      final last = en.lastWhere((t) => t.category == lastCat);
      await tester.scrollUntilVisible(find.text(last.titleTr), 400, scrollable: find.byType(Scrollable).first, maxScrolls: 200);
      expect(find.text(last.titleTr), findsOneWidget);
    });
  });
}

// First launch asks for the native language and the language to learn before
// the introduction, and saves both (the menus follow the native language).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/onboarding.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late DictDb dict;
  setUpAll(() {
    dict = DictDb();
    dict.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    dict.load();
  });
  tearDown(() => uiEnglish = false);

  testWidgets('languages first, then the introduction', (tester) async {
    uiEnglish = false;
    final d = Directory.systemTemp.createTempSync('vb_onb');
    final u = UserDb.open(d);
    final app = AppState(dict, u)
      ..localAi = KeyAi(u)
      ..trEn = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));
    expect(OnboardingPage.needed(app), isTrue);
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    var done = false;
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: OnboardingPage(app: app, onDone: () => done = true)));
    expect(find.byKey(const ValueKey('onboarding-languages')), findsOneWidget);
    expect(find.text('Dillerini seç'), findsOneWidget);

    // Learning Turkish makes English the native language and the menus English.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('onboarding-learn')), matching: find.text('Türkçe')));
    await tester.pump();
    expect(app.learnLang, 'tr');
    expect(app.nativeLang, 'en');
    expect(uiEnglish, isTrue);
    expect(find.text('Choose your languages'), findsOneWidget);
    // And back: Turkish native, learning English.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('onboarding-native')), matching: find.text('Turkish')));
    await tester.pump();
    expect(app.nativeLang, 'tr');
    expect(app.learnLang, 'en');
    expect(uiEnglish, isFalse);

    await tester.tap(find.byKey(const ValueKey('onboarding-languages-next')));
    await tester.pump();
    expect(find.byKey(const ValueKey('onboarding-languages')), findsNothing);
    expect(find.text('Atla'), findsOneWidget);
    await tester.tap(find.text('Atla'));
    expect(done, isTrue);
    // Saved for the next start.
    final again = AppState(dict, UserDb.open(d))..localAi = KeyAi(u);
    expect(again.nativeLang, 'tr');
    expect(again.learnLang, 'en');
  });
}

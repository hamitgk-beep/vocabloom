// The app (menu) language is its own setting, apart from the native language,
// and the theme is light or dark only: an old "system" choice becomes the one
// the device shows. Settings shows the new Language group with drop-downs.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/ui/settings_page.dart';
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

  AppState open(Directory d) {
    final u = UserDb.open(d);
    return AppState(dict, u)..localAi = KeyAi(u);
  }

  test('app language does not change the native language, and back', () {
    final d = Directory.systemTemp.createTempSync('vb_applang');
    var app = open(d);
    app.setLanguages(native: 'tr', learn: 'en');
    app.setAppLanguage('en');
    expect(uiEnglish, isTrue);
    expect(app.nativeLang, 'tr');
    expect(app.learnLang, 'en');
    // Changing the native language leaves the menus alone.
    app.setLanguages(native: 'en', learn: 'tr');
    expect(uiEnglish, isTrue);
    app.setAppLanguage('tr');
    app.setLanguages(native: 'en');
    expect(uiEnglish, isFalse);
    expect(app.nativeLang, 'en');
    // Both are saved.
    uiEnglish = true;
    app = open(d);
    expect(uiEnglish, isFalse);
    expect(app.nativeLang, 'en');
    expect(app.learnLang, 'tr');
  });

  test('settings saved before the app language setting keep their language', () {
    final d = Directory.systemTemp.createTempSync('vb_applang_old');
    UserDb.open(d).setJson('prefs', {'ui': 'en', 'learn': 'tr', 'theme': 'light'});
    final app = open(d);
    expect(uiEnglish, isTrue);
    expect(app.nativeLang, 'en');
    expect(app.learnLang, 'tr');
  });

  test('the old "system" theme becomes what the device shows', () {
    expect(themeFromPrefs('system', Brightness.dark), ThemeMode.dark);
    expect(themeFromPrefs('system', Brightness.light), ThemeMode.light);
    expect(themeFromPrefs('dark', Brightness.light), ThemeMode.dark);
    expect(themeFromPrefs('light', Brightness.dark), ThemeMode.light);
    expect(themeFromPrefs(null, Brightness.dark), ThemeMode.light);
  });

  testWidgets('settings: language group and a light / dark theme menu', (tester) async {
    final app = open(Directory.systemTemp.createTempSync('vb_settings'));
    app.setLanguages(native: 'tr', learn: 'en');
    tester.view.physicalSize = const Size(393 * 2, 1400 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: SettingsPage(app: app)));
    await tester.pump();
    for (final t in ['GÖRÜNÜM', 'DİL', 'Uygulama dili', 'Ana dil', 'Anlam dili']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    await tester.tap(find.byType(DropdownButton<ThemeMode>));
    await tester.pumpAndSettle();
    expect(find.text('Sistem'), findsNothing);
    expect(find.text('Koyu'), findsWidgets);
    await tester.tap(find.text('Koyu').last);
    await tester.pumpAndSettle();
    expect(app.themeMode, ThemeMode.dark);

    // Switching the app language to English keeps Turkish meanings.
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(uiEnglish, isTrue);
    expect(app.nativeLang, 'tr');
    expect(find.text('App language'), findsOneWidget);
  });
}

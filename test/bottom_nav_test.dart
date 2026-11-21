// Phone home: the gold wordmark pinned on top (no search field: the
// Dictionary tab is one tap away), the Today card, and four tabs (Library,
// Dictionary, My words with the words due for review, More). More holds
// light / dark and the other pages. Tab pages end at the top of the bar.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/l10n.dart';
import 'package:kelime_okur/main.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late DictDb dict;
  setUpAll(() {
    dict = DictDb();
    dict.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    dict.load();
  });

  testWidgets('phone home and bottom bar', (tester) async {
    uiEnglish = false;
    final u = UserDb.open(Directory.systemTemp.createTempSync('vb_nav'));
    final app = AppState(dict, u)..localAi = KeyAi(u);
    for (final w in ['bitter', 'frost']) {
      u.setWord(w, WordStatus.learning);
    }
    tester.view.physicalSize = const Size(393 * 2, 852 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: HomePage(app: app)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.byKey(const ValueKey('today-card')), findsOneWidget);
    // Two new "To learn" words are due right away: a badge and a review button.
    expect(find.byKey(const ValueKey('today-review')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('nav-due')), matching: find.text('2')), findsOneWidget);
    for (final t in ['Kitaplık', 'Sözlük', 'Kelimelerim', 'Diğer']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.byKey(const ValueKey('home-search')), findsNothing);

    // The header stays put while the page scrolls.
    final headerTop = tester.getTopLeft(find.byKey(const ValueKey('home-header'))).dy;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(find.byKey(const ValueKey('home-header'))).dy, headerTop);
    expect(find.byType(Wordmark), findsOneWidget);

    // The pages end where the bottom bar starts, so nothing hides behind it.
    final bodyBottom = tester.getBottomLeft(find.byKey(const ValueKey('tab-body'))).dy -
        tester.widget<Padding>(find.byKey(const ValueKey('tab-body'))).padding.resolve(TextDirection.ltr).bottom;
    final barTop = tester.getTopLeft(find.byKey(const ValueKey('nav_0'))).dy;
    expect(bodyBottom, lessThanOrEqualTo(barTop));

    // More: the theme segment and the other pages.
    await tester.tap(find.byKey(const ValueKey('nav-menu')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final t in ['Gramer', 'Ücretsiz kitaplar', 'İstatistikler', 'Ayarlar']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Only light and dark: "system" looked the same as light.
    expect(find.byKey(const ValueKey('menu-system')), findsNothing);
    expect(find.text('Sistem'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-night')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(app.themeMode, ThemeMode.dark);
    await tester.tap(find.byKey(const ValueKey('nav_5')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('journey-total')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-menu-panel')), findsNothing);

    // Let the delayed update check run (no build number in tests: it does nothing).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('loading screen shows the wordmark, not a spinner', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: const LoadingScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Wordmark), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Sözlük hazırlanıyor…'), findsOneWidget);
  });
}

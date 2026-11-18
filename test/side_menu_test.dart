// Wide-screen side menu: names on one line next to the icons, the free library and the
// stats in their own group, Settings at the bottom; narrow windows show icons only.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ai/key_ai.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/main.dart';
import 'package:kelime_okur/ui/theme.dart';
import 'package:sqlite3/sqlite3.dart';

import 'context_sense_ui_test.dart' show loadFonts;

void main() {
  late DictDb dict;
  setUpAll(() {
    dict = DictDb();
    dict.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    dict.load();
  });

  for (final (width, full) in [(820.0, false), (1280.0, true)]) {
    testWidgets('side menu at width $width', (tester) async {
      final u = UserDb.open(Directory.systemTemp.createTempSync('vb_side'));
      final app = AppState(dict, u)..localAi = KeyAi(u);
      tester.view.physicalSize = Size(width * 2, 900 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final shotDir = Platform.environment['SIDE_MENU_SHOTS'];
      if (shotDir != null) await tester.runAsync(loadFonts);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark), home: HomePage(app: app)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 7; i++) {
        expect(find.byKey(ValueKey('side-menu-$i')), findsOneWidget);
      }
      expect(find.text('İstatistiklerim'), full ? findsOneWidget : findsNothing);
      expect(find.text('Ücretsiz kütüphane'), full ? findsOneWidget : findsNothing);
      if (shotDir != null) {
        await tester.runAsync(() async {
          final img = await captureImage(find.byType(MaterialApp).evaluate().first);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$shotDir/side_$width.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      await tester.tap(find.byKey(const ValueKey('side-menu-5')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('journey-total')), findsOneWidget);
      // Let the delayed update check run (no build number in tests: it does nothing).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox());
    });
  }
}

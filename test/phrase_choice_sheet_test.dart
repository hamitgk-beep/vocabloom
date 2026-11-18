// The "Bunu mu demek istedin?" sheet: real widget test at phone and wider
// widths, with no overflow and each choice returned correctly.
import 'dart:io';
import 'dart:ui' as ui;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ui/phrase_choice.dart';
import 'package:kelime_okur/ui/theme.dart';

final shots = Platform.environment['CONTEXT_SHOTS'];

/// The app's own fonts, so a screenshot shows real text (not test boxes).
Future<void> loadFonts() async {
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
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

Future<void> pumpAt(WidgetTester tester, double width, void Function(int?) onResult) async {
  tester.view.physicalSize = Size(width * 2, 1200 * 2);
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Scaffold(
      body: Builder(
        builder: (c) => Center(
          child: FilledButton(
            key: const ValueKey('open'),
            onPressed: () async => onResult(await showPhraseChoice(c, const ['make up', "make up one's mind", 'make up for it, a very long phrase that wraps onto a second line on a phone'], 'made')),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  for (final w in [360.0, 420.0, 820.0]) {
    testWidgets('the sheet fits at $w px and the single-word choice is returned', (tester) async {
      int? got = -99;
      if (shots != null) await tester.runAsync(loadFonts);
      await pumpAt(tester, w, (r) => got = r);
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.text('Bunu mu demek istedin?'), findsOneWidget);
      expect(find.byKey(const ValueKey('phrase-choice-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('phrase-choice-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('phrase-choice-word')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'no overflow at $w px');
      if (shots != null && w == 420) {
        await tester.runAsync(() async {
          final img = await captureImage(find.byType(MaterialApp).evaluate().first);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$shots/phrase_choice_420.png')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      await tester.tap(find.byKey(const ValueKey('phrase-choice-word')));
      await tester.pumpAndSettle();
      expect(got, -1);
    });
  }

  testWidgets('a phrase choice returns its index', (tester) async {
    int? got = -99;
    await pumpAt(tester, 390, (r) => got = r);
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phrase-choice-1')));
    await tester.pumpAndSettle();
    expect(got, 1);
  });
}

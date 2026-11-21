// Read aloud in the reader: the control card sits at the page's foot and the
// book stays on screen above it (the card used to take the whole page).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/read_aloud.dart';
import 'package:kelime_okur/ui/reader_page.dart';
import 'package:kelime_okur/ui/theme.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('the read-aloud card leaves the book visible (${b.name})', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final reader = ReadAloud(paras: () => const [], nextChapter: () async => false)..active = true;
      addTearDown(reader.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(b),
        home: Scaffold(
          body: ListView(children: const [Text('Once upon a time there was a little girl.', key: ValueKey('book'))]),
          bottomNavigationBar: ReadAloudBar(reader: reader),
        ),
      ));
      await tester.pump();

      final bar = tester.getRect(find.byType(ReadAloudBar));
      final card = tester.getRect(find.byKey(const ValueKey('speech-bar')));
      final book = tester.getRect(find.byKey(const ValueKey('book')));
      // The bar is only as tall as its card (plus the margin), at the bottom.
      expect(bar.height, lessThan(card.height + 40));
      expect(bar.bottom, 844);
      // The book's text is above the card, not hidden behind it.
      expect(book.bottom, lessThan(card.top));
      expect(tester.getRect(find.byType(ListView)).height, greaterThan(600));
    });
  }
}

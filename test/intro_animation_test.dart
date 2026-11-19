import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ui/intro_animation.dart';

void main() {
  tearDown(() => IntroAnimation.film = 'assets/brand/intro.webp');

  Future<void> settleDecoding(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  testWidgets('the film shows and a tap brings the app out of the book', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(home: IntroAnimation(onDone: () => done = true)));
    await settleDecoding(tester);
    final painter = tester.widget<CustomPaint>(find.descendant(of: find.byKey(const ValueKey('intro-animation')), matching: find.byType(CustomPaint))).painter as IntroFilmPainter;
    expect(painter.frame, isNotNull, reason: 'the first frame of the film was not decoded');
    expect(done, isFalse);
    await tester.tap(find.byKey(const ValueKey('intro-animation')));
    await tester.pump();
    await tester.pump(IntroAnimation.reveal + const Duration(milliseconds: 50));
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets('the film plays to its end and hands over', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(home: IntroAnimation(onDone: () => done = true)));
    for (var i = 0; i < 1500 && !done; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(done, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('without the film the app opens at once', (tester) async {
    IntroAnimation.film = 'assets/brand/missing.webp';
    var done = false;
    await tester.pumpWidget(MaterialApp(home: IntroAnimation(onDone: () => done = true)));
    await settleDecoding(tester);
    expect(done, isTrue);
  });
}

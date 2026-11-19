import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/ui/intro_animation.dart';

void main() {
  testWidgets('the intro plays through and hands over', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(home: IntroAnimation(onDone: () => done = true)));
    for (var t = 0; t < 60; t++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(done, isTrue);
  });

  testWidgets('a tap skips the intro', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(home: IntroAnimation(onDone: () => done = true)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('intro-animation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(done, isTrue);
  });
}

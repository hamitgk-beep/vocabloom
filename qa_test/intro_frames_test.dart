// Frames of the opening animation for a preview video:
//   flutter test qa_test/intro_frames_test.dart   (writes qa-report/intro/<variant>/f0000.png ...)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kelime_okur/ui/intro_animation.dart';

import 'picture_book_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  final fps = int.tryParse(Platform.environment['INTRO_FPS'] ?? '') ?? 30;
  for (final (name, size, dark) in [('phone_dark', const Size(390, 844), true), ('phone_light', const Size(390, 844), false), ('desktop_dark', const Size(1280, 720), true)]) {
    testWidgets('intro $name', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final t = ValueNotifier(0.0);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: ValueListenableBuilder<double>(valueListenable: t, builder: (_, v, _) => CustomPaint(size: size, painter: IntroPainter(v, dark: dark))),
      ));
      final dir = Directory('qa-report/intro/$name')..createSync(recursive: true);
      final n = (IntroAnimation.length.inMilliseconds / 1000 * fps).round() + fps ~/ 2;
      for (var i = 0; i <= n; i++) {
        t.value = i / fps;
        await tester.pump();
        await tester.runAsync(() async {
          final ro = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await ro.toImage(pixelRatio: 2);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/f${i.toString().padLeft(4, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}

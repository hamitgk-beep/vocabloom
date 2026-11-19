// Frames of the way out of the opening film, for a preview video:
//   INTRO_BG=<screenshot.png> [INTRO_FULL=1] flutter test qa_test/intro_reveal_test.dart
// writes qa-report/intro/<variant>/fNNNN.png: the film's last frame (with
// INTRO_FULL, every frame of the film first), then the app (the
// screenshot) coming out of the book.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kelime_okur/ui/intro_animation.dart';

void main() {
  final bg = Platform.environment['INTRO_BG'];
  final full = Platform.environment['INTRO_FULL'] == '1';
  for (final (name, size) in [('phone', const Size(390, 844)), ('desktop', const Size(1280, 720))]) {
    testWidgets('intro reveal $name', (tester) async {
      await tester.binding.setSurfaceSize(size);
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      // (frame, how many 30 fps video frames it lasts)
      final film = (await tester.runAsync(() async {
        final data = await rootBundle.load(IntroAnimation.film);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frames = <(ui.Image, int)>[];
        for (var i = 0; i < codec.frameCount; i++) {
          final f = await codec.getNextFrame();
          if (full || i == codec.frameCount - 1) frames.add((f.image, math.max(1, (f.duration.inMilliseconds * 30 / 1000).round())));
        }
        return frames;
      }))!;
      final last = film.last.$1;
      final frame = ValueNotifier(last);
      final t = ValueNotifier(0.0);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bg != null) Image.file(File(bg), fit: BoxFit.cover, alignment: Alignment.topLeft) else const ColoredBox(color: Color(0xFFF6EEDC)),
                ListenableBuilder(
                  listenable: Listenable.merge([t, frame]),
                  builder: (_, _) => CustomPaint(painter: IntroFilmPainter(frame.value, reveal: t.value)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      final dir = Directory('qa-report/intro/$name')..createSync(recursive: true);
      var out = 0;
      Future<void> shot([int times = 1]) async {
        await tester.pump();
        final png = await tester.runAsync(() async {
          final ro = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final img = await ro.toImage(pixelRatio: 2);
          return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        });
        for (var k = 0; k < times; k++) {
          File('${dir.path}/f${(out++).toString().padLeft(4, '0')}.png').writeAsBytesSync(png!);
        }
      }

      for (final (img, times) in film.take(film.length - 1)) {
        frame.value = img;
        await shot(times);
      }
      frame.value = last;
      const fps = 30;
      final n = (IntroAnimation.reveal.inMilliseconds * fps / 1000).round();
      for (var i = 0; i <= n + 10; i++) {
        t.value = (i / n).clamp(0, 1);
        await shot();
      }
    }, timeout: const Timeout(Duration(minutes: 15)));
  }
}

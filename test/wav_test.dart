import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/wav.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wav_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  // [quietBefore] s of silence, [loud] s of a tone, [quietAfter] s of silence.
  String clip(String name, double quietBefore, double loud, double quietAfter, {int rate = 44100}) {
    final a = (quietBefore * rate).round(), b = (loud * rate).round(), c = (quietAfter * rate).round();
    final x = Int16List(a + b + c);
    for (var i = 0; i < b; i++) {
      x[a + i] = (8000 * sin(2 * pi * 220 * i / rate)).round();
    }
    final path = '${dir.path}/$name.wav';
    Pcm(x, rate).write(path);
    return path;
  }

  test('a clip survives write and read', () {
    final p = clip('a', 0.1, 0.5, 0.1);
    final w = Pcm.read(p);
    expect(w.rate, 44100);
    expect(w.seconds, closeTo(0.7, 0.001));
  });

  test('trimming drops edge silence but keeps a small margin', () {
    final w = Pcm.read(clip('a', 0.4, 0.5, 0.6)).trimmed();
    expect(w.seconds, closeTo(0.56, 0.03));
  });

  test('pieces are joined with the chosen pauses, and their starts are known', () {
    final a = clip('a', 0.3, 1.0, 0.5), b = clip('b', 0.2, 0.8, 0.4);
    final out = '${dir.path}/joined.wav';
    final starts = joinWavs([a, b], [0.35, 0.1], out, lead: 0.12);
    final w = Pcm.read(out);
    // lead + (1.0 + margins) + pause + (0.8 + margins) + pause
    expect(w.seconds, closeTo(0.12 + 1.06 + 0.35 + 0.86 + 0.1, 0.03));
    expect(starts[0], closeTo(0.12, 0.001));
    expect(starts[1], closeTo(0.12 + 1.06 + 0.35, 0.03));
  });

  test('pauses follow punctuation like a reader breathing', () {
    expect(pauseAfter('He left.'), 0.35);
    expect(pauseAfter('"Where were you?"'), 0.35);
    expect(pauseAfter('Although it rained,'), 0.15);
    expect(pauseAfter('The end.', paragraphEnd: true), 0.6);
  });
}

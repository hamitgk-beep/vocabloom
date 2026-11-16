import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/ema.dart';

void main() {
  test('Turkish numbers and letters', () {
    expect(turkishNumber(1234), 'bin iki yüz otuz dört');
    expect(turkishNumber(2000105), 'iki milyon yüz beş');
    expect(turkishNumber(11), 'on bir');
    const vocab = ' abcçdefgğhıijklmnoöprsştuüvyz.,';
    expect(turkishLetters('İstanbul\'da 3 KİTAP aldım.', (c) => vocab.contains(c)), 'istanbul da üç kitap aldım.');
    expect(turkishLetters('Hâlâ IŞIK', (c) => vocab.contains(c)), 'hala ışık');
  });

  final dir = Platform.environment['VOCABLOOM_EMA_DIR'];
  test('EMA voice makes speech', () {
    final v = EmaVoice.load(dir!, threads: 4, libDir: Platform.environment['SHERPA_ONNX_LIB_DIR']);
    final sw = Stopwatch()..start();
    final a = v.generate('Öğrenmek için her gün biraz okumalısın.');
    final secs = a.length / v.sampleRate;
    // ignore: avoid_print
    print('${sw.elapsedMilliseconds} ms for ${secs.toStringAsFixed(2)} s');
    expect(secs, inInclusiveRange(1.5, 6.0));
    var peak = 0.0;
    for (final x in a) {
      if (x.abs() > peak) peak = x.abs();
    }
    expect(peak, greaterThan(0.05));
    final out = Platform.environment['VOCABLOOM_EMA_OUT'];
    if (out != null) {
      final sents = (Platform.environment['VOCABLOOM_EMA_TEXTS'] ?? 'Öğrenmek için her gün biraz okumalısın.|Bisiklet.').split('|');
      for (var i = 0; i < sents.length; i++) {
        final x = v.generate(sents[i], speed: double.parse(Platform.environment['VOCABLOOM_EMA_SPEED'] ?? '1'));
        final b = BytesBuilder()..add(_wavHeader(x.length, v.sampleRate));
        final d = ByteData(x.length * 2);
        for (var j = 0; j < x.length; j++) {
          d.setInt16(j * 2, (x[j].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
        }
        b.add(d.buffer.asUint8List());
        File('$out/ema_$i.wav').writeAsBytesSync(b.toBytes());
      }
    }
    v.close();
  }, skip: dir == null ? 'set VOCABLOOM_EMA_DIR' : false);
}

List<int> _wavHeader(int n, int sr) {
  final h = ByteData(44);
  void str(int o, String s) => s.codeUnits.asMap().forEach((i, c) => h.setUint8(o + i, c));
  str(0, 'RIFF'); h.setUint32(4, 36 + n * 2, Endian.little); str(8, 'WAVEfmt ');
  h.setUint32(16, 16, Endian.little); h.setUint16(20, 1, Endian.little); h.setUint16(22, 1, Endian.little);
  h.setUint32(24, sr, Endian.little); h.setUint32(28, sr * 2, Endian.little); h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little); str(36, 'data'); h.setUint32(40, n * 2, Endian.little);
  return h.buffer.asUint8List();
}

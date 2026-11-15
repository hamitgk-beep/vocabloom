import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Mono 16-bit PCM audio, as sherpa-onnx writes it.
class Pcm {
  final Int16List samples;
  final int rate;
  Pcm(this.samples, this.rate);

  double get seconds => samples.length / rate;

  static Pcm read(String path) {
    final b = File(path).readAsBytesSync();
    final bd = ByteData.sublistView(b);
    var rate = 16000, pos = 12;
    while (pos + 8 <= b.length) {
      final id = String.fromCharCodes(b, pos, pos + 4);
      var size = bd.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ') rate = bd.getUint32(body + 4, Endian.little);
      if (id == 'data') {
        size = min(size, b.length - body);
        final out = Int16List(size ~/ 2);
        for (var i = 0; i < out.length; i++) {
          out[i] = bd.getInt16(body + 2 * i, Endian.little);
        }
        return Pcm(out, rate);
      }
      pos = body + size + (size.isOdd ? 1 : 0);
    }
    return Pcm(Int16List(0), rate);
  }

  void write(String path) {
    final n = samples.length * 2;
    final h = ByteData(44);
    void tag(int at, String s) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    h.setUint32(4, 36 + n, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little); // PCM
    h.setUint16(22, 1, Endian.little); // mono
    h.setUint32(24, rate, Endian.little);
    h.setUint32(28, rate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    h.setUint32(40, n, Endian.little);
    final out = BytesBuilder(copy: false)
      ..add(h.buffer.asUint8List())
      ..add(samples.buffer.asUint8List(samples.offsetInBytes, n));
    File(path).writeAsBytesSync(out.takeBytes());
  }

  /// Without the quiet before the first and after the last sound, keeping
  /// [keep] seconds of margin so soft consonants are not cut.
  Pcm trimmed({double keep = 0.03}) {
    if (samples.isEmpty) return this;
    var peak = 0;
    for (final v in samples) {
      peak = max(peak, v.abs());
    }
    final th = max(60, peak ~/ 50); // 2% of the peak
    final win = max(1, rate ~/ 100); // 10 ms
    bool loud(int at) {
      final end = min(samples.length, at + win);
      for (var i = at; i < end; i++) {
        if (samples[i].abs() > th) return true;
      }
      return false;
    }

    var a = 0;
    while (a < samples.length && !loud(a)) {
      a += win;
    }
    var z = samples.length;
    while (z > a && !loud(max(0, z - win))) {
      z -= win;
    }
    final m = (keep * rate).round();
    a = max(0, a - m);
    z = min(samples.length, z + m);
    if (a >= z) return this;
    return Pcm(Int16List.sublistView(samples, a, z), rate);
  }
}

/// Joins spoken pieces into one clip with the given pause after each one, so
/// they play as one smooth stream. Returns where each piece starts (seconds).
List<double> joinWavs(List<String> inputs, List<double> pausesAfter, String out, {double lead = 0.12}) {
  final parts = [for (final p in inputs) Pcm.read(p).trimmed()];
  final rate = parts.isEmpty ? 16000 : parts.first.rate;
  final starts = <double>[];
  var total = (lead * rate).round();
  for (var i = 0; i < parts.length; i++) {
    starts.add(total / rate);
    total += parts[i].samples.length + (pausesAfter[i] * rate).round();
  }
  final all = Int16List(total);
  var at = (lead * rate).round();
  for (var i = 0; i < parts.length; i++) {
    all.setRange(at, at + parts[i].samples.length, parts[i].samples);
    at += parts[i].samples.length + (pausesAfter[i] * rate).round();
  }
  Pcm(all, rate).write(out);
  return starts;
}

/// The pause a listener expects after a piece of text: a breath after a
/// sentence, a short one after a comma, a longer one at a paragraph's end.
double pauseAfter(String text, {bool paragraphEnd = false}) {
  if (paragraphEnd) return 0.6;
  final t = text.trimRight();
  if (RegExp(r'[.!?…]["”’)]*$').hasMatch(t)) return 0.35;
  if (RegExp(r'[,;:—]["”’)]*$').hasMatch(t)) return 0.15;
  return 0.25;
}

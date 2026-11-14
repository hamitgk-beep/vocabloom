import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/tts/read_aloud.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:kelime_okur/tts/voices.dart';

/// Speed and cleanliness gate for the offline voices. CI runs it on an ARM
/// CPU limited to one thread (like a weak phone) with the published voice
/// packs, and a release is only made when it passes.
///
/// Set VOCABLOOM_VOICE_BASE to the folder URL holding the pack zips.
/// VOCABLOOM_SLOW_FACTOR (default 3) scales the measured times to a low-end
/// phone, whose cores are about that much slower than the CI machine's.
void main() {
  final base = Platform.environment['VOCABLOOM_VOICE_BASE'];
  final slow = double.tryParse(Platform.environment['VOCABLOOM_SLOW_FACTOR'] ?? '') ?? 3;
  final report = StringBuffer();
  void log(String s) {
    report.writeln(s);
    // ignore: avoid_print
    print(s);
  }

  test('voices are fast and clean enough for a low-end phone', () async {
    final dir = Directory.systemTemp.createTempSync('voiceperf');
    final s = Speech.instance..init(dir, UserDb.open(dir));
    for (final pk in voicePacks) {
      await s.download(pk, url: '$base/${pk.id}.zip');
      expect(s.stateOf(pk), PackState.ready, reason: s.errorOf(pk));
    }
    final en = voiceById['en_f1']!, enM = voiceById['en_m2']!, tr = voiceById['tr_fahrettin']!;

    final sw = Stopwatch()..start();
    await s.warmUp();
    log('warm-up (load + calibrate): ${sw.elapsedMilliseconds} ms, quality steps ${s.qualitySteps}');

    Future<(double, String)> timed(String text, Voice v) async {
      final t = Stopwatch()..start();
      final p = await s.synth(text, v: v, urgent: true);
      return (t.elapsedMicroseconds / 1e6, p);
    }

    // 1) A tapped word: time until its audio is ready to play.
    const words = ['and', 'grow', 'though', 'the', 'run', 'would', 'bright', 'cat', 'thought', 'yes', 'learn', 'world', 'through', 'which', 'strength', 'judge', 'church', 'rough', 'school', 'night'];
    final times = <double>[];
    var stutters = 0;
    for (final v in [en, enM]) {
      for (final w in words) {
        final (t, p) = await timed(w, v);
        times.add(t);
        final n = burstsOfWav(File(p));
        if (n != 1) {
          stutters++;
          log('  stray sound: ${v.id} "$w" ($n bursts)');
        }
        File(p).deleteSync();
      }
    }
    times.sort();
    final p50 = times[times.length ~/ 2], p90 = times[(times.length * 0.9).floor()];
    log('word: median ${(p50 * 1000).round()} ms, p90 ${(p90 * 1000).round()} ms here; low-end phone ~${(p90 * slow * 1000).round()} ms; stray sounds $stutters/${times.length}');

    // 2) Reading aloud: first clause of a long sentence, and speed overall.
    const long = 'Although it was raining heavily all morning, she decided to walk to the old library on the hill, because she wanted to finish the book before her friends arrived for dinner.';
    final chunks = speechChunks(long, 0, long.length).map((r) => long.substring(r.$1, r.$2).trim()).toList();
    final (first, fp) = await timed(chunks.first, en);
    var gen = first, audio = wavSeconds(File(fp));
    File(fp).deleteSync();
    for (final c in chunks.skip(1)) {
      final (t, p) = await timed(c, en);
      gen += t;
      audio += wavSeconds(File(p));
      File(p).deleteSync();
    }
    final rtf = gen / audio;
    log('long sentence: ${chunks.length} parts, first part ready in ${(first * 1000).round()} ms (low-end ~${(first * slow * 1000).round()} ms), real-time factor $rtf (low-end ~${(rtf * slow).toStringAsFixed(2)})');

    // 3) Turkish meaning.
    final (trT, trP) = await timed('rağmen', tr);
    File(trP).deleteSync();
    log('turkish word: ${(trT * 1000).round()} ms');

    File('voice-perf-report.txt').writeAsStringSync(report.toString());

    // Gates, as a low-end phone would feel them.
    expect(p90 * slow, lessThan(1.2), reason: 'a tapped word must start in about a second');
    expect(first * slow, lessThan(2.0), reason: 'reading must start within ~2 s');
    expect(rtf * slow, lessThan(0.9), reason: 'reading must keep up with playback');
    expect(stutters, lessThanOrEqualTo(2), reason: 'single words must not stutter (at most 1 in 20)');
    expect(trT * slow, lessThan(1.0));
  }, skip: base == null ? 'set VOCABLOOM_VOICE_BASE' : false, timeout: const Timeout(Duration(minutes: 15)));
}

Float32List _samples(File f, {required void Function(int) rate}) {
  final b = f.readAsBytesSync();
  final bd = ByteData.sublistView(b);
  rate(bd.getUint32(24, Endian.little));
  // 16-bit PCM after a 44-byte header (sherpa-onnx writes this layout)
  final n = (b.length - 44) ~/ 2;
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(44 + 2 * i, Endian.little) / 32768.0;
  }
  return out;
}

double wavSeconds(File f) {
  var sr = 1;
  final x = _samples(f, rate: (r) => sr = r);
  return x.length / sr;
}

/// Separate loud stretches in a clip: a clean one-syllable word has one.
int burstsOfWav(File f) {
  var sr = 1;
  final x = _samples(f, rate: (r) => sr = r);
  final h = (sr * 0.03).round();
  final e = <double>[];
  for (var i = 0; i + h < x.length; i += h) {
    var s = 0.0;
    for (var j = i; j < i + h; j++) {
      s += x[j] * x[j];
    }
    e.add(sqrt(s / h));
  }
  final th = 0.15 * e.reduce(max);
  // Count stretches above 15% of the peak, separated by >= 120 ms of quiet,
  // that reach half the peak: a repeated start ("aand", "gggrow") or a stray
  // second sound. A soft release after a final consonant is not counted.
  final peak = e.reduce(max);
  var n = 0, gap = 99;
  var top = 0.0;
  for (final v in e) {
    if (v > th) {
      if (gap >= 4) {
        if (top >= 0.5 * peak) n++;
        top = 0;
      }
      top = max(top, v);
      gap = 0;
    } else {
      gap++;
    }
  }
  if (top >= 0.5 * peak) n++;
  return n;
}

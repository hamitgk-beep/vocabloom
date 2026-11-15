import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/tts/read_aloud.dart';
import 'package:kelime_okur/tts/speech.dart';
import 'package:kelime_okur/tts/voices.dart';
import 'package:kelime_okur/tts/wav.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Speed and quality gate for the offline voices. CI runs it on an ARM CPU
/// with the published voice packs, and a release is only made when it passes.
///
/// VOCABLOOM_VOICE_PROFILE picks the phone it stands for:
/// - `low` (1 thread, times x3): a weak phone, which uses the light voice;
/// - `mid` (4 threads, times x1.5): an ordinary phone, which uses the natural voice.
/// VOCABLOOM_VOICE_BASE is the folder URL holding the pack zips, and
/// VOCABLOOM_ASR_DIR a Whisper model that writes down what the voice said, so
/// a skipped, repeated or cut word fails the test.
void main() {
  final base = Platform.environment['VOCABLOOM_VOICE_BASE'];
  final profile = Platform.environment['VOCABLOOM_VOICE_PROFILE'] ?? 'low';
  final slow = double.tryParse(Platform.environment['VOCABLOOM_SLOW_FACTOR'] ?? '') ?? (profile == 'mid' ? 1.5 : 3);
  final report = StringBuffer();
  void log(String s) {
    report.writeln(s);
    // ignore: avoid_print
    print(s);
  }

  test('voices are fast and clean enough ($profile phone)', () async {
    final dir = Directory.systemTemp.createTempSync('voiceperf');
    final s = Speech.instance..init(dir, UserDb.open(dir));
    for (final pk in voicePacks) {
      await s.download(pk, url: '$base/${pk.id}.zip');
      expect(s.stateOf(pk), PackState.ready, reason: s.errorOf(pk));
    }
    final natural = profile == 'mid';
    s.quality = natural ? 'natural' : 'light';
    final list = natural ? voices : lightVoices;
    final en = list.firstWhere((v) => v.female), enM = natural ? voiceById['k_bm_george']! : list.firstWhere((v) => !v.female), tr = voiceById['tr_fahrettin']!;
    // The natural male is British, so both accents are checked.
    log('## ${natural ? 'Natural voice (Kokoro), ordinary phone' : 'Light voice (Piper), weak phone'}: times x$slow');

    final sw = Stopwatch()..start();
    await s.warmUp();
    log('warm-up (load all voices): ${sw.elapsedMilliseconds} ms');

    Future<(double, String)> timed(String text, Voice v) async {
      final t = Stopwatch()..start();
      final p = await s.synth(text, v: v, urgent: true);
      return (t.elapsedMicroseconds / 1e6, p);
    }

    final asrDir = Platform.environment['VOCABLOOM_ASR_DIR'];
    final asr = asrDir == null ? null : Asr(asrDir);

    // 1) A tapped word: time until its audio is ready, and whether it is
    // heard as that word (said after a fixed lead-in, as Whisper needs context).
    const words = ['pedicab', 'pedestrian', 'beautiful', 'library', 'potato', 'telephone', 'kitchen', 'pocket', 'basket', 'tomorrow', 'carriage', 'daughter', 'garden', 'candle', 'paper', 'and', 'grow', 'though', 'school', 'night'];
    final times = <double>[];
    var wordsOk = 0, wordsChecked = 0;
    // [en] last: it reads aloud next, as one keeps one voice while reading
    // (a US and a UK natural voice are one model loaded with another setting).
    for (final v in [enM, en]) {
      final lead = asr == null ? null : await s.synth('Here is the word:', v: v);
      for (final w in words) {
        final (t, p) = await timed(w, v);
        times.add(t);
        if (asr != null) {
          final heard = asr.transcribeJoined(lead!, p);
          final last = RegExp(r'[a-z]+').allMatches(heard.toLowerCase()).map((m) => m[0]).lastOrNull;
          wordsChecked++;
          if (last == w || (w == 'pedicab' && last != null && last.endsWith('cab'))) {
            wordsOk++;
          } else {
            log('  word ${v.name} "$w" heard as "${heard.trim()}"');
          }
        }
        File(p).deleteSync();
      }
      if (lead != null) File(lead).deleteSync();
    }
    times.sort();
    final p90 = times[(times.length * 0.9).floor()];
    log('tapped word: p90 ${(p90 * 1000).round()} ms here, phone ~${(p90 * slow * 1000).round()} ms${asr == null ? '' : '; heard right $wordsOk of $wordsChecked'}');

    // 2) Reading aloud: the first clause the listener waits for, and speed overall.
    const long = 'Although it was raining heavily all morning, she decided to walk to the old library on the hill, because she wanted to finish the book before her friends arrived for dinner.';
    final chunks = speechChunks(long, 0, long.length).map((r) => long.substring(r.$1, r.$2).trim()).toList();
    final (first, fp) = await timed(chunks.first, en);
    var gen = first, audio = Pcm.read(fp).seconds;
    File(fp).deleteSync();
    for (final c in chunks.skip(1)) {
      final (t, p) = await timed(c, en);
      gen += t;
      audio += Pcm.read(p).seconds;
      File(p).deleteSync();
    }
    final rtf = gen / audio;
    log('reading: first part ready in ${(first * 1000).round()} ms (phone ~${(first * slow * 1000).round()} ms); work per second of speech ${rtf.toStringAsFixed(2)} s (phone ~${(rtf * slow).toStringAsFixed(2)} s)');

    // 3) Turkish meaning.
    final (trT, trP) = await timed('rağmen', tr);
    File(trP).deleteSync();
    log('turkish word: ${(trT * 1000).round()} ms (phone ~${(trT * slow * 1000).round()} ms)');

    // 4) Nothing skipped or repeated: book sentences made exactly as the reader
    // makes them (pieces joined with pauses into one clip), written down by a
    // speech recognizer and compared word by word.
    var werErrors = 0, werWords = 0, badSentences = 0, checked = 0;
    if (asr != null) {
      for (final v in [en, enM]) {
        for (final text in _bookSentences) {
          final pieces = speechChunks(text, 0, text.length, maxWords: 22).map((r) => text.substring(r.$1, r.$2).trim()).toList();
          final paths = [for (final piece in pieces) await s.synth(piece, v: v)];
          final clip = '${dir.path}/clip.wav';
          joinWavs(paths, [for (final piece in pieces) pauseAfter(piece)], clip);
          for (final p in paths) {
            File(p).deleteSync();
          }
          final heard = asr.transcribe(clip);
          final (e, n) = wordErrors(text, heard);
          werErrors += e;
          werWords += n;
          checked++;
          if (e >= 2) {
            badSentences++;
            log('  ${v.name}: "$text" -> "$heard"');
          }
        }
      }
      asr.free();
      log('sentences: ${(100 * werErrors / werWords).toStringAsFixed(1)}% words wrong ($werErrors of $werWords), sentences with a skipped or extra word: $badSentences of $checked');
    }

    File('voice-perf-report.txt').writeAsStringSync(report.toString());

    // Gates, as the phone would feel them.
    expect(p90 * slow, lessThan(1.2), reason: 'a tapped word must start in about a second');
    expect(first * slow, lessThan(2.0), reason: 'reading must start within ~2 s');
    expect(rtf * slow, lessThan(natural ? Speech.slowRtf : 0.9), reason: 'reading must keep up with playback');
    expect(trT * slow, lessThan(1.0));
    if (asr != null) {
      // Whisper itself mishears a rare word now and then, so a little room is
      // left. The light voice (only for phones too slow for the natural one)
      // is a 70 MB model and measurably less clear, so its bar is lower; the
      // natural voice must read every test sentence right.
      expect(wordsOk / wordsChecked, greaterThanOrEqualTo(natural ? 0.85 : 0.8), reason: 'single words must be said whole and clearly');
      expect(werErrors / werWords, lessThan(natural ? 0.01 : 0.03), reason: 'words must not be skipped or repeated');
      expect(badSentences, lessThanOrEqualTo(natural ? 0 : 3), reason: 'sentences must not lose or gain words');
    }
  }, skip: base == null ? 'set VOCABLOOM_VOICE_BASE' : false, timeout: const Timeout(Duration(minutes: 20)));
}

const _bookSentences = [
  'Although it was raining heavily all morning, she decided to walk to the old library on the hill.',
  "Harry looked at his friend and smiled, but he didn't say a word.",
  'The train left the station at seven, and nobody noticed the little boy in the last carriage.',
  '"Where have you been?" his mother asked, holding the door open.',
  'It was the best of times, it was the worst of times.',
  'He opened the letter slowly, afraid of what it might say.',
  'They grow tomatoes, beans and potatoes in the garden behind the house.',
  'Through the window, she could see the lights of the city shining in the distance.',
  'If you want to learn a language, you have to read every day.',
  'The old man thought about his daughter, who lived far away in another country.',
  'Suddenly, the dog started barking, and everyone in the room jumped.',
  'Would you like some tea, or would you rather have a glass of water?',
];

const _numbers = {'1': 'one', '2': 'two', '3': 'three', '4': 'four', '5': 'five', '6': 'six', '7': 'seven', '8': 'eight', '9': 'nine', '10': 'ten'};

List<String> _words(String t) => RegExp(r"[a-z0-9']+").allMatches(t.toLowerCase()).map((m) => _numbers[m[0]] ?? m[0]!).toList();

/// Word-level edit distance between what was meant and what was heard.
(int, int) wordErrors(String meant, String heard) {
  final r = _words(meant), h = _words(heard);
  var d = List<int>.generate(h.length + 1, (j) => j);
  for (var i = 1; i <= r.length; i++) {
    final nd = List<int>.filled(h.length + 1, 0)..[0] = i;
    for (var j = 1; j <= h.length; j++) {
      nd[j] = min(min(d[j] + 1, nd[j - 1] + 1), d[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1));
    }
    d = nd;
  }
  return (d[h.length], r.length);
}

/// Whisper (base, English) through sherpa-onnx: writes down what a clip says.
class Asr {
  final so.OfflineRecognizer r;
  Asr(String dir) : r = _make(dir);

  static so.OfflineRecognizer _make(String dir) {
    so.initBindings(Platform.environment['SHERPA_ONNX_LIB_DIR']);
    return so.OfflineRecognizer(so.OfflineRecognizerConfig(
          model: so.OfflineModelConfig(
            whisper: so.OfflineWhisperModelConfig(encoder: '$dir/base-encoder.int8.onnx', decoder: '$dir/base-decoder.int8.onnx', language: 'en', task: 'transcribe'),
            tokens: '$dir/base-tokens.txt',
            modelType: 'whisper',
            numThreads: 2,
            debug: false,
          ),
        ));
  }

  /// [lead] then [word] with short pauses, as one clip.
  String transcribeJoined(String lead, String word) {
    final out = '${Directory.systemTemp.path}/asr_joined_$pid.wav';
    joinWavs([lead, word], [0.3, 0.3], out);
    final t = transcribe(out);
    File(out).deleteSync();
    return t;
  }

  String transcribe(String path) {
    final w = Pcm.read(path);
    final x = Float32List(w.samples.length);
    for (var i = 0; i < x.length; i++) {
      x[i] = w.samples[i] / 32768.0;
    }
    final st = r.createStream();
    st.acceptWaveform(samples: x, sampleRate: w.rate);
    r.decode(st);
    final text = r.getResult(st).text;
    st.free();
    return text;
  }

  void free() => r.free();
}

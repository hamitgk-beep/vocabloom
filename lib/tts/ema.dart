/// Turkish speech with EMA Lightning (Apache-2.0, github.com/canberk7/ema-lightning),
/// run through ONNX Runtime: Turkish letters in, 48 kHz speech out.
///
/// Three graphs, exported from the original model for one sentence at a time
/// (tools/voice_packs/ema_export.py):
///   text.onnx     ids [1,L]                                -> h [1,L,D], dur [1,L] (frames per letter)
///   sound.onnx    h, dur, cw, wstart [1,L], fw, fp [1,T],
///                 noise [1,S,T,C]                          -> z [1,T,C] (latents at 25 Hz)
///   decoder.onnx  z                                        -> audio [1,T*hop]
/// The timeline between the first two (how many frames each word gets) is
/// worked out here, exactly as the original engine does it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'ort.dart';

class EmaVoice {
  final OrtSession _text, _sound, _decoder;
  final Map<String, int> _ids;
  final int _steps, _latent, _hop, sampleRate, _maxWordFrames;

  EmaVoice._(this._text, this._sound, this._decoder, this._ids, this._steps, this._latent, this._hop, this.sampleRate,
      this._maxWordFrames);

  /// Loads the voice in [dir] (text.onnx, sound.onnx, decoder.onnx, config.json).
  factory EmaVoice.load(String dir, {int threads = 1, String? libDir}) {
    final ort = Ort.load(libDir);
    final cfg = jsonDecode(File('$dir/config.json').readAsStringSync()) as Map<String, dynamic>;
    final vocab = (cfg['vocab'] as List).cast<String>();
    return EmaVoice._(
      ort.session('$dir/text.onnx', threads: threads),
      ort.session('$dir/sound.onnx', threads: threads),
      ort.session('$dir/decoder.onnx', threads: threads),
      {for (var i = 0; i < vocab.length; i++) vocab[i]: i},
      (cfg['times'] as List).length,
      cfg['latent_dim'] as int,
      cfg['hop'] as int,
      cfg['sample_rate'] as int,
      (cfg['max_word_frames'] as int?) ?? 250,
    );
  }

  void close() {
    _text.close();
    _sound.close();
    _decoder.close();
  }

  /// Speech for [text]; [speed] above 1 is faster. The same [seed] gives the same take.
  Float32List generate(String text, {double speed = 1.0, int seed = 1}) {
    final t = turkishLetters(text, _ids.containsKey);
    if (t.isEmpty) return Float32List(0);
    final L = t.length;
    final ids = Int64List(L), cw = Int64List(L), ws = Int64List(L);
    var word = -1, start = 0;
    for (var i = 0; i < L; i++) {
      // A word begins at a letter after a space; the space belongs to the word before it.
      if (t[i] != ' ' && (i == 0 || t[i - 1] == ' ')) {
        word++;
        start = i;
      }
      ids[i] = _ids[t[i]] ?? 1;
      cw[i] = max(word, 0);
      ws[i] = word < 0 ? 0 : start;
    }
    final out = _text.run({'ids': Tensor.int64(ids, [1, L])}, ['h', 'dur']);
    final h = out['h']!, dur = out['dur']!.f32!;
    for (var i = 0; i < L; i++) {
      dur[i] /= speed;
    }
    // Frames per word, then each frame's word and its position inside that word.
    final words = cw[L - 1] + 1;
    final sums = List<double>.filled(words, 0);
    for (var i = 0; i < L; i++) {
      sums[cw[i]] += dur[i];
    }
    final n = [for (final s in sums) s.round().clamp(1, _maxWordFrames)];
    final T = n.fold(0, (a, b) => a + b);
    final fw = Int64List(T), fp = Float32List(T);
    var f = 0;
    for (var w = 0; w < words; w++) {
      for (var k = 0; k < n[w]; k++, f++) {
        fw[f] = w;
        fp[f] = k / n[w];
      }
    }
    final noise = Float32List(_steps * T * _latent);
    final rng = Random(seed);
    for (var i = 0; i < noise.length; i += 2) {
      // Box-Muller: two standard normal numbers from two uniform ones.
      final r = sqrt(-2 * log(1 - rng.nextDouble())), a = 2 * pi * rng.nextDouble();
      noise[i] = r * cos(a);
      if (i + 1 < noise.length) noise[i + 1] = r * sin(a);
    }
    final z = _sound.run({
      'h': h,
      'dur': Tensor.float(dur, [1, L]),
      'cw': Tensor.int64(cw, [1, L]),
      'wstart': Tensor.int64(ws, [1, L]),
      'fw': Tensor.int64(fw, [1, T]),
      'fp': Tensor.float(fp, [1, T]),
      'noise': Tensor.float(noise, [1, _steps, T, _latent]),
    }, ['z'])['z']!;
    final audio = _decoder.run({'z': z}, ['audio'])['audio']!.f32!;
    return audio.length > T * _hop ? Float32List.sublistView(audio, 0, T * _hop) : audio;
  }
}

const _typography = {'’': "'", '‘': "'", 'ʼ': "'", '´': "'", '`': "'", '“': '"', '”': '"', '„': '"', '«': '"', '»': '"',
  '–': '-', '—': '-', '−': '-', '…': '...'};
const _plain = {'â': 'a', 'î': 'i', 'û': 'u', 'á': 'a', 'à': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u', 'ñ': 'n', 'ß': 'ss'};

/// Written Turkish to the model's alphabet: numbers and a few symbols read
/// out, Turkish lowercase, accents dropped, anything else a space.
String turkishLetters(String text, bool Function(String) known) {
  var s = text.replaceAllMapped(RegExp(r'%\s*(\d+)'), (m) => 'yüzde ${m[1]}');
  s = s.replaceAllMapped(RegExp(r'(\d+)[.,](\d+)'), (m) => '${turkishNumber(int.parse(m[1]!))} virgül ${turkishNumber(int.parse(m[2]!))}');
  s = s.replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.length > 12 ? m[0]!.split('').map((d) => turkishNumber(int.parse(d))).join(' ') : turkishNumber(int.parse(m[0]!)));
  s = s.replaceAll('&', ' ve ').replaceAll('+', ' artı ');
  s = s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final c = _plain[_typography[ch] ?? ch] ?? _typography[ch] ?? ch;
    b.write(c.split('').every(known) ? c : ' ');
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _ones = ['', 'bir', 'iki', 'üç', 'dört', 'beş', 'altı', 'yedi', 'sekiz', 'dokuz'];
const _tens = ['', 'on', 'yirmi', 'otuz', 'kırk', 'elli', 'altmış', 'yetmiş', 'seksen', 'doksan'];

/// 1234 -> "bin iki yüz otuz dört".
String turkishNumber(int n) {
  if (n == 0) return 'sıfır';
  String hundreds(int x) {
    final p = <String>[];
    if (x >= 100) p.add(x ~/ 100 == 1 ? 'yüz' : '${_ones[x ~/ 100]} yüz');
    if (x % 100 >= 10) p.add(_tens[(x % 100) ~/ 10]);
    if (x % 10 > 0) p.add(_ones[x % 10]);
    return p.join(' ');
  }

  const scales = ['', 'bin', 'milyon', 'milyar'];
  final parts = <String>[];
  for (var i = 0; n > 0 && i < scales.length; i++, n ~/= 1000) {
    final g = n % 1000;
    if (g == 0) continue;
    if (i == 1 && g == 1) {
      parts.insert(0, 'bin');
    } else {
      parts.insert(0, [hundreds(g), scales[i]].where((x) => x.isNotEmpty).join(' '));
    }
  }
  return parts.join(' ');
}

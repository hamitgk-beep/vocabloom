// Task 5N: a small BERT cross-encoder run in plain Dart (no native library, no network, the same on every platform).
// It reads two texts and gives one probability. Two models use it:
//
//   idiom model: (expression phrase, sentence with the matched words in "[ ]") -> used as the expression here?
//     idiom.probability('kick the bucket', 'The boy [ kicked the bucket ] across the yard.')  -> low
//     idiom.probability('kick the bucket', 'Her grandfather [ kicked the bucket ] last year.')  -> high
//   sense model: ("word: dictionary definition", sentence with the word in "[ ]") -> is this the meaning here?
//
// Base: google/bert_uncased_L-4_H-256_A-4 (Apache-2.0; 4 layers, 256 wide). Fine-tuned only on data without corpus
// restrictions: contrastive sentences written for this project, public-domain book sentences labelled for it, and
// WordNet's own example sentences (tools/sentence_engine_5n).
//
// Weights: int8 per row for the large matrices (word embeddings, every Linear), float32 for the rest
// (tools/sentence_engine_5n/export_idiom_cls.py writes the file).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class CrossEncoder {
  final int hidden, layers, heads, inter;
  final double eps;
  final Map<String, int> _vocab;
  final Map<String, Float32List> _f = {};
  final Map<String, List<int>> _shape = {};

  // Word embeddings stay int8 (one row is dequantized per token).
  late final Int8List _wordQ;
  late final Float32List _wordS;

  CrossEncoder._(this.hidden, this.layers, this.heads, this.inter, this.eps, this._vocab);

  factory CrossEncoder.fromBytes(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'SXC1') throw const FormatException('not an SXC1 model');
    final hl = bd.getUint32(4, Endian.little);
    final hdr = jsonDecode(utf8.decode(bytes.sublist(8, 8 + hl))) as Map<String, dynamic>;
    final cfg = hdr['config'] as Map<String, dynamic>;
    final vocab = <String, int>{};
    final vl = hdr['vocab'] as List;
    for (var i = 0; i < vl.length; i++) {
      vocab[vl[i] as String] = i;
    }
    final c = CrossEncoder._(cfg['hidden'] as int, cfg['layers'] as int, cfg['heads'] as int, cfg['inter'] as int,
        (cfg['eps'] as num).toDouble(), vocab);
    var at = 8 + hl;
    for (final t in hdr['tensors'] as List) {
      final name = t['name'] as String;
      final shape = [for (final d in t['shape'] as List) d as int];
      final n = shape.fold(1, (a, b) => a * b);
      c._shape[name] = shape;
      if (t['q'] == 1) {
        final rows = shape[0], cols = n ~/ rows;
        final s = Float32List(rows);
        for (var r = 0; r < rows; r++) {
          s[r] = bd.getFloat32(at + 4 * r, Endian.little);
        }
        at += 4 * rows;
        final q = Int8List.sublistView(bytes, at, at + n);
        at += n;
        if (name == 'bert.embeddings.word_embeddings.weight') {
          c._wordQ = Int8List.fromList(q);
          c._wordS = s;
        } else {
          final f = Float32List(n);
          for (var r = 0; r < rows; r++) {
            final sc = s[r];
            for (var k = 0; k < cols; k++) {
              f[r * cols + k] = q[r * cols + k] * sc;
            }
          }
          c._f[name] = f;
        }
      } else {
        final f = Float32List(n);
        for (var k = 0; k < n; k++) {
          f[k] = bd.getFloat32(at + 4 * k, Endian.little);
        }
        at += 4 * n;
        c._f[name] = f;
      }
    }
    return c;
  }

  // ---- tokenizer (BERT uncased: lower case, strip accents, split punctuation, WordPiece) ----

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ù': 'u',
    'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'ğ': 'g', 'ş': 's', 'ı': 'i',
  };

  static bool _punct(int c) =>
      (c >= 33 && c <= 47) || (c >= 58 && c <= 64) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126) ||
      (c >= 0x2010 && c <= 0x2027) || (c >= 0x2030 && c <= 0x205E) || c == 0xA1 || c == 0xBF || c == 0xAB || c == 0xBB;

  List<String> _basic(String text) {
    final out = <String>[];
    final b = StringBuffer();
    void flush() {
      if (b.isNotEmpty) out.add(b.toString());
      b.clear();
    }

    for (final r in text.toLowerCase().runes) {
      if (r == 0 || r == 0xFFFD) continue;
      final ch = String.fromCharCode(r);
      if (r == 32 || r == 9 || r == 10 || r == 13 || r == 0xA0) {
        flush();
      } else if (r >= 0x300 && r <= 0x36F) {
        continue; // combining accent
      } else if (_punct(r)) {
        flush();
        out.add(ch);
      } else {
        b.write(_accents[ch] ?? ch);
      }
    }
    flush();
    return out;
  }

  List<int> _wordPiece(String w) {
    final unk = _vocab['[UNK]']!;
    if (w.length > 100) return [unk];
    final ids = <int>[];
    var start = 0;
    while (start < w.length) {
      var end = w.length;
      int? id;
      while (start < end) {
        final sub = (start > 0 ? '##' : '') + w.substring(start, end);
        id = _vocab[sub];
        if (id != null) break;
        end--;
      }
      if (id == null) return [unk];
      ids.add(id);
      start = end;
    }
    return ids;
  }

  /// [CLS] a [SEP] b [SEP] ids and segment ids, truncated (longest first) to [maxLen].
  ({List<int> ids, List<int> types}) encode(String a, String b, {int maxLen = 96}) {
    final x = [for (final w in _basic(a)) ..._wordPiece(w)];
    final y = [for (final w in _basic(b)) ..._wordPiece(w)];
    while (x.length + y.length > maxLen - 3) {
      if (x.length > y.length) {
        x.removeLast();
      } else {
        y.removeLast();
      }
    }
    final cls = _vocab['[CLS]']!, sep = _vocab['[SEP]']!;
    return (
      ids: [cls, ...x, sep, ...y, sep],
      types: [for (var i = 0; i < x.length + 2; i++) 0, for (var i = 0; i < y.length + 1; i++) 1],
    );
  }

  // ---- forward pass ----

  /// out[n, o] = x[n, i] · W[o, i] + b[o]
  Float32List _linear(Float32List x, int n, String name) {
    final w = _f['$name.weight']!, b = _f['$name.bias']!;
    final o = _shape['$name.weight']![0], i = _shape['$name.weight']![1];
    final out = Float32List(n * o);
    final xv = Float32x4List.view(x.buffer, x.offsetInBytes, x.length ~/ 4);
    final wv = Float32x4List.view(w.buffer, w.offsetInBytes, w.length ~/ 4);
    final i4 = i ~/ 4;
    for (var r = 0; r < n; r++) {
      final xo = r * i4;
      for (var c = 0; c < o; c++) {
        final wo = c * i4;
        var acc = Float32x4.zero();
        for (var k = 0; k < i4; k++) {
          acc += xv[xo + k] * wv[wo + k];
        }
        out[r * o + c] = acc.x + acc.y + acc.z + acc.w + b[c];
      }
    }
    return out;
  }

  void _layerNorm(Float32List x, int n, String name) {
    final g = _f['$name.weight']!, b = _f['$name.bias']!;
    for (var r = 0; r < n; r++) {
      final o = r * hidden;
      var mean = 0.0;
      for (var k = 0; k < hidden; k++) {
        mean += x[o + k];
      }
      mean /= hidden;
      var v = 0.0;
      for (var k = 0; k < hidden; k++) {
        final d = x[o + k] - mean;
        v += d * d;
      }
      final inv = 1 / math.sqrt(v / hidden + eps);
      for (var k = 0; k < hidden; k++) {
        x[o + k] = (x[o + k] - mean) * inv * g[k] + b[k];
      }
    }
  }

  static double _erf(double x) {
    // Abramowitz & Stegun 7.1.26 (|error| < 1.5e-7)
    final s = x < 0 ? -1.0 : 1.0;
    x = x.abs();
    final t = 1 / (1 + 0.3275911 * x);
    final y = 1 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * math.exp(-x * x);
    return s * y;
  }

  /// Probability that the marked words are used as the expression [phrase] in [marked].
  double probability(String phrase, String marked) {
    final e = encode(phrase, marked);
    final n = e.ids.length, h = hidden;
    var x = Float32List(n * h);
    final pos = _f['bert.embeddings.position_embeddings.weight']!, typ = _f['bert.embeddings.token_type_embeddings.weight']!;
    for (var t = 0; t < n; t++) {
      final id = e.ids[t], sc = _wordS[id];
      for (var k = 0; k < h; k++) {
        x[t * h + k] = _wordQ[id * h + k] * sc + pos[t * h + k] + typ[e.types[t] * h + k];
      }
    }
    _layerNorm(x, n, 'bert.embeddings.LayerNorm');
    final dh = h ~/ heads, scale = 1 / math.sqrt(dh);
    for (var l = 0; l < layers; l++) {
      final p = 'bert.encoder.layer.$l';
      final q = _linear(x, n, '$p.attention.self.query');
      final k = _linear(x, n, '$p.attention.self.key');
      final v = _linear(x, n, '$p.attention.self.value');
      final ctx = Float32List(n * h);
      final sc = Float64List(n);
      for (var hd = 0; hd < heads; hd++) {
        final o = hd * dh;
        for (var i = 0; i < n; i++) {
          var mx = -1e30;
          for (var j = 0; j < n; j++) {
            var d = 0.0;
            for (var c = 0; c < dh; c++) {
              d += q[i * h + o + c] * k[j * h + o + c];
            }
            sc[j] = d * scale;
            if (sc[j] > mx) mx = sc[j];
          }
          var sum = 0.0;
          for (var j = 0; j < n; j++) {
            sc[j] = math.exp(sc[j] - mx);
            sum += sc[j];
          }
          for (var j = 0; j < n; j++) {
            final a = sc[j] / sum;
            for (var c = 0; c < dh; c++) {
              ctx[i * h + o + c] += a * v[j * h + o + c];
            }
          }
        }
      }
      final ao = _linear(ctx, n, '$p.attention.output.dense');
      for (var t = 0; t < n * h; t++) {
        ao[t] += x[t];
      }
      _layerNorm(ao, n, '$p.attention.output.LayerNorm');
      final mid = _linear(ao, n, '$p.intermediate.dense');
      for (var t = 0; t < mid.length; t++) {
        final z = mid[t];
        mid[t] = 0.5 * z * (1 + _erf(z / math.sqrt2));
      }
      final out = _linear(mid, n, '$p.output.dense');
      for (var t = 0; t < n * h; t++) {
        out[t] += ao[t];
      }
      _layerNorm(out, n, '$p.output.LayerNorm');
      x = out;
    }
    // pooler on [CLS], then the two-way classifier
    final cls = Float32List.fromList(x.sublist(0, h));
    final pooled = _linear(cls, 1, 'bert.pooler.dense');
    for (var t = 0; t < h; t++) {
      pooled[t] = _tanh(pooled[t]);
    }
    final logits = _linear(pooled, 1, 'classifier');
    final d = logits[1] - logits[0];
    return 1 / (1 + math.exp(-d));
  }

  static double _tanh(double z) {
    if (z > 20) return 1;
    if (z < -20) return -1;
    final e = math.exp(2 * z);
    return (e - 1) / (e + 1);
  }
}

// Task 5E, stage 5: runs a BERT-family ONNX model from Dart through the ONNX Runtime the app already ships with
// sherpa-onnx (lib/tts/ort.dart), with a WordPiece tokenizer written in Dart. Measures model load time, time per
// sentence and memory, and prints scores to compare with the Python run (onnx_bench.py). Not part of the app's
// test suite; nothing here is used by the app. Run from the repository root:
//
//   ONNX_MODEL=model.onnx ONNX_VOCAB=vocab.txt ONNX_KIND=bi|cross ONNX_LIB=<dir with libonnxruntime.so> \
//   ONNX_PAIRS=pairs.tsv flutter test tools/nlp_research/onnx_bench_test.dart
//
// pairs.tsv: sentence <TAB> meaning, one pair a line.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/tts/ort.dart';

/// BERT uncased tokenizer: lower case, accents removed, split on spaces and punctuation, then WordPiece.
class WordPiece {
  final Map<String, int> vocab;
  WordPiece(this.vocab);
  factory WordPiece.file(String path) {
    final v = <String, int>{};
    var i = 0;
    for (final l in File(path).readAsLinesSync()) {
      v[l] = i++;
    }
    return WordPiece(v);
  }

  static final _punct = RegExp(r'''[!-/:-@\[-`{-~ -⁯¡-¿]''');
  static const _accents = {'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ï': 'i',
    'î': 'i', 'ó': 'o', 'ö': 'o', 'ô': 'o', 'ú': 'u', 'ü': 'u', 'û': 'u', 'ç': 'c', 'ñ': 'n', 'ş': 's', 'ğ': 'g', 'ı': 'i'};

  List<String> basic(String text) {
    final s = text.toLowerCase().split('').map((c) => _accents[c] ?? c).join();
    final out = <String>[];
    for (final w in s.split(RegExp(r'\s+'))) {
      var cur = StringBuffer();
      for (final ch in w.split('')) {
        if (_punct.hasMatch(ch)) {
          if (cur.isNotEmpty) out.add(cur.toString());
          cur = StringBuffer();
          out.add(ch);
        } else {
          cur.write(ch);
        }
      }
      if (cur.isNotEmpty) out.add(cur.toString());
    }
    return out;
  }

  List<int> ids(String text) {
    final out = <int>[];
    final unk = vocab['[UNK]']!;
    for (final w in basic(text)) {
      if (w.length > 100) {
        out.add(unk);
        continue;
      }
      var start = 0;
      final pieces = <int>[];
      var bad = false;
      while (start < w.length) {
        var end = w.length;
        int? cur;
        while (start < end) {
          final sub = (start > 0 ? '##' : '') + w.substring(start, end);
          final id = vocab[sub];
          if (id != null) {
            cur = id;
            break;
          }
          end--;
        }
        if (cur == null) {
          bad = true;
          break;
        }
        pieces.add(cur);
        start = end;
      }
      out.addAll(bad ? [unk] : pieces);
    }
    return out;
  }

  /// input_ids, attention_mask, token_type_ids for one text or a pair, at most [max] tokens.
  (List<int>, List<int>) encode(String a, [String? b, int max = 128]) {
    final cls = vocab['[CLS]']!, sep = vocab['[SEP]']!;
    var x = ids(a), y = b == null ? <int>[] : ids(b);
    while (x.length + y.length + (b == null ? 2 : 3) > max) {
      if (x.length >= y.length) {
        x = x.sublist(0, x.length - 1);
      } else {
        y = y.sublist(0, y.length - 1);
      }
    }
    final idsOut = [cls, ...x, sep, if (b != null) ...[...y, sep]];
    final types = [for (var i = 0; i < x.length + 2; i++) 0, if (b != null) for (var i = 0; i < y.length + 1; i++) 1];
    return (idsOut, types);
  }
}

void main() {
  final model = Platform.environment['ONNX_MODEL'];
  if (model == null) return;
  test('onnx bench', () {
    final kind = Platform.environment['ONNX_KIND'] ?? 'bi';
    final rss0 = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();
    final ort = Ort.load(Platform.environment['ONNX_LIB']);
    final tok = WordPiece.file(Platform.environment['ONNX_VOCAB']!);
    final s = ort.session(model, threads: int.tryParse(Platform.environment['ONNX_THREADS'] ?? '') ?? 2);
    final loadMs = sw.elapsedMilliseconds;
    final rss1 = ProcessInfo.currentRss;
    final pairs = [
      for (final l in File(Platform.environment['ONNX_PAIRS']!).readAsLinesSync())
        if (l.contains('\t')) l.split('\t'),
    ];
    final hasTypes = Platform.environment['ONNX_NO_TYPES'] == null;
    Map<String, Tensor> run(List<int> ids, List<int> types) {
      final n = ids.length;
      return s.run({
        'input_ids': Tensor.int64(Int64List.fromList(ids), [1, n]),
        'attention_mask': Tensor.int64(Int64List.fromList(List.filled(n, 1)), [1, n]),
        if (hasTypes) 'token_type_ids': Tensor.int64(Int64List.fromList(types), [1, n]),
      }, [kind == 'bi' ? 'last_hidden_state' : 'logits']);
    }

    Float32List embed(String t) {
      final (ids, types) = tok.encode(t);
      final h = run(ids, types)['last_hidden_state']!;
      final dim = h.shape[2], n = h.shape[1];
      final v = Float32List(dim);
      for (var i = 0; i < n; i++) {
        for (var d = 0; d < dim; d++) {
          v[d] += h.f32![i * dim + d] / n;
        }
      }
      var norm = 0.0;
      for (final x in v) {
        norm += x * x;
      }
      norm = sqrt(norm);
      for (var d = 0; d < dim; d++) {
        v[d] /= norm;
      }
      return v;
    }

    final times = <int>[];
    final out = StringBuffer();
    for (final p in pairs) {
      final t = Stopwatch()..start();
      double score;
      if (kind == 'bi') {
        final a = embed(p[0]), b = embed(p[1]);
        score = 0;
        for (var d = 0; d < a.length; d++) {
          score += a[d] * b[d];
        }
      } else {
        final (ids, types) = tok.encode(p[0], p[1]);
        final lg = run(ids, types)['logits']!.f32!;
        score = lg.length == 1 ? lg[0] : lg[1] - lg[0];
      }
      times.add(t.elapsedMicroseconds);
      out.writeln(score.toStringAsFixed(5));
    }
    times.sort();
    final rss2 = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('kind $kind, model ${File(model).lengthSync() / 1e6} MB, load $loadMs ms, pairs ${pairs.length}, '
        'per pair median ${times[times.length ~/ 2] / 1000} ms, p95 ${times[(times.length * 0.95).floor()] / 1000} ms; '
        'RSS before ${rss0 ~/ 1048576} MB, after load ${rss1 ~/ 1048576} MB, after run ${rss2 ~/ 1048576} MB');
    final o = Platform.environment['ONNX_OUT'];
    if (o != null) File(o).writeAsStringSync(out.toString());
    s.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}

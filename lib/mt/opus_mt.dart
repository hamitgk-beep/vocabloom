/// Offline English -> Turkish sentence translation with an OPUS-MT (Marian)
/// model, run through the app's own ONNX Runtime binding (lib/tts/ort.dart).
///
/// The model folder holds the files of `onnx-community/opus-mt-tc-big-en-tr`
/// (CC-BY 4.0): config.json, vocab.json, source.spm and the int8 encoder and
/// decoder. Steps: SentencePiece pieces -> vocab ids + `</s>`, the encoder
/// once, then greedy decoding with the decoder (no key/value cache, so one
/// decoder file is enough), ids -> pieces -> text.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../tts/ort.dart';
import 'sentencepiece.dart';

class OpusMtModel {
  final SentencePiece _spm;
  final Map<String, int> _vocab;
  final List<String> _pieces;
  final OrtSession _enc, _dec;
  final int _start, _eos, _pad, _unk;

  /// Inputs longer than this many pieces are not translated (a sentence is
  /// far shorter; the model's own limit is 512).
  static const maxInput = 256;

  OpusMtModel._(this._spm, this._vocab, this._pieces, this._enc, this._dec, this._start, this._eos, this._pad, this._unk);

  /// Loads the model in [dir]; [libDir] is where ONNX Runtime is (tests).
  factory OpusMtModel.load(String dir, {int threads = 2, String? libDir}) {
    final cfg = jsonDecode(File('$dir/config.json').readAsStringSync()) as Map<String, dynamic>;
    final vocab = (jsonDecode(File('$dir/vocab.json').readAsStringSync()) as Map<String, dynamic>).cast<String, int>();
    final pieces = List<String>.filled(vocab.values.fold(0, (m, v) => v > m ? v : m) + 1, '');
    vocab.forEach((p, i) => pieces[i] = p);
    final spm = SentencePiece.fromBytes(File('$dir/source.spm').readAsBytesSync());
    final ort = Ort.load(libDir);
    return OpusMtModel._(
      spm,
      vocab,
      pieces,
      ort.session('$dir/onnx/encoder_model_int8.onnx', threads: threads),
      ort.session('$dir/onnx/decoder_model_int8.onnx', threads: threads),
      cfg['decoder_start_token_id'] as int,
      cfg['eos_token_id'] as int,
      cfg['pad_token_id'] as int,
      vocab['<unk>'] ?? 1,
    );
  }

  /// The model's input ids for [text] (ends with `</s>`).
  List<int> ids(String text) => [for (final p in _spm.encode(text)) _vocab[p] ?? _unk, _eos];

  /// The Turkish of [text], or null when there is nothing to translate.
  String? translate(String text) {
    final src = ids(text);
    if (src.length < 2 || src.length > maxInput) return null;
    final n = src.length;
    final input = Int64List.fromList(src);
    final mask = Int64List(n)..fillRange(0, n, 1);
    final hidden = _enc.run({
      'input_ids': Tensor.int64(input, [1, n]),
      'attention_mask': Tensor.int64(mask, [1, n]),
    }, ['last_hidden_state'])['last_hidden_state']!;
    final out = <int>[_start];
    final limit = 2 * n + 16 < 512 ? 2 * n + 16 : 512;
    for (var step = 0; step < limit; step++) {
      final logits = _dec.run({
        'input_ids': Tensor.int64(Int64List.fromList(out), [1, out.length]),
        'encoder_attention_mask': Tensor.int64(mask, [1, n]),
        'encoder_hidden_states': hidden,
      }, ['logits'])['logits']!;
      final v = logits.shape.last;
      final row = Float32List.sublistView(logits.f32!, (out.length - 1) * v, out.length * v);
      var best = -1;
      var bestScore = double.negativeInfinity;
      for (var k = 0; k < v; k++) {
        if (k == _pad) continue; // never the start / padding token
        if (row[k] > bestScore) {
          bestScore = row[k];
          best = k;
        }
      }
      if (best == _eos || best < 0) break;
      out.add(best);
    }
    final text2 = SentencePiece.decode([
      for (final i in out.skip(1))
        if (i != _unk && i < _pieces.length) _pieces[i],
    ]);
    return text2.isEmpty ? null : text2;
  }

  void close() {
    _enc.close();
    _dec.close();
  }
}

/// The model in its own isolate, so translating never blocks the screen.
class OpusMtWorker {
  final Isolate _isolate;
  final SendPort _port;
  final ReceivePort _inbox;
  final _waiting = <int, Completer<String?>>{};
  var _next = 0;
  final _closed = Completer<void>();

  OpusMtWorker._(this._isolate, this._port, this._inbox) {
    _inbox.listen((m) {
      if (m == 'closed') {
        if (!_closed.isCompleted) _closed.complete();
        return;
      }
      if (m is List && m.length == 3) {
        final c = _waiting.remove(m[0] as int);
        if (c == null) return;
        if (m[2] != null) {
          c.completeError(OrtError(m[2] as String));
        } else {
          c.complete(m[1] as String?);
        }
      }
    });
  }

  /// Starts the isolate and loads the model there.
  static Future<OpusMtWorker> start(String dir, {int threads = 2, String? libDir}) async {
    final ready = ReceivePort();
    final iso = await Isolate.spawn(_main, [ready.sendPort, dir, threads, libDir]);
    final first = await ready.first;
    if (first is String) {
      iso.kill(priority: Isolate.immediate);
      throw OrtError(first);
    }
    final inbox = ReceivePort();
    (first as SendPort).send(inbox.sendPort);
    return OpusMtWorker._(iso, first, inbox);
  }

  static void _main(List<Object?> args) {
    final reply = args[0] as SendPort;
    final OpusMtModel model;
    try {
      model = OpusMtModel.load(args[1] as String, threads: args[2] as int, libDir: args[3] as String?);
    } catch (e) {
      reply.send('$e');
      return;
    }
    final port = ReceivePort();
    reply.send(port.sendPort);
    SendPort? out;
    port.listen((m) {
      if (m is SendPort) {
        out = m;
        return;
      }
      if (m == 'close') {
        // Releases the model files (Windows cannot delete open files).
        model.close();
        out?.send('closed');
        port.close();
        return;
      }
      final id = (m as List)[0] as int;
      try {
        out?.send([id, model.translate(m[1] as String), null]);
      } catch (e) {
        out?.send([id, null, '$e']);
      }
    });
  }

  Future<String?> translate(String text) {
    final id = _next++;
    final c = _waiting[id] = Completer<String?>();
    _port.send([id, text]);
    return c.future;
  }

  /// Closes the model; done once its files are released.
  Future<void> close() async {
    for (final c in _waiting.values) {
      c.completeError(OrtError('closed'));
    }
    _waiting.clear();
    _port.send('close');
    try {
      await _closed.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      // A translation still running: the isolate is stopped below.
    }
    _inbox.close();
    _isolate.kill();
  }
}

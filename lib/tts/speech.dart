import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import '../data/user_db.dart';
import 'voices.dart';

enum PackState { missing, downloading, extracting, ready, failed }

/// Natural offline speech. The voice models (Supertonic for English, Piper for
/// Turkish) run on the device through sherpa-onnx in a background isolate;
/// audio is played with audioplayers. Each voice pack is downloaded once
/// (Settings > Read aloud) and then works without internet.
class Speech extends ChangeNotifier {
  Speech._();
  static final instance = Speech._();

  Directory _root = Directory.systemTemp;
  UserDb? _user;
  final _state = <String, PackState>{};
  final _progress = <String, double>{};
  final _error = <String, String>{};

  /// Supported where sherpa-onnx ships native libraries.
  static bool get supported => Platform.isAndroid || Platform.isIOS || Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  Directory packDir(VoicePack pk) => Directory(p.join(_root.path, 'voice', pk.id));
  File _readyMark(VoicePack pk) => File(p.join(packDir(pk).path, '.ready'));

  void init(Directory dataDir, UserDb user) {
    _root = dataDir;
    _user = user;
    for (final pk in voicePacks) {
      _state[pk.id] = _readyMark(pk).existsSync() ? PackState.ready : PackState.missing;
    }
    _steps = int.tryParse(user.getSetting('tts_steps') ?? '') ?? 5;
    // The first test build used a slower English model; free its space.
    try {
      final old = Directory(p.join(_root.path, 'voice', 'kokoro-en-v1'));
      if (old.existsSync()) old.deleteSync(recursive: true);
    } catch (_) {}
    // Keep the cache of spoken words from growing without end.
    try {
      final cache = Directory(p.join(_root.path, 'voice', 'cache'));
      if (cache.existsSync() && cache.listSync().length > 4000) cache.deleteSync(recursive: true);
    } catch (_) {}
  }

  PackState stateOf(VoicePack pk) => _state[pk.id] ?? PackState.missing;
  double progressOf(VoicePack pk) => _progress[pk.id] ?? 0;
  String? errorOf(VoicePack pk) => _error[pk.id];
  bool isReady(VoicePack pk) => stateOf(pk) == PackState.ready;

  /// The English voice pack is installed.
  bool get ready => isReady(englishPack);

  /// Quality steps of the English model, chosen from the measured speed of
  /// this device (more steps = smoother voice, slower).
  int _steps = 5;
  int get qualitySteps => _steps;
  final _jobSteps = <int, int>{};
  double? _perStep;

  /// Target: speech is made at least ~3x faster than it plays, so reading
  /// flows and a tapped word answers quickly, on slow and fast phones alike.
  static const _targetRtf = 0.3;
  static const _wordSteps = int.fromEnvironment('VOCABLOOM_WORD_STEPS', defaultValue: 4);

  void _learnSpeed(double rtf, double secs, int steps) {
    if (secs < 1.5 || rtf <= 0) return; // short clips are mostly overhead
    final ps = rtf / steps;
    _perStep = _perStep == null ? ps : _perStep! * 0.6 + ps * 0.4;
    final next = (_targetRtf / _perStep!).floor().clamp(2, 10);
    if (next != _steps) {
      _steps = next;
      _user?.setSetting('tts_steps', '$_steps');
    }
  }

  // ---------------------------------------------------------------- settings

  /// Chosen English voice.
  Voice get voice => voiceById[_user?.getSetting('tts_voice')] ?? voices.first;
  set voice(Voice v) {
    _user?.setSetting('tts_voice', v.id);
    notifyListeners();
  }

  /// Chosen Turkish voice.
  Voice get trVoice => voiceById[_user?.getSetting('tts_voice_tr')] ?? trVoices.first;
  set trVoice(Voice v) {
    _user?.setSetting('tts_voice_tr', v.id);
    notifyListeners();
  }

  Voice voiceFor(String lang) => lang == 'tr' ? trVoice : voice;

  /// Reading speed (1.0 = normal).
  double get speed => double.tryParse(_user?.getSetting('tts_speed') ?? '') ?? 1.0;
  set speed(double v) {
    _user?.setSetting('tts_speed', v.toStringAsFixed(2));
    notifyListeners();
  }

  /// Say a word as soon as its panel opens.
  bool get autoWord => _user?.getSetting('tts_auto_word') == '1';
  set autoWord(bool v) {
    _user?.setSetting('tts_auto_word', v ? '1' : null);
    notifyListeners();
  }

  // ---------------------------------------------------------------- download

  final _clients = <String, http.Client>{};

  Future<void> download(VoicePack pk, {String? url}) async {
    final st = stateOf(pk);
    if (st == PackState.downloading || st == PackState.extracting || st == PackState.ready) return;
    _state[pk.id] = PackState.downloading;
    _progress[pk.id] = 0;
    _error.remove(pk.id);
    notifyListeners();
    final voiceDir = Directory(p.join(_root.path, 'voice'));
    final zip = File(p.join(voiceDir.path, '${pk.id}.zip.part'));
    try {
      await voiceDir.create(recursive: true);
      final client = _clients[pk.id] = http.Client();
      final res = await client.send(http.Request('GET', Uri.parse(url ?? pk.url)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      final sink = zip.openWrite();
      var got = 0;
      var lastNotify = DateTime(0);
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds > 200) {
            lastNotify = now;
            _progress[pk.id] = min(1, got / (total ?? pk.mb * 1024 * 1024));
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (total != null && got < total) throw const HttpException('download interrupted');
      _state[pk.id] = PackState.extracting;
      notifyListeners();
      final dir = packDir(pk);
      if (dir.existsSync()) await dir.delete(recursive: true);
      final zipPath = zip.path, out = voiceDir.path;
      await Isolate.run(() {
        final input = InputFileStream(zipPath);
        try {
          extractArchiveToDiskSync(ZipDecoder().decodeStream(input), out);
        } finally {
          input.closeSync();
        }
      });
      await zip.delete();
      if (!File(p.join(dir.path, 'tokens.txt')).existsSync()) throw const FileSystemException('voice pack is incomplete');
      await _readyMark(pk).writeAsString('1');
      _state[pk.id] = PackState.ready;
      unawaited(warmUp());
    } catch (e) {
      debugPrint('voice pack ${pk.id}: $e');
      _error[pk.id] = '$e';
      _state[pk.id] = PackState.failed;
      try {
        if (zip.existsSync()) zip.deleteSync();
      } catch (_) {}
    } finally {
      _clients.remove(pk.id)?.close();
      notifyListeners();
    }
  }

  void cancelDownload(VoicePack pk) => _clients[pk.id]?.close();

  Future<void> deletePack(VoicePack pk) async {
    await stop();
    await _shutdownWorker();
    try {
      final d = packDir(pk);
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
    _state[pk.id] = PackState.missing;
    notifyListeners();
  }

  // ---------------------------------------------------------------- synthesis

  SendPort? _worker;
  Isolate? _isolate;
  ReceivePort? _inbox;
  Completer<SendPort>? _starting;
  int _nextId = 0;
  final _waiting = <int, Completer<String>>{};
  final _queue = ListQueue<_Job>();
  bool _busy = false;

  Future<SendPort> _ensureWorker() async {
    if (_worker != null) return _worker!;
    if (_starting != null) return _starting!.future;
    final c = _starting = Completer<SendPort>();
    final inbox = _inbox = ReceivePort();
    inbox.listen((m) {
      if (m is SendPort) {
        _worker = m;
        c.complete(m);
      } else if (m is List) {
        final done = _waiting.remove(m[0] as int);
        final steps = _jobSteps.remove(m[0] as int);
        if (m[1] == null) {
          if (steps != null) _learnSpeed(m[3] as double, m[4] as double, steps);
          done?.complete(m[2] as String);
        } else {
          done?.completeError(Exception(m[1]));
        }
        _busy = false;
        _pump();
      }
    });
    // VOCABLOOM_TTS_THREADS lets tests act like a phone with few fast cores.
    final threads = int.tryParse(Platform.environment['VOCABLOOM_TTS_THREADS'] ?? '') ?? max(1, min(4, Platform.numberOfProcessors - 1));
    _isolate = await Isolate.spawn(_workerMain, [inbox.sendPort, threads]);
    final port = await c.future;
    _starting = null;
    return port;
  }

  Future<void> _shutdownWorker() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _worker = null;
    _inbox?.close();
    _inbox = null;
    for (final c in _waiting.values) {
      c.completeError(Exception('stopped'));
    }
    _waiting.clear();
    _queue.clear();
    _busy = false;
  }

  /// Synthesizes [text] into a WAV file and returns its path.
  /// [urgent] jobs (a tapped word) go before queued sentences.
  Future<String> synth(String text, {Voice? v, bool urgent = false, double? speed}) async {
    final vo = v ?? voice;
    if (!isReady(vo.pack)) throw StateError('voice pack ${vo.pack.id} not downloaded');
    final id = _nextId++;
    final out = p.join(Directory.systemTemp.path, 'vocabloom_tts_${pid}_$id.wav');
    final c = Completer<String>();
    _waiting[id] = c;
    final dir = packDir(vo.pack).path;
    // A lone word needs few quality steps to sound right, and must answer fast.
    final steps = text.trim().contains(' ') ? _steps : min(_steps, _wordSteps);
    final engine = [vo.engine, vo.pack.id, dir, '$steps'];
    if (vo.engine == 'supertonic') _jobSteps[id] = steps;
    final job = _Job(id, _forSpeech(text), vo.sid, speed ?? this.speed, out, engine);
    urgent ? _queue.addFirst(job) : _queue.add(job);
    await _ensureWorker();
    _pump();
    return c.future;
  }

  /// A lone word is said most cleanly as a capitalized one-word sentence
  /// ("And." rather than "and"); other text gets a final full stop if it has none.
  static String _forSpeech(String text) {
    final t = text.trim();
    if (t.isNotEmpty && !t.contains(' ')) {
      final w = t.replaceAll(RegExp(r'[.!?…,;:"]+$'), '');
      return '${w[0].toUpperCase()}${w.substring(1)}.';
    }
    return RegExp(r'[.!?…,;:]$').hasMatch(t) ? t : '$t.';
  }

  void _pump() {
    if (_busy || _worker == null || _queue.isEmpty) return;
    _busy = true;
    final j = _queue.removeFirst();
    _worker!.send([j.id, j.text, j.sid, j.speed, j.out, j.engine]);
  }

  /// Drops queued (not yet started) jobs, e.g. when reading stops.
  void clearQueue() {
    for (final j in _queue) {
      _waiting.remove(j.id)?.completeError(Exception('cancelled'));
    }
    _queue.clear();
  }

  // ---------------------------------------------------------------- playback

  AudioPlayer? _player;
  StreamSubscription<void>? _doneSub;
  Completer<void>? _playing;

  AudioPlayer get player => _player ??= AudioPlayer()..setReleaseMode(ReleaseMode.stop);

  /// Plays a WAV file and completes when it has finished (or was stopped).
  Future<void> playFile(String path, {bool keep = false}) async {
    await _finishCurrent();
    final c = _playing = Completer<void>();
    _doneSub = player.onPlayerComplete.listen((_) {
      if (!c.isCompleted) c.complete();
    });
    try {
      await player.play(DeviceFileSource(path));
      await c.future;
    } finally {
      if (identical(_playing, c)) {
        await _doneSub?.cancel();
        _doneSub = null;
      }
      if (!keep) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<void> _finishCurrent() async {
    final c = _playing;
    if (c != null && !c.isCompleted) c.complete();
    await _doneSub?.cancel();
    _doneSub = null;
  }

  Future<void> pause() => player.pause();
  Future<void> resume() => player.resume();

  Future<void> stop() async {
    clearQueue();
    if (_player != null) await _player!.stop();
    await _finishCurrent();
  }

  int _sayToken = 0;

  /// Called before a word is said, so book reading can step aside.
  VoidCallback? onSay;

  /// Says a word or short text right away (interrupting what is playing).
  Future<void> say(String text, {Voice? v, double? speed}) async {
    onSay?.call();
    final token = ++_sayToken;
    final vo = v ?? voice;
    final sp = speed ?? this.speed;
    String? cached;
    try {
      cached = await _cached(text, vo, sp);
    } catch (_) {
      // a prefetch of it was cancelled (e.g. reading stopped): make it now
      cached = await _cached(text, vo, sp);
    }
    if (cached != null) {
      if (token == _sayToken) await playFile(cached, keep: true);
      return;
    }
    // Long text: not kept.
    final path = await synth(text, v: vo, urgent: true, speed: sp);
    if (token != _sayToken) {
      _deleteQuietly(path);
      return;
    }
    await playFile(path);
  }

  final _making = <String, Future<String?>>{};

  /// Audio file of a word or short text, made once and kept, so a second tap
  /// plays at once. Null for long text (not kept).
  Future<String?> _cached(String text, Voice v, double speed, {bool urgent = true}) {
    if (text.length > 120 || !isReady(v.pack)) return Future.value(null);
    final f = _cacheFile(text, v, speed);
    if (f.existsSync()) return Future.value(f.path);
    return _making.putIfAbsent(f.path, () async {
      try {
        final tmp = await synth(text, v: v, urgent: urgent, speed: speed);
        f.parent.createSync(recursive: true);
        try {
          File(tmp).renameSync(f.path);
        } catch (_) {
          File(tmp).copySync(f.path);
          _deleteQuietly(tmp);
        }
        return f.path;
      } finally {
        _making.remove(f.path);
      }
    });
  }

  /// Makes the audio of [text] ahead of time (e.g. when a word's panel opens),
  /// so the speaker button answers at once.
  void prefetch(String text, {String lang = 'en'}) {
    final v = voiceFor(lang);
    if (!isReady(v.pack)) return;
    _cached(text, v, speed, urgent: false).ignore();
  }

  static void _deleteQuietly(String path) {
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  File _cacheFile(String text, Voice v, double speed) {
    final key = '${v.id}|${speed.toStringAsFixed(2)}|${v.pack.id}|$text';
    final h = _fnv(key);
    return File(p.join(_root.path, 'voice', 'cache', '${v.id}_$h.wav'));
  }

  static String _fnv(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return h.toRadixString(36);
  }

  /// Loads the voice model in the background (and runs it once) so the first
  /// tap does not wait for it.
  Future<void> warmUp() async {
    for (final lang in const ['en', 'tr']) {
      final v = voiceFor(lang);
      if (!isReady(v.pack)) continue;
      try {
        // A full sentence, so the English model also measures this phone's speed.
        _deleteQuietly(await synth(lang == 'en' ? 'Reading a little every day is the fastest way to learn new words.' : 'Merhaba.', v: v));
      } catch (_) {}
    }
  }
}

class _Job {
  final int id;
  final String text;
  final int sid;
  final double speed;
  final String out;
  final List<String> engine;
  _Job(this.id, this.text, this.sid, this.speed, this.out, this.engine);
}

so.OfflineTts _createEngine(List<String> e, int threads) {
  final kind = e[0], dir = e[2];
  final model = kind == 'supertonic'
      ? so.OfflineTtsModelConfig(
          supertonic: so.OfflineTtsSupertonicModelConfig(
            durationPredictor: '$dir/duration_predictor.int8.onnx',
            textEncoder: '$dir/text_encoder.int8.onnx',
            vectorEstimator: '$dir/vector_estimator.int8.onnx',
            vocoder: '$dir/vocoder.int8.onnx',
            ttsJson: '$dir/tts.json',
            unicodeIndexer: '$dir/unicode_indexer.bin',
            voiceStyle: '$dir/voice.bin',
          ),
          numThreads: threads,
          debug: false,
        )
      : so.OfflineTtsModelConfig(
          vits: so.OfflineTtsVitsModelConfig(
            model: '$dir/model.onnx',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data',
          ),
          numThreads: threads,
          debug: false,
        );
  return so.OfflineTts(so.OfflineTtsConfig(model: model));
}

/// Extra takes allowed for a lone word that came out with a stray sound.
const _wordRetakes = int.fromEnvironment('VOCABLOOM_WORD_RETAKES', defaultValue: 1);

/// Number of separate loud stretches in a clip (a clean short word has one).
int _bursts(Float32List x, int sr) {
  if (sr == 0 || x.isEmpty) return 0;
  final h = (sr * 0.03).round();
  final e = <double>[];
  for (var i = 0; i + h < x.length; i += h) {
    var s = 0.0;
    for (var j = i; j < i + h; j++) {
      s += x[j] * x[j];
    }
    e.add(sqrt(s / h));
  }
  if (e.isEmpty) return 0;
  final th = 0.15 * e.reduce(max);
  var n = 0, gap = 99;
  for (final v in e) {
    if (v > th) {
      if (gap >= 4) n++;
      gap = 0;
    } else {
      gap++;
    }
  }
  return n;
}

/// Background isolate: keeps up to one English and one Turkish model loaded
/// and writes one WAV file per request.
void _workerMain(List args) {
  final reply = args[0] as SendPort;
  final threads = args[1] as int;
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  Object? initError;
  try {
    // Tests point at the native library; apps find it next to the executable.
    so.initBindings(Platform.environment['SHERPA_ONNX_LIB_DIR']);
  } catch (e) {
    initError = e;
  }
  final engines = <String, so.OfflineTts>{};
  String family(String key) => key.split('-').first; // 'supertonic' / 'piper'
  inbox.listen((m) {
    final l = m as List;
    final id = l[0] as int;
    try {
      if (initError != null) throw Exception('speech engine unavailable: $initError');
      final text = l[1] as String, sid = l[2] as int, speed = l[3] as double, out = l[4] as String;
      final e = (l[5] as List).cast<String>();
      var tts = engines[e[1]];
      if (tts == null) {
        for (final k in engines.keys.where((k) => family(k) == family(e[1])).toList()) {
          engines.remove(k)?.free();
        }
        tts = engines[e[1]] = _createEngine(e, threads);
      }
      final sw = Stopwatch()..start();
      final cfg = so.OfflineTtsGenerationConfig(sid: sid, speed: speed, numSteps: int.parse(e[3]));
      var a = tts.generateWithConfig(text: text, config: cfg);
      if (e[0] == 'supertonic' && !text.contains(' ')) {
        // A single word now and then comes out with a stray extra sound; the
        // model varies each run, so one more take is made and the cleaner kept.
        var best = _bursts(a.samples, a.sampleRate);
        for (var k = 0; k < _wordRetakes && best > 1; k++) {
          final b = tts.generateWithConfig(text: text, config: cfg);
          final n = _bursts(b.samples, b.sampleRate);
          if (n < best) {
            best = n;
            a = b;
          }
        }
      }
      final secs = a.sampleRate == 0 ? 0.0 : a.samples.length / a.sampleRate;
      final rtf = secs == 0 ? 0.0 : sw.elapsedMilliseconds / 1000 / secs;
      if (a.samples.isEmpty) throw Exception('no audio');
      // A little silence first: some phones clip or repeat the first
      // milliseconds while the audio output starts ("aand", "gggrow").
      final lead = (a.sampleRate * 0.12).round(), tail = (a.sampleRate * 0.08).round();
      final padded = Float32List(lead + a.samples.length + tail)..setRange(lead, lead + a.samples.length, a.samples);
      so.writeWave(filename: out, samples: padded, sampleRate: a.sampleRate);
      reply.send([id, null, out, rtf, secs]);
    } catch (e) {
      reply.send([id, '$e', null, 0.0, 0.0]);
    }
  });
}

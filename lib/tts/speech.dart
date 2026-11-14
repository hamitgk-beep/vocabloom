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

/// Natural offline speech. The voice models (Kokoro for English, Piper for
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
  }

  PackState stateOf(VoicePack pk) => _state[pk.id] ?? PackState.missing;
  double progressOf(VoicePack pk) => _progress[pk.id] ?? 0;
  String? errorOf(VoicePack pk) => _error[pk.id];
  bool isReady(VoicePack pk) => stateOf(pk) == PackState.ready;

  /// The English voice pack is installed.
  bool get ready => isReady(kokoroPack);

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
        if (m[1] == null) {
          done?.complete(m[2] as String);
        } else {
          done?.completeError(Exception(m[1]));
        }
        _busy = false;
        _pump();
      }
    });
    final threads = max(1, min(4, Platform.numberOfProcessors - 1));
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
    final engine = vo.kokoro ? ['kokoro', vo.engineKey, dir, vo.british ? 'lexicon-gb-en.txt' : 'lexicon-us-en.txt'] : ['vits', vo.engineKey, dir, ''];
    final job = _Job(id, text, vo.sid, speed ?? this.speed, out, engine);
    urgent ? _queue.addFirst(job) : _queue.add(job);
    await _ensureWorker();
    _pump();
    return c.future;
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
  Future<void> playFile(String path) async {
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
      try {
        File(path).deleteSync();
      } catch (_) {}
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
    final path = await synth(text, v: v, urgent: true, speed: speed);
    if (token != _sayToken) {
      try {
        File(path).deleteSync();
      } catch (_) {}
      return;
    }
    await playFile(path);
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
  final model = kind == 'kokoro'
      ? so.OfflineTtsModelConfig(
          kokoro: so.OfflineTtsKokoroModelConfig(
            model: '$dir/model.int8.onnx',
            voices: '$dir/voices.bin',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data',
            lexicon: '$dir/${e[3]}',
          ),
          numThreads: threads,
        )
      : so.OfflineTtsModelConfig(
          vits: so.OfflineTtsVitsModelConfig(
            model: '$dir/model.onnx',
            tokens: '$dir/tokens.txt',
            dataDir: '$dir/espeak-ng-data',
          ),
          numThreads: threads,
        );
  return so.OfflineTts(so.OfflineTtsConfig(model: model));
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
  String family(String key) => key.split('-').first; // 'kokoro' / 'piper'
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
      final a = tts.generate(text: text, sid: sid, speed: speed);
      if (a.samples.isEmpty) throw Exception('no audio');
      so.writeWave(filename: out, samples: a.samples, sampleRate: a.sampleRate);
      reply.send([id, null, out]);
    } catch (e) {
      reply.send([id, '$e', null]);
    }
  });
}

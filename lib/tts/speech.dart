import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import '../data/user_db.dart';
import '../l10n.dart';
import 'ema.dart';
import 'voices.dart';

enum PackState { missing, downloading, extracting, ready, failed }

/// Natural offline speech. The voice models (Kokoro, or the light Piper voice on
/// slow phones, for English; Piper for Turkish) run on the device through
/// sherpa-onnx in a background isolate;
/// audio is played with audioplayers. Each voice pack is downloaded once
/// (Settings > Read aloud) and then works without internet.
class Speech extends ChangeNotifier with WidgetsBindingObserver {
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
    try {
      WidgetsBinding.instance.removeObserver(this);
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    for (final pk in voicePacks) {
      _state[pk.id] = _readyMark(pk).existsSync() ? PackState.ready : PackState.missing;
    }
    _rtf = double.tryParse(user.getSetting('tts_rtf_kokoro') ?? '');
    // Earlier test builds used other English models; free their space.
    for (final old in const ['kokoro-en-v1', 'supertonic-en-v2', 'piper-tr-fettah']) {
      try {
        final d = Directory(p.join(_root.path, 'voice', old));
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    }
    // Keep the cache of spoken words from growing without end.
    try {
      final cache = Directory(p.join(_root.path, 'voice', 'cache'));
      if (cache.existsSync() && cache.listSync().length > 4000) cache.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Called when the app goes to the background (screen locked, another app
  /// opened). Book reading sets it to pause itself; otherwise sound stops.
  VoidCallback? onBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      final f = onBackground;
      f != null ? f() : unawaited(stopPlayback());
    }
  }

  PackState stateOf(VoicePack pk) => _state[pk.id] ?? PackState.missing;
  double progressOf(VoicePack pk) => _progress[pk.id] ?? 0;
  String? errorOf(VoicePack pk) => _error[pk.id];

  /// A download failure in the interface language.
  static String _downloadError(Object e) {
    final m = e is HttpException ? e.message : e is FileSystemException ? e.message : '';
    if (m == 'download interrupted') return L('İndirme yarıda kesildi.', 'The download was interrupted.');
    if (m.startsWith('HTTP ')) return L('Sunucu dosyayı vermedi ($m).', 'The server did not send the file ($m).');
    if (m == 'voice pack is incomplete') return L('Ses paketi eksik indi.', 'The voice pack arrived incomplete.');
    return errorText(e);
  }
  bool isReady(VoicePack pk) => stateOf(pk) == PackState.ready;

  /// An English voice is installed (the light one comes first).
  bool get ready => isReady(kokoroPack) || isReady(lightPack);

  /// Measured speed of the natural voice on this phone: seconds of work per
  /// second of speech (lower is faster).
  double? _rtf;
  double? get naturalSpeed => _rtf;

  /// Seconds of work per second of speech above which the natural voice is
  /// too close to falling behind while reading on this phone, so the light
  /// voice is used (unless chosen otherwise in Settings). Below 1 it keeps up;
  /// 0.8 leaves room for a busy or warm phone.
  static const slowRtf = 0.8;

  void _learnSpeed(double rtf, double secs) {
    if (secs < 1.5 || rtf <= 0) return; // short clips are mostly overhead
    final was = useNatural;
    _rtf = _rtf == null ? rtf : _rtf! * 0.7 + rtf * 0.3;
    _user?.setSetting('tts_rtf_kokoro', _rtf!.toStringAsFixed(3));
    if (useNatural != was) notifyListeners();
  }

  /// 'auto' (by this phone's speed), 'natural' or 'light'.
  String get quality => _user?.getSetting('tts_quality') ?? 'auto';
  set quality(String q) {
    _user?.setSetting('tts_quality', q == 'auto' ? null : q);
    notifyListeners();
  }

  /// The natural voice is the one in use.
  bool get useNatural {
    if (!isReady(kokoroPack)) return false;
    if (!isReady(lightPack)) return true;
    return switch (quality) {
      'natural' => true,
      'light' => false,
      _ => _rtf == null || _rtf! <= slowRtf,
    };
  }

  /// The natural voice was measured too slow for this phone.
  bool get naturalTooSlow => _rtf != null && _rtf! > slowRtf;

  // ---------------------------------------------------------------- settings

  /// Chosen natural English voice.
  Voice get naturalVoice {
    final v = voiceById[_user?.getSetting('tts_voice')];
    return v != null && v.pack == kokoroPack ? v : voices.first;
  }

  /// Chosen light English voice.
  Voice get lightVoice {
    final v = voiceById[_user?.getSetting('tts_voice_light')];
    if (v != null && v.pack == lightPack) return v;
    // Same kind of voice as the natural one.
    return lightVoices.firstWhere((l) => l.female == naturalVoice.female);
  }

  /// The English voice in use.
  Voice get voice => useNatural ? naturalVoice : lightVoice;
  set voice(Voice v) {
    _user?.setSetting(v.pack == lightPack ? 'tts_voice_light' : 'tts_voice', v.id);
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
    _user?.setSetting('tts_removed_${pk.id}', null);
    _cancelled.remove(pk.id);
    _state[pk.id] = PackState.downloading;
    _progress[pk.id] = 0;
    _error.remove(pk.id);
    notifyListeners();
    final voiceDir = Directory(p.join(_root.path, 'voice'));
    final zip = File(p.join(voiceDir.path, '${pk.id}.zip.part'));
    try {
      await voiceDir.create(recursive: true);
      final src = url ?? pk.url;
      final forced = Platform.environment['VOCABLOOM_OS_DOWNLOAD'];
      try {
        if (forced != null) throw const SocketException('forced OS download');
        await _fetchDart(pk, src, zip);
      } catch (e) {
        // Dart's own HTTP client ignores Windows' proxy settings and some
        // antivirus certificates. Windows' own tools use both, so they are
        // tried before giving up.
        if (!Platform.isWindows || _cancelled.remove(pk.id) || !_isNetworkError(e)) rethrow;
        _log('${pk.id}: built-in download failed ($e), trying Windows');
        await _fetchWindows(pk, src, zip, e, only: forced);
      }
      _state[pk.id] = PackState.extracting;
      notifyListeners();
      final dir = packDir(pk);
      if (dir.existsSync()) await dir.delete(recursive: true);
      final zipPath = zip.path, out = voiceDir.path;
      await Isolate.run(() {
        final input = InputFileStream(zipPath);
        try {
          unzipPack(ZipDecoder().decodeStream(input), out);
        } finally {
          input.closeSync();
        }
      });
      await zip.delete();
      final mark = pk.engine == 'ema' ? 'decoder.onnx' : 'tokens.txt';
      if (!File(p.join(dir.path, mark)).existsSync()) throw const FileSystemException('voice pack is incomplete');
      await _readyMark(pk).writeAsString('1');
      _state[pk.id] = PackState.ready;
      unawaited(warmUp());
    } catch (e) {
      _log('${pk.id}: failed: $e');
      final detail = '$e'.replaceAll(RegExp(r'\s+'), ' ');
      _error[pk.id] = '${_downloadError(e)}\n${L('Ayrıntı', 'Details')}: ${detail.length > 300 ? '${detail.substring(0, 300)}…' : detail}';
      _state[pk.id] = PackState.failed;
      try {
        if (zip.existsSync()) zip.deleteSync();
      } catch (_) {}
    } finally {
      notifyListeners();
    }
  }

  final _procs = <String, Process>{};
  final _cancelled = <String>{};

  Future<void> _fetchDart(VoicePack pk, String url, File zip) async {
    final client = _clients[pk.id] = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
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
    } finally {
      _clients.remove(pk.id)?.close();
    }
  }

  static bool _isNetworkError(Object e) =>
      e is SocketException || e is TlsException || e is http.ClientException || e is HandshakeException || e is OSError;

  /// Downloads with curl.exe (Windows 10 and later), then PowerShell, which
  /// follow Windows' own proxy and certificate settings.
  Future<void> _fetchWindows(VoicePack pk, String url, File zip, Object first, {String? only}) async {
    final tries = <(String, List<String>)>[
      if (only == null || only == 'curl')
        ('curl.exe', ['-L', '-f', '-sS', '--retry', '2', '--ssl-revoke-best-effort', '-o', p.basename(zip.path), url]),
      if (only == null || only == 'powershell')
        ('powershell.exe', [
          '-NoProfile', '-NonInteractive', '-Command',
          "\$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; "
              "[Net.WebRequest]::DefaultWebProxy.Credentials=[Net.CredentialCache]::DefaultCredentials; "
              r"Invoke-WebRequest -UseBasicParsing -Uri $env:VOCABLOOM_URL -OutFile $env:VOCABLOOM_OUT",
        ]),
    ];
    final errors = ['$first'];
    for (final (exe, args) in tries) {
      try {
        if (zip.existsSync()) zip.deleteSync();
        // Paths such as C:\Users\Hamit Gök can get mangled on a command
        // line, so curl writes into its working folder by a plain name and
        // PowerShell reads the path from the environment.
        final proc = _procs[pk.id] = await Process.start(exe, args,
            workingDirectory: zip.parent.path, environment: {'VOCABLOOM_URL': url, 'VOCABLOOM_OUT': zip.path});
        final err = StringBuffer();
        proc.stderr.transform(const SystemEncoding().decoder).listen(err.write);
        proc.stdout.drain<void>();
        final timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
          try {
            final got = zip.existsSync() ? zip.lengthSync() : 0;
            _progress[pk.id] = min(0.99, got / (pk.mb * 1024 * 1024));
            notifyListeners();
          } catch (_) {}
        });
        final code = await proc.exitCode;
        timer.cancel();
        _procs.remove(pk.id);
        if (_cancelled.remove(pk.id)) throw const HttpException('download interrupted');
        if (code == 0 && zip.existsSync() && zip.lengthSync() > 1024 * 1024) {
          _log('${pk.id}: downloaded with $exe');
          return;
        }
        errors.add('$exe: exit $code ${err.toString().trim()}');
      } on HttpException {
        rethrow;
      } catch (e) {
        errors.add('$exe: $e');
      }
    }
    throw SocketException(errors.join(' | '));
  }

  /// Appends a line to voice/log.txt, kept small, to find out later why a
  /// download failed on someone's computer.
  void _log(String line) {
    debugPrint(line);
    try {
      final f = File(p.join(_root.path, 'voice', 'log.txt'));
      if (f.existsSync() && f.lengthSync() > 200000) f.deleteSync();
      f.writeAsStringSync('${DateTime.now().toIso8601String()} $line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// Downloads both English packs, the small light one first so speech
  /// works within seconds while the natural voice arrives.
  Future<void> downloadEnglish({String Function(VoicePack)? url}) async {
    for (final pk in englishPacks) {
      await download(pk, url: url?.call(pk));
      if (!isReady(pk)) return;
    }
  }

  /// Downloads every voice pack that is not on the phone yet, one after the
  /// other, so all voices come with the app without asking. The light English
  /// voice and the Turkish voices come first because they are small. A pack
  /// the user deleted is left alone; a failed one is tried again next start.
  Future<void> downloadAll({String Function(VoicePack)? url}) async {
    for (final pk in [lightPack, emaPack, fahrettinPack, kokoroPack]) {
      if (_user?.getSetting('tts_removed_${pk.id}') == '1') continue;
      await download(pk, url: url?.call(pk));
    }
  }

  void cancelDownload(VoicePack pk) {
    final c = _clients[pk.id], pr = _procs[pk.id];
    if (c == null && pr == null) return;
    _cancelled.add(pk.id);
    c?.close();
    pr?.kill();
  }

  Future<void> deletePack(VoicePack pk) async {
    _user?.setSetting('tts_removed_${pk.id}', '1');
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
  final _naturalJobs = <int>{};
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
        final natural = _naturalJobs.remove(m[0] as int);
        if (m[1] == null) {
          if (natural) _learnSpeed(m[3] as double, m[4] as double);
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
  Future<String> synth(String text, {Voice? v, bool urgent = false, double? speed, String? tag}) async {
    final vo = v ?? voice;
    if (!isReady(vo.pack)) throw StateError('voice pack ${vo.pack.id} not downloaded');
    final id = _nextId++;
    final out = p.join(Directory.systemTemp.path, 'vocabloom_tts_${pid}_$id.wav');
    final c = Completer<String>();
    _waiting[id] = c;
    final dir = packDir(vo.pack).path;
    // Kokoro reads US or UK English with the matching pronunciation list.
    final engine = [vo.engine, vo.engine == 'kokoro' ? '${vo.pack.id}@${vo.accent}' : vo.pack.id, dir, vo.accent, vo.family];
    if (vo.pack == kokoroPack) _naturalJobs.add(id);
    final job = _Job(id, _forSpeech(text), vo.sid, speed ?? this.speed, out, engine, tag);
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

  /// Moves a queued job (by [tag]) to the front: someone is waiting for it now.
  void _promote(String tag) {
    final j = _queue.where((j) => j.tag == tag).firstOrNull;
    if (j == null) return;
    _queue.remove(j);
    _queue.addFirst(j);
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
    // Some phones report the previous clip's end late, just after the next
    // one starts, which used to cut a sentence short. An end is believed only
    // near the clip's real length; a timer covers a lost end event.
    final secs = _wavSeconds(path);
    final sw = Stopwatch()..start();
    Timer? safety;
    _doneSub = player.onPlayerComplete.listen((_) {
      if (secs > 0 && sw.elapsedMilliseconds < secs * 1000 * 0.6 - 300) return;
      if (!c.isCompleted) c.complete();
    });
    try {
      await player.play(DeviceFileSource(path));
      if (secs > 0) {
        void arm() {
          safety?.cancel();
          safety = Timer(Duration(milliseconds: (secs * 1000).round() + 1500), () {
            // Still playing (e.g. paused for a while)? Check again later.
            if (player.state == PlayerState.paused) {
              arm();
            } else if (!c.isCompleted) {
              c.complete();
            }
          });
        }

        arm();
      }
      await c.future;
    } finally {
      safety?.cancel();
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

  static double _wavSeconds(String path) {
    try {
      final n = File(path).lengthSync() - 44;
      final f = File(path).openSync();
      final h = f.readSync(44);
      f.closeSync();
      final rate = ByteData.sublistView(h).getUint32(24, Endian.little);
      return rate > 0 && n > 0 ? n / 2 / rate : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _finishCurrent() async {
    final c = _playing;
    if (c != null && !c.isCompleted) c.complete();
    await _doneSub?.cancel();
    _doneSub = null;
  }

  /// Position in the clip that is playing.
  Stream<Duration> get position => player.onPositionChanged;

  Future<void> pause() => player.pause();
  Future<void> resume() => player.resume();

  Future<void> stop() async {
    clearQueue();
    await stopPlayback();
  }

  /// Stops what is playing now (and a word or sample still being made will
  /// not start), but keeps the audio being prepared in the background.
  Future<void> stopPlayback() async {
    _sayToken++;
    if (_player != null) await _player!.stop();
    await _finishCurrent();
  }

  int _sayToken = 0;

  /// Called before a word is said, so book reading can step aside.
  VoidCallback? onSay;

  /// Says a word or short text right away (interrupting what is playing).
  Future<void> say(String text, {Voice? v, double? speed}) async {
    onSay?.call();
    // The previous word or sample stops at once.
    await stopPlayback();
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
    final making = _making[f.path];
    if (making != null) {
      if (urgent) _promote(f.path);
      return making;
    }
    return _making[f.path] = () async {
      try {
        final tmp = await synth(text, v: v, urgent: urgent, speed: speed, tag: f.path);
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
    }();
  }

  /// Makes the audio of [text] ahead of time (e.g. when a word's panel opens),
  /// so the speaker button answers at once.
  void prefetch(String text, {String lang = 'en', Voice? voice}) {
    final v = voice ?? voiceFor(lang);
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
    // The natural voice first: a full sentence also measures this phone's
    // speed, which decides between the natural and the light voice.
    final order = [if (isReady(kokoroPack)) naturalVoice, if (isReady(lightPack)) lightVoice, if (isReady(trVoice.pack)) trVoice];
    for (final v in order) {
      try {
        _deleteQuietly(await synth(v.lang == 'en' ? 'Reading a little every day is the fastest way to learn new words.' : 'Merhaba.', v: v));
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
  final String? tag;
  _Job(this.id, this.text, this.sid, this.speed, this.out, this.engine, this.tag);
}

/// A loaded voice model in the worker: text in, samples out.
abstract class _Engine {
  (Float32List, int) generate(String text, int sid, double speed);
  void free();
}

class _SherpaEngine implements _Engine {
  final so.OfflineTts tts;
  _SherpaEngine(this.tts);
  @override
  (Float32List, int) generate(String text, int sid, double speed) {
    final a = tts.generateWithConfig(text: text, config: so.OfflineTtsGenerationConfig(sid: sid, speed: speed));
    return (a.samples, a.sampleRate);
  }

  @override
  void free() => tts.free();
}

class _EmaEngine implements _Engine {
  final EmaVoice v;
  _EmaEngine(this.v);
  @override
  (Float32List, int) generate(String text, int sid, double speed) {
    // EMA was trained on pieces that end a sentence.
    final t = text.trim();
    final ended = RegExp(r'''[.!?]["')]*$''').hasMatch(t) ? t : '${t.replaceAll(RegExp(r'[,;:\- ]+$'), '')}.';
    // A word on its own comes out hurried (the model learnt from sentences);
    // a little slower it is clearer, which also suits a learner.
    final sp = t.contains(' ') ? speed : speed * 0.85;
    return (v.generate(ended, speed: sp, seed: 7), v.sampleRate);
  }

  @override
  void free() => v.close();
}

_Engine _createEngine(List<String> e, int threads) {
  final kind = e[0], dir = e[2], accent = e[3];
  if (kind == 'ema') {
    return _EmaEngine(EmaVoice.load(dir, threads: threads, libDir: Platform.environment['SHERPA_ONNX_LIB_DIR']));
  }
  final model = switch (kind) {
    'kokoro' => so.OfflineTtsModelConfig(
        kokoro: so.OfflineTtsKokoroModelConfig(
          model: '$dir/model.onnx',
          voices: '$dir/voices.bin',
          tokens: '$dir/tokens.txt',
          dataDir: '$dir/espeak-ng-data',
          lexicon: accent == 'gb' ? '$dir/lexicon-gb-en.txt' : '$dir/lexicon-us-en.txt',
          lang: accent == 'gb' ? 'en' : 'en-us', // espeak's 'en' is British
        ),
        numThreads: threads,
        debug: false,
      ),
    _ => so.OfflineTtsModelConfig(
        vits: so.OfflineTtsVitsModelConfig(
          model: '$dir/model.onnx',
          tokens: '$dir/tokens.txt',
          dataDir: '$dir/espeak-ng-data',
          // Less sampling noise on the light English voice: in tests it cut
          // the words Whisper misheard from 4% to about 1%.
          noiseScale: accent == 'tr' ? 0.667 : 0.2,
          noiseScaleW: accent == 'tr' ? 0.8 : 0.3,
        ),
        numThreads: threads,
        debug: false,
      ),
  };
  return _SherpaEngine(so.OfflineTts(so.OfflineTtsConfig(model: model)));
}

/// Background isolate: keeps up to one model of each kind loaded and writes
/// one WAV file per request.
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
  final engines = <String, _Engine>{};
  final familyOf = <String, String>{}; // engine key -> 'en-natural' / 'en-light' / 'tr'
  inbox.listen((m) {
    final l = m as List;
    final id = l[0] as int;
    try {
      if (initError != null) throw Exception('speech engine unavailable: $initError');
      final text = l[1] as String, sid = l[2] as int, speed = l[3] as double, out = l[4] as String;
      final e = (l[5] as List).cast<String>();
      var tts = engines[e[1]];
      if (tts == null) {
        // One model per family stays loaded (e.g. switching Turkish voices).
        for (final k in engines.keys.where((k) => familyOf[k] == e[4]).toList()) {
          engines.remove(k)?.free();
        }
        tts = engines[e[1]] = _createEngine(e, threads);
        familyOf[e[1]] = e[4];
      }
      final sw = Stopwatch()..start();
      final (samples, sampleRate) = tts.generate(text, sid, speed);
      final secs = sampleRate == 0 ? 0.0 : samples.length / sampleRate;
      final rtf = secs == 0 ? 0.0 : sw.elapsedMilliseconds / 1000 / secs;
      if (samples.isEmpty) throw Exception('no audio');
      // Silence first: many phones (and Bluetooth headphones) swallow the
      // first moments of sound while the audio output wakes up.
      final word = !text.contains(' ');
      final lead = (sampleRate * (word ? 0.25 : 0.15)).round(), tail = (sampleRate * 0.1).round();
      final padded = Float32List(lead + samples.length + tail)..setRange(lead, lead + samples.length, samples);
      so.writeWave(filename: out, samples: padded, sampleRate: sampleRate);
      reply.send([id, null, out, rtf, secs]);
    } catch (e) {
      reply.send([id, '$e', null, 0.0, 0.0]);
    }
  });
}

/// Writes the files of a voice pack zip under [out]. Done by hand because
/// the archive package's own extractor wrote nothing on Windows (its checks
/// for paths leaving the folder refused every entry there).
void unzipPack(Archive archive, String out) {
  for (final f in archive) {
    final parts = f.name.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty && s != '.').toList();
    if (parts.isEmpty) continue;
    if (f.name.startsWith('/') || parts.any((s) => s == '..' || s.contains(':'))) {
      throw FileSystemException('bad entry in voice pack', f.name);
    }
    final target = p.joinAll([out, ...parts]);
    if (!f.isFile) {
      Directory(target).createSync(recursive: true);
      continue;
    }
    if (f.isSymbolicLink) continue;
    File(target).parent.createSync(recursive: true);
    final o = OutputFileStream(target);
    try {
      f.writeContent(o);
    } finally {
      o.closeSync();
    }
  }
}

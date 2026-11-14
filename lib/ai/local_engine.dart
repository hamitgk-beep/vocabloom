import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;

import '../data/user_db.dart';
import 'local_ai.dart';
import 'packages.dart';

/// [LocalAi] on llama.cpp (through llamadart). Models are GGUF files kept in
/// `<app data>/ai_models/`.
class LlamaLocalAi extends LocalAi {
  final UserDb db;
  final Directory dir;
  LlamaLocalAi(this.db, Directory appDir) : dir = Directory(p.join(appDir.path, 'ai_models'));

  static const _premiumDefine = bool.fromEnvironment('AI_PREMIUM');

  @override
  List<AiPackage> get packages => aiPackages;

  AiPackage _pkg(String id) =>
      aiPackages.firstWhere((x) => x.id == id, orElse: () => throw ArgumentError('unknown AI package $id'));

  File _file(String id) => File(p.join(dir.path, '$id.gguf'));
  File _part(String id) => File(p.join(dir.path, '$id.gguf.part'));

  /// Download addresses: a saved override first, then the built-in ones.
  List<String> _urls(AiPackage pk) => [?db.getSetting('ai_url_${pk.id}'), ...pk.urls];

  @override
  bool get premiumUnlocked => _premiumDefine || db.getSetting('ai_premium') == '1';

  @override
  Future<Set<String>> installed() async {
    final out = <String>{};
    for (final pk in aiPackages) {
      if (await _file(pk.id).exists()) out.add(pk.id);
    }
    return out;
  }

  // ---------------------------------------------------------------- download

  final Map<String, AiDownload> _downloads = {};
  final Map<String, HttpClient> _clients = {};
  final Set<String> _cancelled = {};

  @override
  Map<String, AiDownload> get downloads => Map.unmodifiable(_downloads);

  @override
  Stream<AiDownload> download(String id) {
    final pk = _pkg(id);
    if (pk.premium && !premiumUnlocked) {
      return Stream.error(const AiException(
          'Bu paket ücretli abonelere açıktır.', 'This package is available to paid subscribers.'));
    }
    final ctl = StreamController<AiDownload>();
    _cancelled.remove(id);
    () async {
      try {
        await for (final d in _run(pk)) {
          _downloads[id] = d;
          notifyListeners();
          ctl.add(d);
        }
      } catch (e, st) {
        if (!_cancelled.contains(id)) ctl.addError(e, st);
      } finally {
        _downloads.remove(id);
        _clients.remove(id)?.close(force: true);
        notifyListeners();
        await ctl.close();
      }
    }();
    return ctl.stream;
  }

  Stream<AiDownload> _run(AiPackage pk) async* {
    await dir.create(recursive: true);
    final dest = _file(pk.id);
    if (await dest.exists()) {
      final n = await dest.length();
      yield AiDownload(pk.id, n, n, done: true);
      return;
    }
    final part = _part(pk.id);
    Object? lastError;
    for (final url in _urls(pk)) {
      try {
        yield* _fetch(pk, url, part);
        if (_cancelled.contains(pk.id)) return;
        if (pk.sha256 != null) {
          final sum = (await sha256.bind(part.openRead()).first).toString();
          if (sum != pk.sha256) {
            await part.delete();
            throw const AiException('İndirilen dosya doğrulanamadı, lütfen yeniden deneyin.',
                'The downloaded file could not be verified, please try again.');
          }
        }
        await part.rename(dest.path);
        final n = await dest.length();
        activeId ?? await setActive(pk.id);
        yield AiDownload(pk.id, n, n, done: true);
        return;
      } on AiException {
        rethrow;
      } catch (e) {
        if (_cancelled.contains(pk.id)) return;
        lastError = e;
      }
    }
    throw AiException('İndirme tamamlanamadı. İnternet bağlantınızı kontrol edip yeniden deneyin. ($lastError)',
        'The download could not be completed. Check your internet connection and try again. ($lastError)');
  }

  /// Downloads [url] into [part], resuming from what is already there.
  Stream<AiDownload> _fetch(AiPackage pk, String url, File part) async* {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _clients[pk.id] = client;
    var have = await part.exists() ? await part.length() : 0;
    final req = await client.getUrl(Uri.parse(url));
    if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    final res = await req.close();
    if (res.statusCode == 416) {
      // Already complete.
      yield AiDownload(pk.id, have, have);
      return;
    }
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
    }
    if (res.statusCode == 200) have = 0; // server ignored the range: start over
    final total = res.contentLength < 0 ? 0 : have + res.contentLength;
    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    var got = have;
    var lastEmit = DateTime.now();
    try {
      yield AiDownload(pk.id, got, total);
      await for (final chunk in res) {
        if (_cancelled.contains(pk.id)) break;
        sink.add(chunk);
        got += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastEmit).inMilliseconds > 250) {
          lastEmit = now;
          yield AiDownload(pk.id, got, total);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    if (_cancelled.contains(pk.id)) return;
    if (total > 0 && got < total) {
      throw const HttpException('connection closed early');
    }
    yield AiDownload(pk.id, got, total);
  }

  @override
  Future<void> cancel(String id) async {
    _cancelled.add(id);
    _clients.remove(id)?.close(force: true);
    _downloads.remove(id);
    notifyListeners();
  }

  @override
  Future<void> delete(String id) async {
    await cancel(id);
    if (_loadedId == id) await unload();
    for (final f in [_file(id), _part(id)]) {
      if (await f.exists()) await f.delete();
    }
    if (activeId == id) {
      final left = await installed();
      db.setSetting('ai_local_active', left.isEmpty ? null : left.first);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ active model

  @override
  String? get activeId => db.getSetting('ai_local_active');

  @override
  Future<void> setActive(String id) async {
    _pkg(id);
    if (activeId == id) return;
    db.setSetting('ai_local_active', id);
    if (_loadedId != null && _loadedId != id) await unload();
    notifyListeners();
  }

  @override
  Future<int?> deviceRamMb() => readDeviceRamMb();

  // -------------------------------------------------------------- inference

  LlamaEngine? _engine;
  String? _loadedId;
  Future<LlamaEngine>? _loading;

  @override
  bool get loaded => _engine != null;

  Future<LlamaEngine> _ensure() async {
    final id = activeId;
    if (id == null || !await _file(id).exists()) {
      throw const AiException('Önce Yapay Zekâ bölümünden bir paket indirin.',
          'First download a package in the AI section.');
    }
    final pk = _pkg(id);
    if (pk.premium && !premiumUnlocked) {
      throw const AiException('Bu paket ücretli abonelere açıktır.', 'This package is available to paid subscribers.');
    }
    if (_engine != null && _loadedId == id) return _engine!;
    if (_loading != null) return _loading!;
    _loading = () async {
      await unload();
      final threads = (Platform.numberOfProcessors - 2).clamp(2, 6);
      final e = await LlamaEngine.load(
        LlamaModel(ModelSource.path(_file(id).path)),
        params: ModelParams(
          contextSize: pk.contextSize,
          // Android GPU support in llama.cpp is still experimental: CPU there.
          device: Platform.isAndroid ? ComputeDevice.cpu : ComputeDevice.auto,
          numberOfThreads: threads,
          numberOfThreadsBatch: threads,
        ),
      );
      _engine = e;
      _loadedId = id;
      notifyListeners();
      return e;
    }();
    try {
      return await _loading!;
    } finally {
      _loading = null;
    }
  }

  @override
  Stream<String> generate(String system, List<(String, String)> messages,
      {int maxTokens = 512, double temperature = 0.3}) async* {
    final e = await _ensure();
    final pk = _pkg(_loadedId!);
    final msgs = [
      LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
      for (final (role, text) in messages)
        LlamaChatMessage.fromText(role: role == 'assistant' ? LlamaChatRole.assistant : LlamaChatRole.user, text: text),
    ];
    final stream = e.create(
      msgs,
      enableThinking: false,
      params: GenerationParams(
        maxTokens: maxTokens,
        temp: temperature,
        topK: 20,
        topP: 0.8,
        minP: 0.0,
        penalty: 1.05,
        // Qwen3 recommends a presence penalty against repetition in small models.
        presencePenalty: pk.hybridThinking ? 1.0 : 0.5,
      ),
    );
    final f = ThinkFilter();
    await for (final t in stream.textDeltas()) {
      final s = f.add(t);
      if (s.isNotEmpty) yield s;
    }
    final rest = f.close();
    if (rest.isNotEmpty) yield rest;
  }

  @override
  void stop() => _engine?.cancelGeneration();

  @override
  Future<void> unload() async {
    final e = _engine;
    _engine = null;
    _loadedId = null;
    if (e != null) {
      e.cancelGeneration();
      await e.dispose();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final c in _clients.values) {
      c.close(force: true);
    }
    _engine?.dispose();
    super.dispose();
  }
}

/// Total device memory in MB, or null when it cannot be read.
Future<int?> readDeviceRamMb() async {
  try {
    if (Platform.isAndroid || Platform.isLinux) {
      final line = (await File('/proc/meminfo').readAsLines()).firstWhere((l) => l.startsWith('MemTotal:'));
      final kb = int.parse(RegExp(r'\d+').firstMatch(line)!.group(0)!);
      return kb ~/ 1024;
    }
    if (Platform.isMacOS) {
      final r = await Process.run('sysctl', ['-n', 'hw.memsize']);
      return int.parse((r.stdout as String).trim()) ~/ (1024 * 1024);
    }
    if (Platform.isWindows) {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory',
      ]);
      return int.parse((r.stdout as String).trim()) ~/ (1024 * 1024);
    }
  } catch (_) {}
  return null;
}

/// Removes `<think>…</think>` blocks from streamed text, also when a tag is
/// split across pieces.
class ThinkFilter {
  static const _open = '<think>', _close = '</think>';
  String _buf = '';
  bool _thinking = false;

  String add(String piece) {
    _buf += piece;
    final out = StringBuffer();
    while (true) {
      final tag = _thinking ? _close : _open;
      final i = _buf.indexOf(tag);
      if (i >= 0) {
        if (!_thinking) out.write(_buf.substring(0, i));
        _buf = _buf.substring(i + tag.length);
        _thinking = !_thinking;
        if (!_thinking) _buf = _buf.replaceFirst(RegExp(r'^\s+'), '');
        continue;
      }
      // Keep a possible beginning of the tag for the next piece.
      var keep = 0;
      for (var k = tag.length - 1; k > 0; k--) {
        if (_buf.endsWith(tag.substring(0, k))) {
          keep = k;
          break;
        }
      }
      if (!_thinking) out.write(_buf.substring(0, _buf.length - keep));
      _buf = _buf.substring(_buf.length - keep);
      return out.toString();
    }
  }

  String close() {
    final s = _thinking ? '' : _buf;
    _buf = '';
    return s;
  }
}

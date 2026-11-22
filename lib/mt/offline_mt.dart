/// Offline sentence translation on Windows (where Google ML Kit does not
/// run), with the OPUS-MT English -> Turkish model. Off until the learner
/// turns it on in Settings and downloads the model there: nothing is bundled
/// with the app and nothing is downloaded by itself.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../ai/local_ai.dart' show formatBytes;
import '../data/user_db.dart';
import '../l10n.dart';
import 'opus_mt.dart';

/// One file of the model.
class MtFile {
  final String path;
  final int size;
  final String sha256;
  const MtFile(this.path, this.size, this.sha256);
}

/// The model: where it comes from, what it weighs and its license.
class MtModelSpec {
  final String id, repo, revision;
  final List<MtFile> files;
  final String license, licenseUrl, attribution;
  const MtModelSpec({
    required this.id,
    required this.repo,
    required this.revision,
    required this.files,
    required this.license,
    required this.licenseUrl,
    required this.attribution,
  });

  int get totalBytes => files.fold(0, (s, f) => s + f.size);

  /// The engine and model version in saved answers: a newer model never
  /// reuses an older one's translations.
  String get engine => '$id@${revision.substring(0, 7)}';

  Uri url(MtFile f) => Uri.parse('https://huggingface.co/$repo/resolve/$revision/${f.path}');
  String get pageUrl => 'https://huggingface.co/$repo';
}

/// `onnx-community/opus-mt-tc-big-en-tr`, the ONNX export of
/// `Helsinki-NLP/opus-mt-tc-big-en-tr` (CC-BY 4.0), pinned to one revision;
/// every file is checked against its SHA-256 after the download.
const opusEnTr = MtModelSpec(
  id: 'opus-mt-tc-big-en-tr',
  repo: 'onnx-community/opus-mt-tc-big-en-tr',
  revision: 'ce128ea834a090aca240e4e113e7756e06cc78e0',
  files: [
    MtFile('config.json', 1099, 'f377425d2cd0b78df07c120c621f1924d3215c46ff4d6e100707054d0a526f8c'),
    MtFile('vocab.json', 1501287, '01ef522455d2bf22b0716416ee34688cc2b3f5fa257f742665d21b6acc450ac1'),
    MtFile('source.spm', 796953, '180d3f94ddfee5585d78b702290ded0f4f9bd40f299349c8383b32a579fefad4'),
    MtFile('onnx/encoder_model_int8.onnx', 135730164, '58bfc076347346049a52a8d53b1f6e4664af74e9737aded374d7d1f78805f46e'),
    MtFile('onnx/decoder_model_int8.onnx', 395310868, '44264bac42bc67e6ef5a9f37b9ef364e1b93277026399ca6d90eb5752ee5164b'),
  ],
  license: 'CC-BY 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
  attribution: 'OPUS-MT, Helsinki-NLP (Tiedemann et al.), opus-mt-tc-big-en-tr',
);

enum OfflineMtStatus { notInstalled, downloading, ready, failed }

class OfflineMtState {
  final OfflineMtStatus status;
  final int received, total;
  final String? errorTr, errorEn;
  const OfflineMtState(this.status, {this.received = 0, this.total = 0, this.errorTr, this.errorEn});
  String? get error => errorTr == null ? null : L(errorTr!, errorEn!);
  double? get fraction => total <= 0 ? null : (received / total).clamp(0.0, 1.0);
}

class MtDownloadError implements Exception {
  final String tr, en;
  const MtDownloadError(this.tr, this.en);
  @override
  String toString() => en;
}

/// Opens [url] for reading: its length (if known) and its bytes.
typedef MtFetch = Future<(int?, Stream<List<int>>)> Function(Uri url);

/// Translates one text with the loaded model.
typedef MtEngine = Future<String?> Function(String text);

class OfflineMt extends ChangeNotifier {
  OfflineMt._(this.spec);
  static final instance = OfflineMt._(opusEnTr);

  /// Tests: a manager for a small stand-in model.
  @visibleForTesting
  factory OfflineMt.test(MtModelSpec spec) => OfflineMt._(spec);

  final MtModelSpec spec;

  /// Tests: pretend to be on Windows (or not).
  static bool? debugSupported;

  /// Windows only: phones and tablets have Google ML Kit.
  static bool get platformSupported => debugSupported ?? (!kIsWeb && Platform.isWindows);

  static const dir = 'en>tr';
  static const _enabledKey = 'offline_mt';
  static const _marker = 'installed.json';

  Directory? _root;
  bool _installed = false;
  OfflineMtState state = const OfflineMtState(OfflineMtStatus.notInstalled);

  /// Where the model goes: `<data folder>/mt/<model>-<revision>`.
  void init(Directory dataDir) {
    _root = Directory('${dataDir.path}${Platform.pathSeparator}mt');
    _installed = _checkInstalled();
    _set(OfflineMtState(_installed ? OfflineMtStatus.ready : OfflineMtStatus.notInstalled));
  }

  String? get modelDir => _root == null ? null : '${_root!.path}${Platform.pathSeparator}${spec.id}-${spec.revision.substring(0, 7)}';

  File _file(String rel) => File('$modelDir${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}');

  bool _checkInstalled() {
    if (modelDir == null) return false;
    try {
      final m = _file(_marker);
      if (!m.existsSync()) return false;
      final j = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
      if (j['revision'] != spec.revision) return false;
      return spec.files.every((f) {
        final x = _file(f.path);
        return x.existsSync() && x.lengthSync() == f.size;
      });
    } catch (_) {
      return false;
    }
  }

  bool get installed => _installed;

  /// Tests: pretend the model is (not) on disk.
  @visibleForTesting
  set debugInstalled(bool v) {
    _installed = v;
    notifyListeners();
  }
  bool enabled(UserDb user) => user.getSetting(_enabledKey) == '1';

  /// Whether panels translate with it now.
  bool active(UserDb user) => platformSupported && _installed && enabled(user);

  void _set(OfflineMtState s) {
    state = s;
    notifyListeners();
  }

  /// Turns the feature on or off (the model stays on disk until removed).
  void setEnabled(UserDb user, bool on) {
    user.setSetting(_enabledKey, on ? '1' : '0');
    if (!on) _closeEngine();
    notifyListeners();
  }

  // ------------------------------------------------------------ download

  /// Room kept free beside the model.
  static const diskMargin = 100 * 1000 * 1000;

  /// Free bytes on the disk of [path]; null when unknown. Tests replace it.
  int? Function(String path) freeSpace = diskFree;

  /// Free bytes for this user on the disk holding [path] (Windows), or null.
  static int? diskFree(String path) {
    if (kIsWeb || !Platform.isWindows) return null;
    try {
      final k = DynamicLibrary.open('kernel32.dll');
      final f = k.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
          int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)>('GetDiskFreeSpaceExW');
      final p = path.toNativeUtf16();
      final out = calloc<Uint64>();
      try {
        return f(p, out, nullptr, nullptr) != 0 ? out.value : null;
      } finally {
        calloc.free(p);
        calloc.free(out);
      }
    } catch (_) {
      return null;
    }
  }

  bool _cancelled = false;
  StreamSubscription<List<int>>? _sub;
  Completer<void>? _cancelSignal;

  /// Downloads the model (only after the learner agreed in Settings). Every
  /// file is written beside its place first and moved there only once its
  /// size and SHA-256 match. Returns true when the model is ready.
  Future<bool> download({MtFetch? fetch}) async {
    if (state.status == OfflineMtStatus.downloading || modelDir == null) return false;
    fetch ??= _httpFetch;
    _cancelled = false;
    final total = spec.totalBytes;
    var done = 0;
    // Enough room first: what is still missing plus a margin, so the disk is
    // never filled up by the download.
    final missing = spec.files.fold(0, (s, f) {
      final x = _file(f.path);
      return s + (x.existsSync() && x.lengthSync() == f.size ? 0 : f.size);
    });
    final need = missing + diskMargin;
    final free = missing == 0 ? null : freeSpace(_root!.parent.path);
    if (free != null && free < need) {
      _set(OfflineMtState(OfflineMtStatus.failed,
          errorTr: 'Diskte yeterli yer yok: ${formatBytes(need)} gerekiyor, ${formatBytes(free)} boş. Biraz yer açıp tekrar dene; hiçbir şey indirilmedi.',
          errorEn: 'Not enough disk space: ${formatBytes(need)} needed, ${formatBytes(free)} free. Free some space and try again; nothing was downloaded.'));
      return false;
    }
    _set(OfflineMtState(OfflineMtStatus.downloading, total: total));
    try {
      await Directory(modelDir!).create(recursive: true);
      for (final f in spec.files) {
        final target = _file(f.path);
        if (target.existsSync() && target.lengthSync() == f.size) {
          done += f.size;
          continue;
        }
        var shown = 0;
        await _fetchOne(fetch, f, target, (n) {
          // About every 0.25 %, so the screen is not rebuilt for each piece.
          if (n - shown < total ~/ 400 && n != f.size) return;
          shown = n;
          _set(OfflineMtState(OfflineMtStatus.downloading, received: done + n, total: total));
        });
        done += f.size;
      }
      await _file(_marker).writeAsString(jsonEncode({'revision': spec.revision, 'engine': spec.engine, 'at': DateTime.now().toIso8601String()}));
      _installed = true;
      _set(const OfflineMtState(OfflineMtStatus.ready));
      return true;
    } on _Cancelled {
      _set(const OfflineMtState(OfflineMtStatus.notInstalled));
      return false;
    } on MtDownloadError catch (e) {
      _set(OfflineMtState(OfflineMtStatus.failed, errorTr: e.tr, errorEn: e.en));
      return false;
    } on SocketException {
      _set(const OfflineMtState(OfflineMtStatus.failed,
          errorTr: 'İnternete bağlanılamadı. Bağlantını kontrol edip tekrar dene.', errorEn: 'Could not connect. Check your connection and try again.'));
      return false;
    } on FileSystemException catch (e) {
      _set(OfflineMtState(OfflineMtStatus.failed,
          errorTr: 'Dosya yazılamadı (diskte yer kalmamış olabilir): ${e.message}', errorEn: 'Could not write the file (the disk may be full): ${e.message}'));
      return false;
    } catch (e) {
      _set(OfflineMtState(OfflineMtStatus.failed, errorTr: 'İndirme tamamlanamadı: $e', errorEn: 'The download did not finish: $e'));
      return false;
    } finally {
      _sub = null;
      _cancelSignal = null;
    }
  }

  Future<void> _fetchOne(MtFetch fetch, MtFile f, File target, void Function(int) progress) async {
    final part = File('${target.path}.part');
    await part.parent.create(recursive: true);
    if (part.existsSync()) part.deleteSync();
    if (_cancelled) throw _Cancelled();
    final (length, stream) = await fetch(spec.url(f));
    if (_cancelled) throw _Cancelled();
    if (length != null && length >= 0 && length != f.size) {
      throw MtDownloadError('Sunucudaki dosyanın boyutu beklenenden farklı (${f.path}).', 'The file on the server has an unexpected size (${f.path}).');
    }
    final out = part.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var got = 0;
    final finished = Completer<void>();
    _cancelSignal = Completer<void>();
    _sub = stream.listen(
      (chunk) {
        got += chunk.length;
        if (got > f.size) {
          _sub?.cancel();
          if (!finished.isCompleted) {
            finished.completeError(MtDownloadError('İndirilen dosya beklenenden büyük (${f.path}).', 'The downloaded file is larger than expected (${f.path}).'));
          }
          return;
        }
        hasher.add(chunk);
        out.add(chunk);
        progress(got);
      },
      onError: (Object e) {
        if (!finished.isCompleted) finished.completeError(e);
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );
    try {
      await Future.any([finished.future, _cancelSignal!.future]);
      if (_cancelled) throw _Cancelled();
    } catch (_) {
      // Cancelled or failed: no half file is left behind.
      unawaited(_sub?.cancel());
      await out.close();
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
    // Not awaited: a stream stuck on a dead connection must not hold us.
    unawaited(_sub?.cancel());
    await out.close();
    hasher.close();
    if (got != f.size) {
      part.deleteSync();
      throw MtDownloadError('Dosya eksik indi (${f.path}). Tekrar dene.', 'The file arrived incomplete (${f.path}). Try again.');
    }
    if (digest.value.toString() != f.sha256) {
      part.deleteSync();
      throw MtDownloadError('İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor: ${f.path}). Dosya kullanılmadı.',
          'The downloaded file failed its check (SHA-256 mismatch: ${f.path}). It was not used.');
    }
    if (target.existsSync()) target.deleteSync();
    part.renameSync(target.path);
  }

  /// Stops a running download; the unfinished file is deleted, finished and
  /// checked files are kept for the next try.
  void cancel() {
    if (state.status != OfflineMtStatus.downloading) return;
    _cancelled = true;
    _sub?.cancel();
    if (_cancelSignal?.isCompleted == false) _cancelSignal!.complete();
  }

  /// Deletes the model files and turns the feature off. Saved translations
  /// stay (they name their model version).
  Future<void> remove(UserDb user) async {
    cancel();
    _closeEngine();
    setEnabled(user, false);
    final d = modelDir;
    if (d != null && Directory(d).existsSync()) await Directory(d).delete(recursive: true);
    _installed = false;
    _set(const OfflineMtState(OfflineMtStatus.notInstalled));
  }

  static Future<(int?, Stream<List<int>>)> _httpFetch(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final req = await client.getUrl(url);
    final res = await req.close();
    if (res.statusCode != 200) {
      await res.drain<void>();
      client.close(force: true);
      throw MtDownloadError('Sunucu dosyayı vermedi (HTTP ${res.statusCode}).', 'The server did not send the file (HTTP ${res.statusCode}).');
    }
    final len = res.contentLength;
    final controller = StreamController<List<int>>();
    late StreamSubscription<List<int>> s;
    controller.onListen = () {
      s = res.timeout(const Duration(seconds: 60)).listen(controller.add, onError: controller.addError, onDone: () {
        controller.close();
        client.close();
      });
    };
    controller.onCancel = () async {
      await s.cancel();
      client.close(force: true);
    };
    return (len >= 0 ? len : null, controller.stream);
  }

  // ------------------------------------------------------------ translate

  /// Tests: a stand-in for the model.
  MtEngine? debugEngine;
  Future<OpusMtWorker>? _worker;
  OpusMtWorker? _live;

  void _closeEngine() {
    _live?.close();
    _live = null;
    _worker = null;
  }

  Future<String?> _run(String text) async {
    if (debugEngine != null) return debugEngine!(text);
    _worker ??= OpusMtWorker.start(modelDir!, threads: (Platform.numberOfProcessors ~/ 2).clamp(1, 4), libDir: Platform.environment['SHERPA_ONNX_LIB_DIR'])
        .then((w) => _live = w);
    try {
      return await (await _worker!).translate(text);
    } catch (_) {
      _closeEngine();
      rethrow;
    }
  }

  /// Turkish of [text] when the feature is on, or null (the panel then shows
  /// no Turkish line). Answers are saved with the source text, direction and
  /// model version, so a sentence is translated once.
  Future<String?> translate(UserDb user, String text) async {
    text = text.trim();
    if (text.isEmpty || !active(user)) return null;
    final saved = user.mtCached(spec.engine, dir, text);
    if (saved != null && saved.isNotEmpty) return saved;
    try {
      final r = (await _run(text).timeout(const Duration(seconds: 60)))?.trim();
      if (r == null || r.isEmpty || r.toLowerCase() == text.toLowerCase()) return null;
      // A runaway answer (repeating itself) is not shown.
      if (r.length > text.length * 4 + 40) return null;
      user.setMtCached(spec.engine, dir, text, r);
      return r;
    } catch (_) {
      return null;
    }
  }
}

class _Cancelled implements Exception {}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

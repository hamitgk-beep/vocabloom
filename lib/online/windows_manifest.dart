import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'native_fetch.dart';

/// File-by-file Windows updates. The release carries a manifest
/// (tools/release/windows_manifest.py) with each program file's SHA-256 and
/// one gzip blob per file, named `<sha256>.gz`. The app hashes its own
/// files, downloads only the changed or new ones into a temporary folder,
/// checks each one's SHA-256 and hands the folder to the install script
/// (windows_updater.dart), which swaps the files once the app has closed.
///
/// Only files under the app folder are ever touched. Books, words, settings
/// and voice packs live in the user's AppData folder and are not listed.
class ManifestFile {
  /// Relative path with "/" separators, e.g. "data/app.so".
  final String path;
  final int size;
  final String sha256;

  /// Size of the gzip blob to download.
  final int gz;
  const ManifestFile(this.path, this.size, this.sha256, this.gz);

  String get blob => '$sha256.gz';
}

class WindowsManifest {
  /// The copy every install keeps next to Storilex.exe.
  static const fileName = 'storilex-manifest.json';

  /// Name of the release asset.
  static const assetName = 'Storilex-Windows-manifest.json';

  final int build;
  final String version;
  final List<ManifestFile> files;

  /// The manifest text as published, installed as [fileName].
  final String text;
  const WindowsManifest(this.build, this.version, this.files, this.text);

  /// Throws [FormatException] for anything unexpected, so a damaged or
  /// unknown manifest falls back to the full zip.
  static WindowsManifest parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map || j['schema'] != 1 || j['files'] is! List) throw const FormatException('unknown manifest');
    final seen = <String>{};
    final files = <ManifestFile>[];
    for (final f in j['files'] as List) {
      if (f is! Map) throw const FormatException('bad manifest entry');
      final path = f['path'], size = f['size'], sha = f['sha256'], gz = f['gz'];
      if (path is! String || size is! int || sha is! String || gz is! int) throw const FormatException('bad manifest entry');
      if (!isSafePath(path)) throw FormatException('unsafe path in manifest', path);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) || size < 0 || gz < 0) throw FormatException('bad hash or size', path);
      if (!seen.add(path.toLowerCase())) throw FormatException('path listed twice', path);
      files.add(ManifestFile(path, size, sha, gz));
    }
    if (!seen.contains('storilex.exe')) throw const FormatException('Storilex.exe is not in the manifest');
    return WindowsManifest((j['build'] as num?)?.toInt() ?? 0, '${j['version'] ?? ''}', files, text);
  }

  /// A relative path inside the app folder that the install script can
  /// handle: plain ASCII letters, digits and ". _ - /" only (cmd reads its
  /// file lists in the console code page), no "..", no drive or root, and
  /// never the manifest itself.
  static bool isSafePath(String path) {
    if (path.isEmpty || path.length > 200) return false;
    if (!RegExp(r'^[A-Za-z0-9._\-/]+$').hasMatch(path)) return false;
    final parts = path.split('/');
    if (parts.any((s) => s.isEmpty || s == '.' || s == '..')) return false;
    return path.toLowerCase() != fileName;
  }
}

class UpdatePlan {
  final WindowsManifest manifest;

  /// Files to download: changed or new.
  final List<ManifestFile> download;

  /// Files the installed version had (by its manifest) that the new one
  /// does not. Only these are deleted; unknown files are left alone.
  final List<String> remove;
  const UpdatePlan(this.manifest, this.download, this.remove);

  /// Bytes to download.
  int get bytes => download.fold(0, (s, f) => s + f.gz);
}

/// Compares the files in [appDir] with [next]. A file counts as unchanged
/// only when its size and SHA-256 match, so a damaged file is replaced too.
/// Runs off the UI thread.
Future<UpdatePlan> planUpdate(WindowsManifest next, Directory appDir) async {
  final dir = appDir.path;
  final entries = [for (final f in next.files) (f.path, f.size, f.sha256)];
  final (changed, removed) = await Isolate.run(() {
    final changed = <String>[];
    for (final (path, size, sha) in entries) {
      final f = File(p.joinAll([dir, ...path.split('/')]));
      if (!f.existsSync() || f.lengthSync() != size || _sha256File(f) != sha) changed.add(path);
    }
    // Files to remove come from the installed manifest only.
    final removed = <String>[];
    try {
      final old = WindowsManifest.parse(File(p.join(dir, WindowsManifest.fileName)).readAsStringSync());
      final keep = {for (final e in entries) e.$1.toLowerCase()};
      for (final f in old.files) {
        if (!keep.contains(f.path.toLowerCase()) && File(p.joinAll([dir, ...f.path.split('/')])).existsSync()) removed.add(f.path);
      }
    } catch (_) {
      // No manifest yet (installed from a full zip before this system):
      // nothing is deleted, as nothing is known to be ours.
    }
    return (changed, removed);
  });
  final byPath = {for (final f in next.files) f.path: f};
  return UpdatePlan(next, [for (final c in changed) byPath[c]!], removed);
}

String _sha256File(File f) {
  final out = _DigestSink();
  final input = sha256.startChunkedConversion(out);
  final raf = f.openSync();
  try {
    final buf = List<int>.filled(1 << 20, 0);
    while (true) {
      final n = raf.readIntoSync(buf);
      if (n <= 0) break;
      input.add(buf.sublist(0, n));
    }
  } finally {
    raf.closeSync();
  }
  input.close();
  return out.value.toString();
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Downloads the plan's files from [baseUrl] ("…/releases/download/latest/")
/// into [stage], laid out as in the app folder, and checks every file's
/// size and SHA-256. Writes the new manifest into [stage] too. Throws on any
/// mismatch, leaving the installed app untouched. [onProgress] gets 0..1.
Future<void> downloadPlan(UpdatePlan plan, String baseUrl, Directory stage, void Function(double) onProgress) async {
  await stage.create(recursive: true);
  final total = plan.bytes == 0 ? 1 : plan.bytes;
  var done = 0;
  for (final f in plan.download) {
    final target = File(p.joinAll([stage.path, ...f.path.split('/')]));
    await target.parent.create(recursive: true);
    final gz = File('${target.path}.gz');
    final before = done;
    await fetchFile('$baseUrl${f.blob}', gz, onProgress: (v) => onProgress(((before + (v ?? 0) * f.gz) / total).clamp(0.0, 1.0)), expectedSize: f.gz);
    final gzPath = gz.path, outPath = target.path;
    final sha = await Isolate.run(() async {
      await File(gzPath).openRead().transform(gzip.decoder).pipe(File(outPath).openWrite());
      File(gzPath).deleteSync();
      return _sha256File(File(outPath));
    });
    if (target.lengthSync() != f.size || sha != f.sha256) {
      throw FileSystemException('checksum mismatch', f.path);
    }
    done += f.gz;
    onProgress(done / total);
  }
  await File(p.join(stage.path, WindowsManifest.fileName)).writeAsString(plan.manifest.text);
}

/// The list files for the install script, with "\" separators: every path
/// the update writes or deletes (backed up first, restored on failure), and
/// the paths to delete after a good copy.
({List<String> touched, List<String> remove}) installLists(UpdatePlan plan) {
  String win(String s) => s.replaceAll('/', r'\');
  return (
    touched: [for (final f in plan.download) win(f.path), WindowsManifest.fileName, for (final r in plan.remove) win(r)],
    remove: [for (final r in plan.remove) win(r)],
  );
}

/// The same lists for a folder unpacked from the full zip.
/// Throws when a path is one the script could not handle.
List<String> listFolder(Directory stage) {
  final out = <String>[];
  for (final e in stage.listSync(recursive: true)) {
    if (e is! File) continue;
    final rel = p.split(p.relative(e.path, from: stage.path)).join('/');
    if (!WindowsManifest.isSafePath(rel) && rel.toLowerCase() != WindowsManifest.fileName) throw FileSystemException('unexpected file in the update', rel);
    out.add(rel.replaceAll('/', r'\'));
  }
  return out;
}

/// The manifest of the release, or null when it has none (older releases).
Future<WindowsManifest?> fetchManifest(String url) async {
  try {
    return WindowsManifest.parse(await fetchText(url, timeout: const Duration(seconds: 20)));
  } catch (_) {
    return null;
  }
}

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Updates the Windows app in place: downloads the release zip, unpacks it
/// next to the app, then a small script waits for the app to close, copies
/// the new files over the old ones and starts VocaBloom again.
/// Books and words live in the user's AppData folder, so they are kept.
class WindowsUpdater {
  /// Downloads and unpacks [url]. [onProgress] gets 0..1 (or null when the
  /// size is unknown). Returns the folder that holds the new files.
  static Future<Directory> prepare(String url, void Function(double? p) onProgress) async {
    final tmp = await Directory.systemTemp.createTemp('vocabloom_update_');
    final zipFile = File(p.join(tmp.path, 'update.zip'));
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = zipFile.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        onProgress(total == null || total == 0 ? null : got / total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    final out = Directory(p.join(tmp.path, 'new'));
    await extractFileToDisk(zipFile.path, out.path);
    if (!File(p.join(out.path, 'VocaBloom.exe')).existsSync()) {
      throw const FileSystemException('VocaBloom.exe is missing from the update');
    }
    return out;
  }

  /// Starts the copy script and closes the app.
  static Future<void> installAndRestart(Directory newFiles) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final exe = p.join(appDir, p.basename(Platform.resolvedExecutable));
    final script = File(p.join(newFiles.parent.path, 'install.cmd'));
    await script.writeAsString([
      '@echo off',
      'chcp 65001 >nul',
      // Wait until this process has exited so its files can be replaced.
      ':wait',
      'tasklist /FI "PID eq $pid" | find "$pid" >nul && (timeout /t 1 /nobreak >nul & goto wait)',
      'robocopy "${newFiles.path}" "$appDir" /E /R:5 /W:1 /NFL /NDL /NJH /NJS >nul',
      'start "" "$exe"',
      'rmdir /S /Q "${newFiles.parent.path}" >nul 2>&1',
    ].join('\r\n'));
    await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached, runInShell: false);
    exit(0);
  }
}

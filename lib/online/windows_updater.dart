import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../tts/speech.dart' show unzipPack;
import 'native_fetch.dart';

/// Updates the Windows app in place: downloads the release zip, unpacks it
/// next to the app, then a small script waits for the app to close, copies
/// the new files over the old ones and starts VocaBloom again.
/// Books and words live in the user's AppData folder, so they are kept.
class WindowsUpdater {
  /// Downloads and unpacks [url]. [onProgress] gets 0..1 (or null when the
  /// size is unknown). Returns the folder that holds the new files.
  static Future<Directory> prepare(String url, void Function(double? p) onProgress, {int? expectedSize}) async {
    final tmp = await Directory.systemTemp.createTemp('vocabloom_update_');
    final zipFile = File(p.join(tmp.path, 'update.zip'));
    await fetchFile(url, zipFile, onProgress: onProgress, expectedSize: expectedSize);
    final out = Directory(p.join(tmp.path, 'new'));
    final zipPath = zipFile.path, outPath = out.path;
    // The archive package's own extractor writes nothing on Windows (see
    // unzipPack), so the files are written by hand, off the UI thread.
    await Isolate.run(() {
      final input = InputFileStream(zipPath);
      try {
        unzipPack(ZipDecoder().decodeStream(input), outPath);
      } finally {
        input.closeSync();
      }
    });
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
    await script.writeAsString(installScript(newFiles: newFiles.path, appDir: appDir, exe: exe, pid: pid, cleanup: newFiles.parent.path));
    await Process.start('cmd', ['/c', script.path], mode: ProcessStartMode.detached, runInShell: false);
    exit(0);
  }

  /// The batch file that waits for process [pid] to end, copies [newFiles]
  /// over [appDir], starts [exe] and removes [cleanup].
  static String installScript({required String newFiles, required String appDir, required String exe, required int pid, required String cleanup}) => [
        '@echo off',
        'chcp 65001 >nul',
        // Wait until the app has exited so its files can be replaced. ping is
        // the wait because timeout.exe refuses to run without a console.
        ':wait',
        'tasklist /FI "PID eq $pid" /NH | find " $pid " >nul && (ping -n 2 127.0.0.1 >nul & goto wait)',
        'robocopy "$newFiles" "$appDir" /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP >nul',
        'start "" "$exe"',
        'rmdir /S /Q "$cleanup" >nul 2>&1',
        '',
      ].join('\r\n');
}

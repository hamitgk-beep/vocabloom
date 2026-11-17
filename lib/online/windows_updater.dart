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

  /// Where the install script writes "ok" or "fail ..." for the next start.
  static String get resultPath => p.join(Directory.systemTemp.path, 'vocabloom-update-result.txt');

  /// Starts the copy script and closes the app.
  static Future<void> installAndRestart(Directory newFiles) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final exe = p.join(appDir, p.basename(Platform.resolvedExecutable));
    final script = File(p.join(newFiles.parent.path, 'install.cmd'));
    await script.writeAsString(installScript(pid));
    try {
      File(resultPath).deleteSync();
    } catch (_) {}
    await launchScript(script.path, installEnv(newFiles: newFiles.path, appDir: appDir, exe: exe, cleanup: newFiles.parent.path, result: resultPath));
    // Ends the process at once. A normal exit can hang while native audio
    // and ONNX threads shut down, and then the app's DLLs stay locked.
    Process.killPid(pid, ProcessSignal.sigkill);
    exit(0);
  }

  /// Runs [script] detached from the app, so it outlives it. (A hidden
  /// console through wscript was tried: there the script stopped right
  /// after robocopy on the Windows test runner.)
  static Future<void> launchScript(String script, Map<String, String> env) async {
    await Process.start('cmd', ['/c', script], mode: ProcessStartMode.detached, environment: env);
  }

  /// Paths go to the script as environment variables, which keep every
  /// character: written into the batch file, a folder like "Hamit Gök" was
  /// read in the console code page and the files went to a wrong folder.
  static Map<String, String> installEnv({
    required String newFiles,
    required String appDir,
    required String exe,
    required String cleanup,
    required String result,
    String? appName,
    String? log,
    int killAfter = 10,
    int giveUpAfter = 40,
  }) => {
    'VB_NEW': newFiles,
    'VB_APP': appDir,
    'VB_EXE': exe,
    'VB_NAME': appName ?? p.basename(exe),
    'VB_LOG': log ?? p.join(Directory.systemTemp.path, 'vocabloom-update.log'),
    'VB_CLEAN': cleanup,
    'VB_RESULT': result,
    'VB_KILL': '$killAfter',
    'VB_GIVEUP': '$giveUpAfter',
  };

  /// The batch file (ASCII only). It waits until no .exe or .dll in %VB_APP%
  /// is in use (a running program's files cannot be opened for writing),
  /// after %VB_KILL% seconds ends process [pid] and any %VB_NAME% still
  /// running, and copies %VB_NEW% over %VB_APP% only once every file is
  /// free, so the app is never left half old, half new. It then writes the
  /// outcome to %VB_RESULT% and starts %VB_EXE% (the new or, after a
  /// failure, the untouched old app).
  static String installScript(int pid) => [
    '@echo off',
    'setlocal',
    'set LOG="%VB_LOG%"',
    '> %LOG% echo %DATE% %TIME% waiting for $pid',
    'set /a T=0',
    ':wait',
    'set BUSY=',
    'for %%F in ("%VB_APP%\\*.exe" "%VB_APP%\\*.dll") do ( (call ) 2>nul >>"%%~F" || set BUSY=%%~nxF)',
    'if not defined BUSY goto free',
    'set /a T+=1',
    'set /a M=T %% 5',
    'if %M%==0 >> %LOG% echo %TIME% in use: %BUSY%',
    'if %T%==%VB_KILL% (',
    '  >> %LOG% echo %TIME% still in use: %BUSY%, ending the old app',
    '  taskkill /F /PID $pid >> %LOG% 2>&1',
    '  taskkill /F /IM "%VB_NAME%" >> %LOG% 2>&1',
    ')',
    'if %T% GEQ %VB_GIVEUP% goto locked',
    'ping -n 2 127.0.0.1 >nul',
    'goto wait',
    ':locked',
    '>> %LOG% echo %TIME% gave up, still in use: %BUSY%',
    '> "%VB_RESULT%" echo fail locked %BUSY%',
    'goto start',
    ':free',
    '>> %LOG% echo %TIME% copying',
    'robocopy "%VB_NEW%" "%VB_APP%" /E /IS /IT /R:5 /W:1 /NDL /NJH /NP < nul >> %LOG% 2>&1',
    'set RC=%ERRORLEVEL%',
    // Redirect first: "robocopy 3>> log" would redirect handle 3, and
    // the script hung there whenever robocopy returned 1..9.
    '>> %LOG% echo %TIME% robocopy %RC%',
    'if %RC% GEQ 8 (',
    '  > "%VB_RESULT%" echo fail copy %RC%',
    ') else (',
    '  > "%VB_RESULT%" echo ok',
    '  rmdir /S /Q "%VB_CLEAN%" >nul 2>&1',
    ')',
    ':start',
    'start "" "%VB_EXE%"',
    '',
  ].join('\r\n');

  /// The outcome of the last update, read once at start-up: null when
  /// there was none or it worked, otherwise the reason it failed.
  static String? takeFailedResult() {
    final f = File(resultPath);
    try {
      if (!f.existsSync()) return null;
      final t = f.readAsStringSync().trim();
      f.deleteSync();
      return t.startsWith('fail') ? t : null;
    } catch (_) {
      return null;
    }
  }
}

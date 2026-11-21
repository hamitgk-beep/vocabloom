import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../tts/speech.dart' show unzipPack;
import 'native_fetch.dart';
import 'windows_manifest.dart';

/// Updates the Windows app in place. With a manifest in the release only
/// the changed files are downloaded (windows_manifest.dart); otherwise the
/// release zip is downloaded and unpacked. Either way the new files wait in
/// a temporary folder, and a small script, running on its own after the app
/// has closed, backs up every file it will replace, copies the new files in,
/// starts Storilex and, if the copy fails or the new version closes before
/// it has started, puts the backed-up files back and starts the old version.
/// Books and words live in the user's AppData folder, so they are kept.
class WindowsUpdater {
  /// The app's program file. Before the rename it was [legacyExeName]; an
  /// update from such a version brings both, and the next update (or the
  /// start-up clean-up) leaves only this one.
  static const exeName = 'Storilex.exe';
  static const legacyExeName = 'VocaBloom.exe';

  /// Downloads and unpacks the full zip [url]. [onProgress] gets 0..1 (or
  /// null when the size is unknown). Returns the folder that holds the new
  /// files.
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
    await zipFile.delete();
    if (!File(p.join(out.path, exeName)).existsSync()) {
      throw const FileSystemException('$exeName is missing from the update');
    }
    final files = listFolder(out);
    await writeLists(tmp, files, const []);
    return out;
  }

  /// Downloads only the files of [plan] from [baseUrl] and checks their
  /// SHA-256. Returns the folder that holds them.
  static Future<Directory> prepareFiles(UpdatePlan plan, String baseUrl, void Function(double p) onProgress) async {
    final tmp = await Directory.systemTemp.createTemp('vocabloom_update_');
    final out = Directory(p.join(tmp.path, 'new'));
    try {
      await downloadPlan(plan, baseUrl, out, onProgress);
    } catch (_) {
      tmp.delete(recursive: true).ignore();
      rethrow;
    }
    final lists = installLists(plan);
    await writeLists(tmp, lists.touched, lists.remove);
    return out;
  }

  /// The script's file lists, next to the new files' folder: every path the
  /// update writes or deletes, and the paths to delete.
  static Future<void> writeLists(Directory work, List<String> touched, List<String> remove) async {
    await File(p.join(work.path, 'touched.txt')).writeAsString(touched.map((s) => '$s\r\n').join(), encoding: ascii);
    await File(p.join(work.path, 'remove.txt')).writeAsString(remove.map((s) => '$s\r\n').join(), encoding: ascii);
  }

  /// Where the install script writes "ok" or "fail ..." for the next start.
  static String get resultPath => p.join(Directory.systemTemp.path, 'vocabloom-update-result.txt');

  /// Starts the copy script and closes the app. [newFiles] comes from
  /// [prepare] or [prepareFiles].
  static Future<void> installAndRestart(Directory newFiles) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final running = p.basename(Platform.resolvedExecutable);
    // The new files always start as Storilex.exe, even when this is still
    // the VocaBloom.exe copy an update from before the rename left behind.
    final exe = p.join(appDir, exeName);
    final work = newFiles.parent.path;
    final script = File(p.join(work, 'install.cmd'));
    await script.writeAsString(installScript(pid));
    try {
      File(resultPath).deleteSync();
    } catch (_) {}
    await launchScript(
      script.path,
      installEnv(
        newFiles: newFiles.path,
        appDir: appDir,
        exe: exe,
        appName: running,
        cleanup: work,
        result: resultPath,
        remove: p.join(appDir, legacyExeName),
      ),
    );
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
  /// The file lists ([prepare], [prepareFiles]) sit next to [newFiles], and
  /// the backup goes there too. [waitStart] is how many seconds the script
  /// waits for the new version to report that it started (0: not at all).
  static Map<String, String> installEnv({
    required String newFiles,
    required String appDir,
    required String exe,
    required String cleanup,
    required String result,
    String? appName,
    String? remove,
    String? log,
    int killAfter = 10,
    int giveUpAfter = 40,
    int waitStart = 120,
  }) {
    final work = p.dirname(newFiles);
    return {
      'VB_NEW': newFiles,
      'VB_APP': appDir,
      'VB_EXE': exe,
      'VB_NAME': appName ?? p.basename(exe),
      'VB_LOG': log ?? p.join(Directory.systemTemp.path, 'vocabloom-update.log'),
      'VB_CLEAN': cleanup,
      'VB_RESULT': result,
      'VB_KILL': '$killAfter',
      'VB_GIVEUP': '$giveUpAfter',
      'VB_LIST': p.join(work, 'touched.txt'),
      'VB_DELS': p.join(work, 'remove.txt'),
      'VB_BAK': p.join(work, 'backup'),
      'VB_HEALTH': p.join(work, 'started.txt'),
      'VB_WAITSTART': '$waitStart',
      if (remove != null) 'VB_REMOVE': remove,
    };
  }

  /// The batch file (ASCII only). It waits until no .exe or .dll in %VB_APP%
  /// is in use (a running program's files cannot be opened for writing),
  /// after %VB_KILL% seconds ends process [pid] and any %VB_NAME% still
  /// running, and changes nothing until every file is free. Then it copies
  /// each file listed in %VB_LIST% to %VB_BAK%, copies %VB_NEW% over
  /// %VB_APP%, deletes the files in %VB_DELS% and starts %VB_EXE%. The new
  /// version writes "ok" into %VB_HEALTH% once it is up ([confirmStarted]).
  /// If copying fails, or the new version closes without that, the listed
  /// files are deleted and the backup is copied back, so the old version
  /// is whole again, and it is started. The outcome goes to %VB_RESULT%;
  /// after a good update the work folder (with this script) is deleted.
  static String installScript(int pid) => [
    '@echo off',
    'setlocal',
    'set LOG="%VB_LOG%"',
    'for %%E in ("%VB_EXE%") do set EXENAME=%%~nxE',
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
    'start "" "%VB_EXE%"',
    'exit /b 0',
    ':free',
    // 1) Back up every file the update will overwrite or delete.
    '>> %LOG% echo %TIME% backing up',
    'if exist "%VB_BAK%" rmdir /S /Q "%VB_BAK%"',
    'mkdir "%VB_BAK%" 2>nul',
    'set BAKFAIL=',
    'for /f "usebackq delims=" %%F in ("%VB_LIST%") do if exist "%VB_APP%\\%%F" (',
    '  for %%P in ("%VB_BAK%\\%%F") do if not exist "%%~dpP" mkdir "%%~dpP"',
    '  copy /Y "%VB_APP%\\%%F" "%VB_BAK%\\%%F" >nul 2>&1 || set BAKFAIL=%%F',
    ')',
    'if not defined BAKFAIL goto copy',
    // Nothing was changed yet: the old app is started as it is.
    '>> %LOG% echo %TIME% backup failed: %BAKFAIL%',
    '> "%VB_RESULT%" echo fail backup %BAKFAIL%',
    'start "" "%VB_EXE%"',
    'exit /b 0',
    // 2) Copy the new files in and delete the ones the new version dropped.
    ':copy',
    '>> %LOG% echo %TIME% copying',
    'robocopy "%VB_NEW%" "%VB_APP%" /E /IS /IT /R:5 /W:1 /NDL /NJH /NP < nul >> %LOG% 2>&1',
    'set RC=%ERRORLEVEL%',
    // Redirect first: "robocopy 3>> log" would redirect handle 3, and
    // the script hung there whenever robocopy returned 1..9.
    '>> %LOG% echo %TIME% robocopy %RC%',
    'set WHY=copy %RC%',
    'if %RC% GEQ 8 goto rollback',
    'for /f "usebackq delims=" %%F in ("%VB_DELS%") do if exist "%VB_APP%\\%%F" del /F /Q "%VB_APP%\\%%F" >> %LOG% 2>&1',
    // 3) Start the new version and wait until it says it is up.
    '>> %LOG% echo %TIME% starting the new version',
    '> "%VB_HEALTH%" echo wait',
    'start "" "%VB_EXE%"',
    'if "%VB_WAITSTART%"=="0" goto good',
    'set /a S=0',
    ':health',
    'ping -n 2 127.0.0.1 >nul',
    // cmd's own commands only: findstr and tasklist did not get through to
    // the end on the test runner (findstr may read a path like "İndirilen"
    // in the ANSI code page).
    'set H=',
    'if exist "%VB_HEALTH%" set /p H=<"%VB_HEALTH%"',
    'if "%H%"=="ok" goto good',
    'set /a S+=1',
    'set /a M=S %% 5',
    'if %M%==0 >> %LOG% echo %TIME% waiting for the new version to start (%S% s)',
    'if %S% GEQ %VB_WAITSTART% goto good',
    'if %S% LSS 5 goto health',
    // A running program's file cannot be opened for writing: while it is
    // locked, the new version is still starting.
    '(call ) 2>nul >>"%VB_EXE%" || goto health',
    'set WHY=start',
    '>> %LOG% echo %TIME% the new version closed before it started',
    'goto rollback',
    ':good',
    '>> %LOG% echo %TIME% ok',
    '> "%VB_RESULT%" echo ok',
    // The old program file from before the rename, once the update worked.
    'if defined VB_REMOVE if exist "%VB_REMOVE%" del /F /Q "%VB_REMOVE%" >> %LOG% 2>&1',
    // This script lives in %VB_CLEAN%. cmd reads a batch file line by line,
    // so deleting it earlier stopped the script before the app was started.
    // "(goto)" leaves the batch file first; rmdir then runs on this line.
    '(goto) 2>nul & rmdir /S /Q "%VB_CLEAN%" >nul 2>&1',
    // 4) Put the old version back: remove every listed file, then copy the
    // backed-up ones in again. Files the update added go; deleted ones return.
    ':rollback',
    '>> %LOG% echo %TIME% rolling back (%WHY%)',
    'if "%WHY%"=="start" taskkill /F /IM "%EXENAME%" >> %LOG% 2>&1',
    'if "%WHY%"=="start" ping -n 3 127.0.0.1 >nul',
    'for /f "usebackq delims=" %%F in ("%VB_LIST%") do if exist "%VB_APP%\\%%F" del /F /Q "%VB_APP%\\%%F" >> %LOG% 2>&1',
    'robocopy "%VB_BAK%" "%VB_APP%" /E /IS /IT /R:5 /W:1 /NDL /NJH /NP < nul >> %LOG% 2>&1',
    'set RC=%ERRORLEVEL%',
    '>> %LOG% echo %TIME% restore robocopy %RC%',
    'if %RC% GEQ 8 (> "%VB_RESULT%" echo fail %WHY%, restore failed %RC%) else (> "%VB_RESULT%" echo fail %WHY%, old version restored)',
    'start "" "%VB_EXE%"',
    'exit /b 0',
    '',
  ].join('\r\n');

  /// Called once the app is up. When the install script started this
  /// version it waits for this "ok"; without it in time it puts the old
  /// version back. Does nothing when the app was started normally.
  static void confirmStarted() {
    final path = Platform.environment['VB_HEALTH'];
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync() && f.readAsStringSync().trim() == 'wait') f.writeAsStringSync('ok');
    } catch (_) {}
  }

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

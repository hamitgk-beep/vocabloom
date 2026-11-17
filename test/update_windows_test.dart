@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/online/native_fetch.dart';
import 'package:kelime_okur/online/windows_updater.dart';
import 'package:path/path.dart' as p;

// Runs on a real Windows machine (CI: update-windows.yml). The Dart HTTP
// client is switched off, as it fails on some users' PCs, so the Windows
// fallbacks (curl.exe, PowerShell) do the work.
const _release = 'https://api.github.com/repos/hamitgk-beep/vocabloom/releases/tags/latest';
const _zip = 'https://github.com/hamitgk-beep/vocabloom/releases/download/latest/VocaBloom-Windows.zip';

void main() {
  tearDown(() {
    debugSkipDartHttp = false;
    debugSkipCurl = false;
  });

  test('release notes read through curl.exe', () async {
    debugSkipDartHttp = true;
    final t = await fetchText(_release, headers: {'Accept': 'application/vnd.github+json'});
    expect(t, contains('Build'));
  });

  test('release notes read through PowerShell', () async {
    debugSkipDartHttp = true;
    debugSkipCurl = true;
    final t = await fetchText(_release, headers: {'Accept': 'application/vnd.github+json'});
    expect(t, contains('Build'));
  });

  test('curl and PowerShell write into a folder with Turkish letters', () async {
    debugSkipDartHttp = true;
    final dir = Directory.systemTemp.createTempSync('vb_')..createSync();
    final gok = Directory(p.join(dir.path, 'Hamit Gök şğü'))..createSync();
    final f = File(p.join(gok.path, 'release.json'));
    await fetchFile(_release, f);
    expect(f.readAsStringSync(), contains('Build'));
    debugSkipCurl = true;
    f.deleteSync();
    await fetchFile(_release, f);
    expect(f.readAsStringSync(), contains('Build'));
    dir.deleteSync(recursive: true);
  });

  test('update zip downloads with progress and unpacks with VocaBloom.exe', () async {
    debugSkipDartHttp = true;
    final seen = <double?>[];
    final dir = await WindowsUpdater.prepare(_zip, seen.add, expectedSize: 40 * 1024 * 1024);
    expect(File(p.join(dir.path, 'VocaBloom.exe')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'flutter_windows.dll')).existsSync(), isTrue);
    expect(seen.last, 1);
    dir.parent.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 10)));

  // A fake installed app: VocaBloom.exe is a copy of ping.exe, so while it
  // runs Windows keeps the file locked, like the real app's exe and DLLs.
  Future<({Directory root, Directory app, Directory work, Directory fresh, String marker, String exe, File result})> setUp_() async {
    final root = Directory.systemTemp.createTempSync('vb_install');
    final app = Directory(p.join(root.path, 'Kitaplar Gök'))..createSync();
    File(p.join(Platform.environment['SystemRoot']!, 'System32', 'PING.EXE')).copySync(p.join(app.path, 'VocaBloom.exe'));
    File(p.join(app.path, 'old.txt')).writeAsStringSync('old');
    File(p.join(app.path, 'keep.txt')).writeAsStringSync('keep');
    final work = Directory(p.join(root.path, 'İndirilen ğüş'))..createSync();
    final fresh = Directory(p.join(work.path, 'new'))..createSync();
    Directory(p.join(fresh.path, 'data')).createSync();
    File(p.join(fresh.path, 'old.txt')).writeAsStringSync('new');
    File(p.join(fresh.path, 'VocaBloom.exe')).writeAsStringSync('new exe');
    File(p.join(fresh.path, 'data', 'x.bin')).writeAsStringSync('x');
    final marker = p.join(root.path, 'started.txt');
    final exe = p.join(app.path, 'run.cmd');
    final run = '@echo started> "$marker"\r\n@exit\r\n';
    File(exe).writeAsStringSync(run);
    File(p.join(fresh.path, 'run.cmd')).writeAsStringSync(run);
    return (root: root, app: app, work: work, fresh: fresh, marker: marker, exe: exe, result: File(p.join(root.path, 'result.txt')));
  }

  Future<String> runInstall(dynamic t, int appPid, {int killAfter = 10, int giveUpAfter = 40, bool hidden = true}) async {
    final script = File(p.join(t.work.path, 'install.cmd'))..writeAsStringSync(WindowsUpdater.installScript(appPid));
    await WindowsUpdater.launchScript(
      script.path,
      WindowsUpdater.installEnv(
        newFiles: t.fresh.path,
        appDir: t.app.path,
        exe: t.exe,
        cleanup: t.work.path,
        result: t.result.path,
        appName: 'VocaBloom.exe',
        log: p.join(t.root.path, 'update.log'),
        killAfter: killAfter,
        giveUpAfter: giveUpAfter,
      ),
    );
    for (var i = 0; i < 160 && !File(t.marker).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final log = File(p.join(t.root.path, 'update.log'));
    var text = log.existsSync() ? log.readAsStringSync() : '-';
    if (!File(t.marker).existsSync()) {
      final ps = await Process.run('tasklist', ['/v', '/fo', 'list']);
      text +=
          '\n--- processes ---\n${'${ps.stdout}'.split(RegExp(r'\r?\n\r?\n')).where((b) => RegExp(r'cmd|robocopy|wscript|conhost|ping|VocaBloom|helper', caseSensitive: false).hasMatch(b)).join('\n\n')}';
    }
    return text;
  }

  test('install waits until the app has let go of its files, copies them and restarts', () async {
    final t = await setUp_();
    final app = await Process.start(p.join(t.app.path, 'VocaBloom.exe'), ['-n', '4', '127.0.0.1']);
    final sw = Stopwatch()..start();
    final log = await runInstall(t, app.pid);
    expect(File(t.marker).existsSync(), isTrue, reason: 'app was not started again. Log: $log');
    expect(sw.elapsed.inMilliseconds, greaterThan(2000), reason: 'did not wait for the app to exit. Log: $log');
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(p.join(t.app.path, 'VocaBloom.exe')).readAsStringSync(), 'new exe', reason: log);
    expect(File(p.join(t.app.path, 'old.txt')).readAsStringSync(), 'new', reason: log);
    expect(File(p.join(t.app.path, 'keep.txt')).readAsStringSync(), 'keep');
    expect(File(p.join(t.app.path, 'data', 'x.bin')).existsSync(), isTrue);
    expect(t.work.existsSync(), isFalse);
    await app.exitCode;
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('install ends an app that does not close and then updates it', () async {
    final t = await setUp_();
    // Hangs for 10 minutes; the pid given to the script is another process,
    // so only the "end any VocaBloom.exe" step can free the files.
    final hung = await Process.start(p.join(t.app.path, 'VocaBloom.exe'), ['-n', '600', '127.0.0.1']);
    final other = await Process.start('cmd', ['/c', 'exit']);
    await other.exitCode;
    final log = await runInstall(t, other.pid, killAfter: 3, giveUpAfter: 20, hidden: false);
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(p.join(t.app.path, 'VocaBloom.exe')).readAsStringSync(), 'new exe', reason: log);
    expect(await hung.exitCode.timeout(const Duration(seconds: 5)), isNot(0));
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('install copies nothing while a file stays locked and reports it', () async {
    final t = await setUp_();
    // Not named VocaBloom.exe, so it is not ended: the update must give up
    // without touching any file, and start the old app again.
    final lockerExe = p.join(t.app.path, 'helper.exe');
    File(p.join(t.app.path, 'VocaBloom.exe')).copySync(lockerExe);
    final locker = await Process.start(lockerExe, ['-n', '600', '127.0.0.1']);
    final other = await Process.start('cmd', ['/c', 'exit']);
    await other.exitCode;
    final log = await runInstall(t, other.pid, killAfter: 2, giveUpAfter: 4);
    expect(File(t.marker).existsSync(), isTrue, reason: 'old app was not started again. Log: $log');
    expect(t.result.readAsStringSync().trim(), startsWith('fail locked'), reason: log);
    expect(File(p.join(t.app.path, 'old.txt')).readAsStringSync(), 'old', reason: log);
    expect(File(p.join(t.app.path, 'data', 'x.bin')).existsSync(), isFalse);
    locker.kill();
    await locker.exitCode;
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

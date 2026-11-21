@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/online/native_fetch.dart';
import 'package:kelime_okur/online/windows_manifest.dart';
import 'package:kelime_okur/online/windows_updater.dart';
import 'package:path/path.dart' as p;

// Runs on a real Windows machine (CI: update-windows.yml). The Dart HTTP
// client is switched off, as it fails on some users' PCs, so the Windows
// fallbacks (curl.exe, PowerShell) do the work.
const _release = 'https://api.github.com/repos/hamitgk-beep/vocabloom/releases/tags/latest';
const _zip = 'https://github.com/hamitgk-beep/vocabloom/releases/download/latest/Storilex-Windows.zip';

/// Windows runners have python, Linux and macOS python3.
final _python = Platform.isWindows ? 'python' : 'python3';

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

  test('update zip downloads with progress and unpacks with Storilex.exe', () async {
    debugSkipDartHttp = true;
    // Until the first release after the rename, 'latest' has only the VocaBloom files.
    final rel = await fetchText(_release, headers: {'Accept': 'application/vnd.github+json'});
    if (!rel.contains('"Storilex-Windows.zip"')) {
      markTestSkipped('the latest release has no Storilex-Windows.zip yet');
      return;
    }
    final seen = <double?>[];
    final dir = await WindowsUpdater.prepare(_zip, seen.add, expectedSize: 40 * 1024 * 1024);
    expect(File(p.join(dir.path, 'Storilex.exe')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'flutter_windows.dll')).existsSync(), isTrue);
    expect(seen.last, 1);
    dir.parent.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 10)));

  // A fake installed app: Storilex.exe is a copy of ping.exe, so while it
  // runs Windows keeps the file locked, like the real app's exe and DLLs.
  Future<({Directory root, Directory app, Directory work, Directory fresh, String marker, String exe, File result})> setUp_() async {
    final root = Directory.systemTemp.createTempSync('vb_install');
    final app = Directory(p.join(root.path, 'Kitaplar Gök'))..createSync();
    File(p.join(Platform.environment['SystemRoot']!, 'System32', 'PING.EXE')).copySync(p.join(app.path, 'Storilex.exe'));
    File(p.join(app.path, 'old.txt')).writeAsStringSync('old');
    File(p.join(app.path, 'keep.txt')).writeAsStringSync('keep');
    final work = Directory(p.join(root.path, 'İndirilen ğüş'))..createSync();
    final fresh = Directory(p.join(work.path, 'new'))..createSync();
    Directory(p.join(fresh.path, 'data')).createSync();
    File(p.join(fresh.path, 'old.txt')).writeAsStringSync('new');
    File(p.join(fresh.path, 'Storilex.exe')).writeAsStringSync('new exe');
    File(p.join(fresh.path, 'data', 'x.bin')).writeAsStringSync('x');
    final marker = p.join(root.path, 'started.txt');
    final exe = p.join(app.path, 'run.cmd');
    // Like the real app (WindowsUpdater.confirmStarted), the started program
    // tells the script it is up.
    final run = '@echo started> "$marker"\r\n@if defined VB_HEALTH echo ok> "%VB_HEALTH%"\r\n@exit\r\n';
    File(exe).writeAsStringSync(run);
    File(p.join(fresh.path, 'run.cmd')).writeAsStringSync(run);
    return (root: root, app: app, work: work, fresh: fresh, marker: marker, exe: exe, result: File(p.join(root.path, 'result.txt')));
  }

  Future<String> runInstall(
    dynamic t,
    int appPid, {
    int killAfter = 10,
    int giveUpAfter = 40,
    String appName = 'Storilex.exe',
    String? remove,
    List<String> delete = const [],
    int waitStart = 30,
  }) async {
    if (!File(p.join(t.work.path, 'touched.txt')).existsSync()) {
      await WindowsUpdater.writeLists(t.work, [...listFolder(t.fresh), ...delete], delete);
    }
    final script = File(p.join(t.work.path, 'install.cmd'))..writeAsStringSync(WindowsUpdater.installScript(appPid));
    await WindowsUpdater.launchScript(
      script.path,
      WindowsUpdater.installEnv(
        newFiles: t.fresh.path,
        appDir: t.app.path,
        exe: t.exe,
        cleanup: t.work.path,
        result: t.result.path,
        appName: appName,
        remove: remove,
        log: p.join(t.root.path, 'update.log'),
        killAfter: killAfter,
        giveUpAfter: giveUpAfter,
        waitStart: waitStart,
      ),
    );
    // The script writes its result once the started program is up (or,
    // after a rollback, just before it starts the old one again).
    for (var i = 0; i < 480 && !(File(t.marker).existsSync() && t.result.existsSync()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final log = File(p.join(t.root.path, 'update.log'));
    var text = log.existsSync() ? latin1.decode(log.readAsBytesSync()) : '-';
    if (!File(t.marker).existsSync()) {
      final ps = await Process.run('tasklist', ['/v', '/fo', 'list']);
      text +=
          '\n--- processes ---\n${'${ps.stdout}'.split(RegExp(r'\r?\n\r?\n')).where((b) => RegExp(r'cmd|robocopy|wscript|conhost|ping|Storilex|helper', caseSensitive: false).hasMatch(b)).join('\n\n')}';
    }
    return text;
  }

  test('install waits until the app has let go of its files, copies them and restarts', () async {
    final t = await setUp_();
    final app = await Process.start(p.join(t.app.path, 'Storilex.exe'), ['-n', '4', '127.0.0.1']);
    final sw = Stopwatch()..start();
    final log = await runInstall(t, app.pid);
    expect(File(t.marker).existsSync(), isTrue, reason: 'app was not started again. Log: $log');
    expect(sw.elapsed.inMilliseconds, greaterThan(2000), reason: 'did not wait for the app to exit. Log: $log');
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(p.join(t.app.path, 'Storilex.exe')).readAsStringSync(), 'new exe', reason: log);
    expect(File(p.join(t.app.path, 'old.txt')).readAsStringSync(), 'new', reason: log);
    expect(File(p.join(t.app.path, 'keep.txt')).readAsStringSync(), 'keep');
    expect(File(p.join(t.app.path, 'data', 'x.bin')).existsSync(), isTrue);
    // The download folder (with the script in it) is removed just after the start.
    for (var i = 0; i < 40 && t.work.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(t.work.existsSync(), isFalse, reason: log);
    await app.exitCode;
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('install ends an app that does not close and then updates it', () async {
    final t = await setUp_();
    // Hangs for 10 minutes; the pid given to the script is another process,
    // so only the "end any Storilex.exe" step can free the files.
    final hung = await Process.start(p.join(t.app.path, 'Storilex.exe'), ['-n', '600', '127.0.0.1']);
    final other = await Process.start('cmd', ['/c', 'exit']);
    await other.exitCode;
    final log = await runInstall(t, other.pid, killAfter: 3, giveUpAfter: 20);
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(p.join(t.app.path, 'Storilex.exe')).readAsStringSync(), 'new exe', reason: log);
    expect(await hung.exitCode.timeout(const Duration(seconds: 5)), isNot(0));
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('install copies nothing while a file stays locked and reports it', () async {
    final t = await setUp_();
    // Not named Storilex.exe, so it is not ended: the update must give up
    // without touching any file, and start the old app again.
    final lockerExe = p.join(t.app.path, 'helper.exe');
    File(p.join(t.app.path, 'Storilex.exe')).copySync(lockerExe);
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
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('an update from the VocaBloom.exe copy removes it once the copy worked', () async {
    final t = await setUp_();
    final legacy = p.join(t.app.path, 'VocaBloom.exe');
    File(p.join(t.app.path, 'Storilex.exe')).copySync(legacy);
    final app = await Process.start(legacy, ['-n', '3', '127.0.0.1']);
    final log = await runInstall(t, app.pid, appName: 'VocaBloom.exe', remove: legacy);
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(legacy).existsSync(), isFalse, reason: log);
    expect(File(p.join(t.app.path, 'Storilex.exe')).readAsStringSync(), 'new exe', reason: log);
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('files dropped by the new version are deleted after a good copy', () async {
    final t = await setUp_();
    File(p.join(t.app.path, 'gone.dll')).writeAsStringSync('old plugin');
    final log = await runInstall(t, 999999, delete: ['gone.dll']);
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(p.join(t.app.path, 'gone.dll')).existsSync(), isFalse, reason: log);
    expect(File(p.join(t.app.path, 'keep.txt')).readAsStringSync(), 'keep');
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a new version that closes before it starts is rolled back to the old one', () async {
    final t = await setUp_();
    File(p.join(t.app.path, 'gone.dll')).writeAsStringSync('old plugin');
    // The new program never says it is up, and exits at once.
    final crashed = p.join(t.root.path, 'new-started.txt');
    File(p.join(t.fresh.path, 'run.cmd')).writeAsStringSync('@echo new> "$crashed"\r\n@exit 1\r\n');
    final log = await runInstall(t, 999999, delete: ['gone.dll'], waitStart: 60);
    // The old app is started right after the result is written.
    for (var i = 0; i < 40 && !File(t.marker).existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(File(crashed).existsSync(), isTrue, reason: 'the new version was not started. Log: $log');
    // The marker comes from the old run.cmd, started again after the rollback.
    expect(File(t.marker).existsSync(), isTrue, reason: 'old app was not started again. Log: $log');
    expect(t.result.readAsStringSync().trim(), 'fail start, old version restored', reason: log);
    expect(File(p.join(t.app.path, 'old.txt')).readAsStringSync(), 'old', reason: log);
    expect(File(p.join(t.app.path, 'Storilex.exe')).readAsBytesSync().length, greaterThan(1000), reason: 'old exe is back. Log: $log');
    expect(File(p.join(t.app.path, 'gone.dll')).readAsStringSync(), 'old plugin', reason: log);
    expect(File(p.join(t.app.path, 'data', 'x.bin')).existsSync(), isFalse, reason: 'files the update added are removed. Log: $log');
    expect(File(p.join(t.app.path, 'run.cmd')).readAsStringSync(), contains('VB_HEALTH'), reason: log);
    expect(File(p.join(t.app.path, 'keep.txt')).readAsStringSync(), 'keep');
    t.root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('file-by-file update: only changed files are downloaded, checked and installed', () async {
    final t = await setUp_();
    final root = t.root;
    // The release: the tool writes the manifest and one blob per file.
    final next = Directory(p.join(root.path, 'release'))..createSync();
    File(p.join(t.app.path, 'Storilex.exe')).copySync(p.join(next.path, 'Storilex.exe'));
    File(p.join(next.path, 'keep.txt')).writeAsStringSync('keep');
    File(p.join(next.path, 'old.txt')).writeAsStringSync('new');
    File(p.join(next.path, 'run.cmd')).writeAsStringSync(File(t.exe).readAsStringSync());
    final blobs = p.join(root.path, 'blobs');
    final out = p.join(root.path, 'manifest.json');
    final r = await Process.run(_python, ['-I', 'tools/release/windows_manifest.py', '--dir', next.path, '--build', '2', '--blobs', blobs, '--out', out]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final m = WindowsManifest.parse(File(out).readAsStringSync());
    final plan = await planUpdate(m, t.app);
    expect(plan.download.map((f) => f.path), ['old.txt'], reason: 'Storilex.exe, keep.txt and run.cmd are unchanged');

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final f = File(p.join(blobs, req.uri.pathSegments.last));
      if (f.existsSync()) {
        req.response.add(f.readAsBytesSync());
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final stage = await WindowsUpdater.prepareFiles(plan, 'http://127.0.0.1:${server.port}/', (_) {});
    await server.close(force: true);
    final t2 = (root: root, app: t.app, work: stage.parent, fresh: stage, marker: t.marker, exe: t.exe, result: t.result);
    final log = await runInstall(t2, 999999);
    expect(t.result.readAsStringSync().trim(), 'ok', reason: log);
    expect(File(p.join(t.app.path, 'old.txt')).readAsStringSync(), 'new', reason: log);
    expect(File(p.join(t.app.path, WindowsManifest.fileName)).readAsStringSync(), m.text, reason: log);
    root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

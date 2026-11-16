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

  test('update zip downloads with progress and unpacks with VocaBloom.exe', () async {
    debugSkipDartHttp = true;
    final seen = <double?>[];
    final dir = await WindowsUpdater.prepare(_zip, seen.add, expectedSize: 40 * 1024 * 1024);
    expect(File(p.join(dir.path, 'VocaBloom.exe')).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'flutter_windows.dll')).existsSync(), isTrue);
    expect(seen.last, 1);
    dir.parent.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('install script waits for the app, copies the files and restarts it', () async {
    final root = Directory.systemTemp.createTempSync('vb_install');
    final app = Directory(p.join(root.path, 'Kitaplar Gök'))..createSync();
    File(p.join(app.path, 'old.txt')).writeAsStringSync('old');
    File(p.join(app.path, 'keep.txt')).writeAsStringSync('keep');
    final work = Directory(p.join(root.path, 'İndirilen ğüş'))..createSync();
    final fresh = Directory(p.join(work.path, 'new'))..createSync();
    Directory(p.join(fresh.path, 'data')).createSync();
    File(p.join(fresh.path, 'old.txt')).writeAsStringSync('new');
    File(p.join(fresh.path, 'data', 'x.bin')).writeAsStringSync('x');
    final marker = p.join(root.path, 'started.txt');
    final exe = p.join(app.path, 'run.cmd');
    File(p.join(fresh.path, 'run.cmd')).writeAsStringSync('@echo started> "$marker"\r\n@exit\r\n');
    // Stands in for the running app: lives about 3 seconds.
    final fake = await Process.start('ping', ['-n', '4', '127.0.0.1']);
    final script = File(p.join(work.path, 'install.cmd'))..writeAsStringSync(WindowsUpdater.installScript(fake.pid));
    final sw = Stopwatch()..start();
    await Process.start(
      'cmd',
      ['/c', script.path],
      mode: ProcessStartMode.detached,
      environment: WindowsUpdater.installEnv(newFiles: fresh.path, appDir: app.path, exe: exe, cleanup: work.path),
    );
    for (var i = 0; i < 120 && (!File(marker).existsSync() || work.existsSync()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final log = File(p.join(Platform.environment['TEMP']!, 'vocabloom-update.log'));
    expect(File(marker).existsSync(), isTrue, reason: 'app was not started again. Log: ${log.existsSync() ? log.readAsStringSync() : '-'}');
    expect(sw.elapsed.inMilliseconds, greaterThan(1500), reason: 'did not wait for the app to exit');
    expect(File(p.join(app.path, 'old.txt')).readAsStringSync(), 'new', reason: log.readAsStringSync());
    expect(File(p.join(app.path, 'keep.txt')).readAsStringSync(), 'keep');
    expect(File(p.join(app.path, 'data', 'x.bin')).existsSync(), isTrue);
    expect(work.existsSync(), isFalse);
    await fake.exitCode;
    root.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 1)));
}

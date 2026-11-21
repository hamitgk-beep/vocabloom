import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/online/windows_manifest.dart';
import 'package:path/path.dart' as p;

/// The release job writes the manifest and blobs with
/// tools/release/windows_manifest.py; the app reads them back, compares its
/// own files and downloads only what changed. Runs on every platform: the
/// Windows install script itself is tested in update_windows_test.dart.
/// Windows runners have python, Linux and macOS python3.
final _python = Platform.isWindows ? 'python' : 'python3';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('vb_manifest'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(Directory d, String rel, String text) {
    final f = File(p.joinAll([d.path, ...rel.split('/')]));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  /// Runs the release tool on [dir]; returns the manifest and the blob folder.
  Future<(WindowsManifest, Directory)> release(Directory dir, int build) async {
    final blobs = Directory(p.join(tmp.path, 'blobs$build'));
    final out = p.join(tmp.path, 'manifest$build.json');
    final r = await Process.run(_python, [
      '-I', 'tools/release/windows_manifest.py', '--dir', dir.path, '--build', '$build', '--version', '1.$build', '--blobs', blobs.path, '--out', out,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return (WindowsManifest.parse(File(out).readAsStringSync()), blobs);
  }

  /// Serves [blobs] over HTTP, like the release's download links.
  Future<HttpServer> serve(Directory blobs, {Set<String> corrupt = const {}}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final name = req.uri.pathSegments.last;
      final f = File(p.join(blobs.path, name));
      if (!f.existsSync()) {
        req.response.statusCode = 404;
      } else if (corrupt.contains(name)) {
        req.response.add(gzip.encode(utf8.encode('tampered')));
      } else {
        req.response.add(f.readAsBytesSync());
      }
      await req.response.close();
    });
    return server;
  }

  Directory build(String name, Map<String, String> files) {
    final d = Directory(p.join(tmp.path, name))..createSync();
    files.forEach((k, v) => write(d, k, v));
    return d;
  }

  test('only changed and new files are downloaded, dropped ones removed, and every file checked', () async {
    final big = 'x' * 200000;
    final old = build('old', {
      'Storilex.exe': 'exe 1',
      'flutter_windows.dll': big,
      'data/app.so': 'code 1',
      'data/flutter_assets/assets/dict.db': 'dictionary',
      'gone.dll': 'old plugin',
    });
    await release(old, 1); // the installed version keeps its storilex-manifest.json
    expect(File(p.join(old.path, WindowsManifest.fileName)).existsSync(), isTrue);
    // Books and words are never in the app folder; a stray file a user put
    // there must survive too, as it is not in any manifest.
    write(old, 'my notes.txt', 'mine');

    final next = build('next', {
      'Storilex.exe': 'exe 2',
      'flutter_windows.dll': big,
      'data/app.so': 'code 2',
      'data/flutter_assets/assets/dict.db': 'dictionary',
      'new_plugin.dll': 'new',
    });
    final (m, blobs) = await release(next, 2);
    expect(m.build, 2);
    expect(m.files.map((f) => f.path), isNot(contains(WindowsManifest.fileName)));

    final plan = await planUpdate(m, old);
    expect(plan.download.map((f) => f.path).toSet(), {'Storilex.exe', 'data/app.so', 'new_plugin.dll'});
    expect(plan.remove, ['gone.dll']);
    expect(plan.bytes, lessThan(200), reason: 'the unchanged 200 KB DLL is not downloaded');

    final server = await serve(blobs);
    final stage = Directory(p.join(tmp.path, 'stage'));
    final seen = <double>[];
    await downloadPlan(plan, 'http://127.0.0.1:${server.port}/latest/', stage, seen.add);
    await server.close(force: true);
    expect(seen.last, 1.0);
    expect(File(p.join(stage.path, 'data', 'app.so')).readAsStringSync(), 'code 2');
    expect(File(p.join(stage.path, 'Storilex.exe')).readAsStringSync(), 'exe 2');
    expect(File(p.join(stage.path, 'flutter_windows.dll')).existsSync(), isFalse);
    expect(File(p.join(stage.path, WindowsManifest.fileName)).readAsStringSync(), m.text);
    expect(stage.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.gz')), isEmpty);

    final lists = installLists(plan);
    expect(lists.touched, containsAll([r'data\app.so', 'Storilex.exe', 'new_plugin.dll', WindowsManifest.fileName, 'gone.dll']));
    expect(lists.touched, isNot(contains('my notes.txt')));
    expect(lists.remove, ['gone.dll']);
  });

  test('an install without a manifest (from a full zip) deletes nothing', () async {
    final old = build('old', {'Storilex.exe': 'exe 1', 'gone.dll': 'x'});
    final (m, _) = await release(build('next', {'Storilex.exe': 'exe 2'}), 2);
    final plan = await planUpdate(m, old);
    expect(plan.download.map((f) => f.path), ['Storilex.exe']);
    expect(plan.remove, isEmpty);
  });

  test('a damaged installed file is downloaded again even with the same size', () async {
    final old = build('old', {'Storilex.exe': 'exe 1', 'a.dll': 'AAAA'});
    final (m, _) = await release(build('next', {'Storilex.exe': 'exe 1', 'a.dll': 'AAAA'}), 2);
    expect((await planUpdate(m, old)).download, isEmpty);
    write(old, 'a.dll', 'AAAB');
    expect((await planUpdate(m, old)).download.map((f) => f.path), ['a.dll']);
  });

  test('a file that does not match its checksum stops the update', () async {
    final old = build('old', {'Storilex.exe': 'exe 1'});
    final (m, blobs) = await release(build('next', {'Storilex.exe': 'exe 2'}), 2);
    final plan = await planUpdate(m, old);
    final server = await serve(blobs, corrupt: {plan.download.single.blob});
    await expectLater(
      downloadPlan(plan, 'http://127.0.0.1:${server.port}/', Directory(p.join(tmp.path, 'stage')), (_) {}),
      throwsA(isA<FileSystemException>().having((e) => e.message, 'message', 'checksum mismatch')),
    );
    await server.close(force: true);
    expect(File(p.join(old.path, 'Storilex.exe')).readAsStringSync(), 'exe 1');
  });

  test('a missing file on the server stops the update', () async {
    final old = build('old', {'Storilex.exe': 'exe 1'});
    final (m, blobs) = await release(build('next', {'Storilex.exe': 'exe 2'}), 2);
    final plan = await planUpdate(m, old);
    final server = await serve(Directory(p.join(tmp.path, 'empty'))..createSync());
    await expectLater(downloadPlan(plan, 'http://127.0.0.1:${server.port}/', Directory(p.join(tmp.path, 'stage')), (_) {}), throwsA(anything));
    await server.close(force: true);
    expect(blobs.existsSync(), isTrue);
  });

  test('manifests with unsafe or unexpected entries are refused', () {
    String m(List<Map<String, Object>> files, {int schema = 1}) => jsonEncode({'schema': schema, 'build': 2, 'files': files});
    Map<String, Object> f(String path) => {'path': path, 'size': 1, 'sha256': 'a' * 64, 'gz': 1};
    expect(WindowsManifest.parse(m([f('Storilex.exe'), f('data/app.so')])).files, hasLength(2));
    for (final bad in ['../evil.dll', '/abs.dll', r'C:\x.dll', 'C:/x.dll', 'data/../../x', 'a b.dll', 'Kitaplar Gök/x', 'data//x', WindowsManifest.fileName]) {
      expect(() => WindowsManifest.parse(m([f('Storilex.exe'), f(bad)])), throwsFormatException, reason: bad);
    }
    expect(() => WindowsManifest.parse(m([f('Storilex.exe'), f('STORILEX.EXE')])), throwsFormatException, reason: 'listed twice');
    expect(() => WindowsManifest.parse(m([f('data/app.so')])), throwsFormatException, reason: 'no Storilex.exe');
    expect(() => WindowsManifest.parse(m([f('Storilex.exe')], schema: 2)), throwsFormatException, reason: 'unknown schema');
    expect(() => WindowsManifest.parse(jsonEncode({'schema': 1, 'files': [{'path': 'Storilex.exe', 'size': 1, 'sha256': 'xyz', 'gz': 1}]})), throwsFormatException);
  });

  test('the release tool measures the update from an older build', () async {
    final old = build('old', {'Storilex.exe': 'exe 1', 'data/app.so': 'same'});
    final next = build('next', {'Storilex.exe': 'exe 2', 'data/app.so': 'same'});
    final r = await Process.run(_python, ['-I', 'tools/release/windows_manifest.py', '--dir', next.path, '--compare', old.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('1 changed, 0 new, 0 removed'));
    expect(File(p.join(next.path, WindowsManifest.fileName)).existsSync(), isFalse, reason: 'measuring writes no manifest');
  });
}

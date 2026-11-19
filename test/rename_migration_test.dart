import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/online/rename_migration.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('rename_mig'));
  tearDown(() => root.deleteSync(recursive: true));

  test('books and words move from the VocaBloom folder to an empty Storilex folder', () {
    final old = Directory(p.join(root.path, 'VocaBloom'))..createSync();
    File(p.join(old.path, 'user.db')).writeAsStringSync('mine');
    final fresh = Directory(p.join(root.path, 'Storilex'))..createSync();
    final got = RenameMigration.dataFolder(fresh);
    expect(got.path, fresh.path);
    expect(File(p.join(fresh.path, 'user.db')).readAsStringSync(), 'mine');
    expect(old.existsSync(), isFalse);
  });

  test('a Storilex folder that already has data is kept', () {
    final old = Directory(p.join(root.path, 'VocaBloom'))..createSync();
    File(p.join(old.path, 'user.db')).writeAsStringSync('old');
    final fresh = Directory(p.join(root.path, 'Storilex'))..createSync();
    File(p.join(fresh.path, 'user.db')).writeAsStringSync('new');
    expect(RenameMigration.dataFolder(fresh).path, fresh.path);
    expect(File(p.join(fresh.path, 'user.db')).readAsStringSync(), 'new');
  });

  test('a new install without the old folder uses the Storilex folder', () {
    final fresh = Directory(p.join(root.path, 'Storilex'));
    expect(RenameMigration.dataFolder(fresh).path, fresh.path);
  });

  test('shortcuts are left alone when this is not the VocaBloom.exe copy', () async {
    await RenameMigration.moveShortcuts(running: p.join(root.path, 'Storilex.exe'));
  });
}

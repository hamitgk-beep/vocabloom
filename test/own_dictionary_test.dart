// The own-dictionary fallback in DictDb.lookup(): with the flag off the app reads
// exactly what it reads today (ft); with the flag on, own_word comes first and
// ft is used whenever there is no own meaning or the table is missing.
// The bundled database is never written to; every test works on a temporary copy.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/data/dict_db.dart';

const _asset = 'assets/dict.db';

/// A temporary copy of the bundled database. With [withOwn] it also gets an own_word table
/// shaped like the one tools/own_dict/db/migrate.py creates.
String _copy({required bool withOwn}) {
  final dir = Directory.systemTemp.createTempSync('own_dict_test');
  final path = '${dir.path}/dict.db';
  File(_asset).copySync(path);
  if (withOwn) {
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE own_word(
        word TEXT PRIMARY KEY, senses TEXT NOT NULL, keep_tr TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT, note TEXT);
      INSERT INTO own_word(word, senses, keep_tr, status) VALUES
        ('book', '[{"tr":"yeni anlam","src":"fix"}]', '["eski anlam"]', 'auto_generated'),
        ('dog', '[]', '[]', 'auto_generated');
    ''');
    db.dispose();
  }
  return path;
}

DictDb _open(String path) {
  final d = DictDb();
  d.db = sqlite3.open(path, mode: OpenMode.readOnly);
  d.load();
  return d;
}

void main() {
  late List<String> baselineBook;
  late List<String> baselineDog;

  setUpAll(() {
    final base = _open(_asset);
    baselineBook = base.lookup('book').trFreeDict;
    baselineDog = base.lookup('dog').trFreeDict;
    expect(baselineBook, isNotEmpty, reason: 'the bundled ft table must have a meaning for book');
  });

  test('flag off (the app default): lookup reads ft even when own_word exists', () {
    expect(DictDb.useOwnDictionary, isFalse, reason: 'production default must stay off');
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('book').trFreeDict, baselineBook);
    expect(d.lookup('dog').trFreeDict, baselineDog);
  });

  test('flag on: own meanings come first, keep_tr before the new senses', () {
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('book', ownEnabled: true).trFreeDict, ['eski anlam', 'yeni anlam']);
  });

  test('flag on: a word without an own row still reads ft', () {
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('house', ownEnabled: true).trFreeDict, _open(_asset).lookup('house').trFreeDict);
  });

  test('flag on: an empty own row falls back to ft', () {
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('dog', ownEnabled: true).trFreeDict, baselineDog);
  });

  test('flag on but no own_word table: no error, ft is used', () {
    final d = _open(_asset);
    expect(d.lookup('book', ownEnabled: true).trFreeDict, baselineBook);
  });

  test('the bundled database is still opened read-only and unchanged', () {
    final before = File(_asset).lengthSync();
    _open(_asset).lookup('book', ownEnabled: true);
    expect(File(_asset).lengthSync(), before);
  });
}

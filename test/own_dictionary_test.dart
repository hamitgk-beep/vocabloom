// The own-dictionary fallback in DictDb.lookup(): with ownEnabled false the app reads exactly what
// it reads today (ft); with ownEnabled true, a verified own row comes first and an unreviewed AI
// draft never replaces ft (DictDb.sourcePolicy); ft is used whenever there is no own meaning or the
// table is missing. The released default is on (useOwnDictionary = true).
// The bundled database is never written to; every test works on a temporary copy.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/data/dict_db.dart';

const _asset = 'assets/dict.db';

/// A temporary copy of the bundled database. With [withOwn] it gets a fresh own_word table
/// shaped like the one tools/own_dict/db/migrate.py creates, with two test rows. Without it the
/// own tables are removed, so the copy behaves like a database from before the import.
String _copy({required bool withOwn}) {
  final dir = Directory.systemTemp.createTempSync('own_dict_test');
  final path = '${dir.path}/dict.db';
  File(_asset).copySync(path);
  final db = sqlite3.open(path);
  db.execute('DROP VIEW IF EXISTS od; DROP TABLE IF EXISTS own_word; DROP TABLE IF EXISTS own_expr;');
  if (withOwn) {
    db.execute('''
      CREATE TABLE own_word(
        word TEXT PRIMARY KEY, senses TEXT NOT NULL, keep_tr TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL, reviewed INTEGER NOT NULL DEFAULT 0, action TEXT, source TEXT, note TEXT);
      INSERT INTO own_word(word, senses, keep_tr, status) VALUES
        ('book', '[{"tr":"yeni anlam","src":"fix"}]', '["eski anlam"]', 'auto_generated'),
        ('dog', '[]', '[]', 'auto_generated');
      INSERT INTO own_word(word, senses, keep_tr, status, reviewed) VALUES
        ('house', '[{"tr":"onaylı anlam","src":"storilex"}]', '["eski ev"]', 'contrib', 1);
    ''');
  }
  db.dispose();
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
    // ft-only baseline, taken with the own dictionary explicitly off.
    final base = _open(_asset);
    baselineBook = base.lookup('book', ownEnabled: false).trFreeDict;
    baselineDog = base.lookup('dog', ownEnabled: false).trFreeDict;
    expect(baselineBook, isNotEmpty, reason: 'the bundled ft table must have a meaning for book');
  });

  test('released default is on, and turning it off reads ft even when own_word exists', () {
    expect(DictDb.useOwnDictionary, isTrue, reason: 'the import is released with the flag on');
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('book', ownEnabled: false).trFreeDict, baselineBook);
    expect(d.lookup('dog', ownEnabled: false).trFreeDict, baselineDog);
  });

  test('flag on: an unreviewed own row keeps keep_tr and ft; its senses are only drafts', () {
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('book', ownEnabled: true).trFreeDict, ['eski anlam', ...baselineBook]);
    expect(d.lookup('book', ownEnabled: true).trDraft, ['yeni anlam']);
  });

  test('flag on: a verified own row comes first, then keep_tr, then ft', () {
    final d = _open(_copy(withOwn: true));
    final ft = _open(_asset).lookup('house', ownEnabled: false).trFreeDict;
    expect(d.lookup('house', ownEnabled: true).trFreeDict, ['onaylı anlam', 'eski ev', ...ft.where((t) => t != 'eski ev')]);
  });

  test('policy off: keep_tr before the new senses, as before the source order', () {
    DictDb.sourcePolicy = false;
    try {
      final d = _open(_copy(withOwn: true));
      expect(d.lookup('book', ownEnabled: true).trFreeDict, ['eski anlam', 'yeni anlam']);
    } finally {
      DictDb.sourcePolicy = true;
    }
  });

  test('flag on: a word without an own row still reads ft', () {
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('cat', ownEnabled: true).trFreeDict,
        _open(_asset).lookup('cat', ownEnabled: false).trFreeDict);
  });

  test('flag on: an empty own row falls back to ft', () {
    final d = _open(_copy(withOwn: true));
    expect(d.lookup('dog', ownEnabled: true).trFreeDict, baselineDog);
  });

  test('flag on but no own_word table: no error, ft is used', () {
    final d = _open(_copy(withOwn: false));
    expect(d.lookup('book', ownEnabled: true).trFreeDict, baselineBook);
  });

  test('the bundled database is still opened read-only and unchanged', () {
    final before = File(_asset).lengthSync();
    _open(_asset).lookup('book', ownEnabled: true);
    expect(File(_asset).lengthSync(), before);
  });

  test('own expression: an AI draft is kept apart when on, the gloss under the old order, the old one when off', () {
    final db = sqlite3.open(_asset, mode: OpenMode.readOnly);
    final row = db.select("SELECT senses FROM own_expr WHERE phrase = 'a dime a dozen' AND cat = 'idioms'");
    db.dispose();
    expect(row, isNotEmpty);
    final ownFirst = (jsonDecode(row.first.columnAt(0) as String) as List).first as Map;

    final on = DictDb();
    on.db = sqlite3.open(_asset, mode: OpenMode.readOnly);
    on.load(ownEnabled: true);
    final off = DictDb();
    off.db = sqlite3.open(_asset, mode: OpenMode.readOnly);
    off.load(ownEnabled: false);

    final e1 = on.exprs.firstWhere((e) => e.phrase == 'a dime a dozen' && e.cat == 'idioms');
    final e2 = off.exprs.firstWhere((e) => e.phrase == 'a dime a dozen' && e.cat == 'idioms');
    // The row is an unreviewed AI draft (DictDb.sourcePolicy): the gloss stays, the draft is apart.
    expect(e1.tr, e2.tr);
    expect(e1.trDraft, contains(ownFirst['tr'] as String));
    expect(e2.tr, isNot(contains(ownFirst['tr'] as String)));

    DictDb.sourcePolicy = false;
    try {
      final old = DictDb();
      old.db = sqlite3.open(_asset, mode: OpenMode.readOnly);
      old.load(ownEnabled: true);
      expect(old.exprs.firstWhere((e) => e.phrase == 'a dime a dozen' && e.cat == 'idioms').tr, contains(ownFirst['tr'] as String));
    } finally {
      DictDb.sourcePolicy = true;
    }
  });

  test('expression sheet: drafts only in their own list when on, the built-in library when off, and back again', () {
    final db = sqlite3.open(_asset, mode: OpenMode.readOnly);
    final row = db.select("SELECT senses FROM own_expr WHERE phrase = 'a dime a dozen' AND cat = 'idioms'");
    db.dispose();
    final ownFirst = (jsonDecode(row.first.columnAt(0) as String) as List).first as Map;

    final on = DictDb();
    on.db = sqlite3.open(_asset, mode: OpenMode.readOnly);
    on.load(ownEnabled: true);
    final detailOn = on.exprDetail('a dime a dozen', 'idioms');
    expect(detailOn == null || (jsonDecode(detailOn) as List).first['title_tr'] != ownFirst['tr'], isTrue);
    final drafts = jsonDecode(on.exprDraftDetail('a dime a dozen', 'idioms')!) as List;
    expect((drafts.first as Map)['title_tr'], ownFirst['tr']);
    expect((drafts.first as Map)['explain_tr'], '');

    final off = DictDb();
    off.db = sqlite3.open(_asset, mode: OpenMode.readOnly);
    off.load(ownEnabled: false);
    final detailOff = off.exprDetail('a dime a dozen', 'idioms');
    expect(detailOff == null || (jsonDecode(detailOff) as List).first['title_tr'] != ownFirst['tr'], isTrue);
  });
}

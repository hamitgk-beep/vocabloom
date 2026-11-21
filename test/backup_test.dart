// The backup file (.storilex): what goes in, what never goes in, and that a
// restore keeps the learner's data safe. A bad file never touches the data on
// the device, a restore can be undone, and a merge never moves a reading
// position or a word on its own when the two devices disagree.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/backup.dart';
import 'package:kelime_okur/data/review.dart';
import 'package:kelime_okur/data/stats.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

const fakeKey = 'sk-ant-SECRET-1234567890';

ImportedBook sampleBook({String title = 'The Garden', int chapters = 3, Map<String, List<int>>? images}) => ImportedBook(
      title,
      'A. Writer',
      'epub',
      [
        for (var c = 0; c < chapters; c++)
          ImportedChapter('Chapter ${c + 1}', [
            if (c == 0 && images != null) ('i', images.keys.first),
            for (var i = 0; i < 5; i++) ('p', '$title, chapter ${c + 1}, paragraph ${i + 1}. The rain fell softly.'),
          ]),
      ],
      images,
    );

/// A device with words, reviews, a book with a picture, stats and settings.
UserDb device(Directory dir) {
  final u = UserDb.open(dir);
  ReviewStore(u);
  StatsStore(u);
  u.setWord('rain', WordStatus.learning, context: 'The rain fell softly.', book: 'The Garden');
  u.setWord('garden', WordStatus.learned);
  u.db.execute('INSERT INTO review(lemma, box, due, reps, lapses) VALUES (?,?,?,?,?)', ['rain', 2, 1000, 3, 0]);
  final id = u.insertBook(sampleBook(images: {'cover.png': [1, 2, 3, 4]}));
  u.saveProgress(id, 1, 3);
  u.db.execute('INSERT INTO reading_time(day, book_id, seconds) VALUES (?,?,?)', ['2026-11-10', id, 600]);
  u.db.execute('INSERT INTO read_para(book_id, chapter, idx, words, day) VALUES (?,?,?,?,?)', [id, 0, 1, 9, '2026-11-10']);
  u.setSetting('prefs', jsonEncode({'font': 22, 'theme': 'dark'}));
  u.setSetting('ai_provider', 'anthropic');
  u.setSetting('ai_key_anthropic', fakeKey);
  u.setSetting('api_key', fakeKey);
  u.setSetting('tts_rtf_kokoro', '0.420');
  u.setSetting('tts_removed_kokoro-en-fp32-v1', '1');
  return u;
}

String fileSha(File f) => sha256.convert(f.readAsBytesSync()).toString();

/// Every file under [dir]/books, by path, with its checksum.
Map<String, String> pictures(Directory dir) {
  final d = Directory(p.join(dir.path, 'books'));
  if (!d.existsSync()) return {};
  return {
    for (final f in d.listSync(recursive: true).whereType<File>()) p.relative(f.path, from: dir.path): fileSha(f),
  };
}

/// What the learner sees of the data: words, review cards, books, paragraphs, settings.
String snapshot(UserDb u) => jsonEncode([
      for (final q in [
        'SELECT lemma, status FROM words ORDER BY lemma',
        'SELECT lemma, box, reps FROM review ORDER BY lemma',
        'SELECT id, title, last_chapter, last_para FROM books ORDER BY id',
        'SELECT book_id, chapter, idx, kind, text FROM paras ORDER BY book_id, chapter, idx',
        'SELECT key, value FROM settings ORDER BY key',
      ])
        u.db.select(q).map((r) => r.values).toList(),
    ]);

/// The restore's safety copies and journals in [dir]/backups.
List<String> journals(Directory dir) {
  final d = Directory(p.join(dir.path, 'backups'));
  if (!d.existsSync()) return [];
  return [for (final f in d.listSync().whereType<File>()) if (p.basename(f.path).startsWith('before-restore-')) p.basename(f.path)]..sort();
}

Matcher failsWith(String code) => throwsA(isA<BackupException>().having((e) => e.code, 'code', code));

void main() {
  late Directory root;
  late Directory a, b;
  setUp(() {
    root = Directory.systemTemp.createTempSync('storilex_backup');
    a = Directory(p.join(root.path, 'a'))..createSync();
    b = Directory(p.join(root.path, 'b'))..createSync();
  });
  tearDown(() {
    debugRestoreStep = null;
    root.deleteSync(recursive: true);
  });

  File out(String name) => File(p.join(root.path, name));

  test('book texts are in the backup by default and can be left out; the size is estimated for both', () {
    final u = device(a);
    final est = estimateBackupSize(u);
    expect(est.withBooks, greaterThan(est.withoutBooks));
    expect(est.withoutBooks, greaterThan(0));

    exportBackup(u, out('full.storilex'));
    exportBackup(u, out('lite.storilex'), includeBooks: false);
    final full = inspectBackup(UserDb.open(b), out('full.storilex'));
    final lite = inspectBackup(UserDb.open(b), out('lite.storilex'));
    expect(full.manifest.includesBooks, isTrue);
    expect(lite.manifest.includesBooks, isFalse);
    expect(full.manifest.counts['paras'], 15 + 1);
    expect(lite.manifest.counts['paras'], 0);
    full.dispose();
    lite.dispose();
  });

  test('API keys and device-only settings never go into the backup file', () {
    final u = device(a);
    final f = exportBackup(u, out('x.storilex'));
    final zip = ZipDecoder().decodeBytes(f.readAsBytesSync());
    for (final e in zip.files) {
      final bytes = e.readBytes() ?? const <int>[];
      expect(latin1.decode(bytes, allowInvalid: true).contains(fakeKey), isFalse, reason: '${e.name} carries the key');
    }
    final pv = inspectBackup(UserDb.open(b), f);
    final keys = pv.backupSettings.keys;
    expect(keys, isNot(contains('api_key')));
    expect(keys.where((k) => k.startsWith('ai_key_')), isEmpty);
    expect(keys, isNot(contains('tts_rtf_kokoro')));
    expect(keys.where((k) => k.startsWith('tts_removed_')), isEmpty);
    expect(keys, containsAll(['prefs', 'ai_provider']));
    pv.dispose();
    // The device's own data is unchanged by an export.
    expect(u.getSetting('ai_key_anthropic'), fakeKey);
  });

  test('a backup restored on an empty device brings back words, reviews, progress, pictures and stats', () {
    final u = device(a);
    exportBackup(u, out('x.storilex'));
    final v = UserDb.open(b);
    final pv = inspectBackup(v, out('x.storilex'));
    final r = restoreBackup(v, pv);
    pv.dispose();
    expect(r.wordsAdded, 2);
    expect(v.statuses['rain'], WordStatus.learning);
    expect(v.statuses['garden'], WordStatus.learned);
    expect(v.db.select('SELECT box, reps FROM review WHERE lemma=?', ['rain']).first['reps'], 3);
    final book = v.books().single;
    expect((book.lastChapter, book.lastParagraph), (1, 3));
    final pic = v.db.select("SELECT text FROM paras WHERE book_id=? AND kind='i'", [book.id]).first['text'] as String;
    expect(File(p.join(b.path, pic)).readAsBytesSync(), [1, 2, 3, 4]);
    expect(v.db.select('SELECT seconds FROM reading_time WHERE book_id=?', [book.id]).first['seconds'], 600);
    expect(v.db.select('SELECT COUNT(*) AS n FROM read_para WHERE book_id=?', [book.id]).first['n'], 1);
    expect(v.getSetting('prefs'), isNull, reason: 'a merge never changes the settings');
    expect(v.getSetting('ai_key_anthropic'), isNull);
  });

  group('a bad file is refused and the data on the device stays as it was', () {
    late UserDb v;
    late File db;
    setUp(() {
      v = device(b);
      db = File(p.join(b.path, 'user.db'));
      v.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    });

    void refused(File f, String code) {
      final before = fileSha(db);
      expect(() => inspectBackup(v, f), throwsA(isA<BackupException>().having((e) => e.code, 'code', code)));
      v.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      expect(fileSha(db), before);
    }

    Archive goodArchive() {
      final f = exportBackup(device(a), out('good.storilex'));
      return ZipDecoder().decodeBytes(f.readAsBytesSync());
    }

    File write(String name, Archive z) => out(name)..writeAsBytesSync(ZipEncoder().encodeBytes(z));

    test('not a zip', () => refused(out('junk.storilex')..writeAsStringSync('hello'), 'not_backup'));

    test('no manifest', () {
      final z = Archive()..add(ArchiveFile.bytes('data.db', [1, 2, 3]));
      refused(write('nomanifest.storilex', z), 'not_backup');
    });

    test('a newer backup format than this app knows', () {
      final z = goodArchive();
      final m = jsonDecode(utf8.decode(z.findFile('manifest.json')!.readBytes()!)) as Map;
      m['format_version'] = backupFormatVersion + 1;
      final n = Archive()
        ..add(ArchiveFile.string('manifest.json', jsonEncode(m)))
        ..add(ArchiveFile.bytes('data.db', z.findFile('data.db')!.readBytes()!));
      refused(write('newer.storilex', n), 'newer_version');
    });

    test('a changed database (checksum does not match)', () {
      final z = goodArchive();
      final data = z.findFile('data.db')!.readBytes()!.toList();
      data[data.length ~/ 2] ^= 0xff;
      final n = Archive()
        ..add(ArchiveFile.bytes('manifest.json', z.findFile('manifest.json')!.readBytes()!))
        ..add(ArchiveFile.bytes('data.db', data));
      refused(write('changed.storilex', n), 'checksum');
    });

    test('a database without the learner tables', () {
      final tmp = File(p.join(root.path, 'empty.db'));
      sqlite3.open(tmp.path)
        ..execute('CREATE TABLE x(a)')
        ..close();
      final bytes = tmp.readAsBytesSync();
      final m = {'format': backupFormat, 'format_version': backupFormatVersion, 'data_sha256': sha256.convert(bytes).toString()};
      final n = Archive()
        ..add(ArchiveFile.string('manifest.json', jsonEncode(m)))
        ..add(ArchiveFile.bytes('data.db', bytes));
      refused(write('notables.storilex', n), 'incomplete');
    });

    test('a picture path that leaves the app folder', () {
      final z = goodArchive();
      z.add(ArchiveFile.bytes('books/../../evil.txt', [1]));
      refused(write('escape.storilex', z), 'not_backup');
      expect(File(p.join(root.path, 'evil.txt')).existsSync(), isFalse);
    });
  });

  test('a safety copy is taken first, and undo brings the device back to how it was', () {
    final u = device(a);
    exportBackup(u, out('x.storilex'));
    final v = UserDb.open(b);
    ReviewStore(v);
    StatsStore(v);
    v.setWord('cloud', WordStatus.learning);
    v.setSetting('ai_key_openai', 'sk-local');
    final pv = inspectBackup(v, out('x.storilex'));
    restoreBackup(v, pv);
    pv.dispose();
    expect(Directory(p.join(b.path, 'backups')).listSync().whereType<File>().where((f) => f.path.endsWith('.db')), isNotEmpty);
    expect(v.statuses.keys, containsAll(['cloud', 'rain']));

    expect(undoLastRestore(v), isTrue);
    expect(v.statuses.keys.toList(), ['cloud']);
    expect(v.books(), isEmpty);
    expect(Directory(p.join(b.path, 'books')).existsSync() && Directory(p.join(b.path, 'books')).listSync().isNotEmpty, isFalse,
        reason: 'pictures added by the restore are removed again');
    expect(v.getSetting('ai_key_openai'), 'sk-local');
    expect(undoLastRestore(v), isFalse, reason: 'there is nothing left to undo');
  });

  test('a failure in the middle of a restore leaves the device as it was', () {
    final u = device(a);
    exportBackup(u, out('x.storilex'));
    final v = UserDb.open(b);
    v.setWord('cloud', WordStatus.learning);
    final pv = inspectBackup(v, out('x.storilex'));
    expect(() => restoreBackup(v, pv, debugFailAfterWrites: true), throwsA(isA<StateError>()));
    pv.dispose();
    expect(v.db.select('SELECT lemma FROM words').map((r) => r['lemma']).toList(), ['cloud']);
    expect(v.books(), isEmpty);
    expect(Directory(p.join(b.path, 'books')).existsSync() && Directory(p.join(b.path, 'books')).listSync().isNotEmpty, isFalse);
  });

  group('merge conflicts are never decided silently', () {
    late UserDb u, v;
    late int localBook;
    setUp(() {
      u = device(a);
      exportBackup(u, out('x.storilex'));
      // The second device has the same book, read again from the start.
      v = UserDb.open(b);
      ReviewStore(v);
      StatsStore(v);
      localBook = v.insertBook(sampleBook(images: {'cover.png': [1, 2, 3, 4]}));
      v.saveProgress(localBook, 0, 1);
      v.db.execute('INSERT INTO reading_time(day, book_id, seconds) VALUES (?,?,?)', ['2026-11-15', localBook, 60]);
      // and knows "rain" already, but went back to learning "garden".
      v.setWord('rain', WordStatus.learned);
      v.setWord('garden', WordStatus.learning);
    });

    test('the preview names each book whose position differs, with when each side last read it', () {
      final pv = inspectBackup(v, out('x.storilex'));
      final c = pv.bookConflicts.single;
      expect(c.title, 'The Garden');
      expect((c.local.chapter, c.local.para), (0, 1));
      expect((c.backup.chapter, c.backup.para), (1, 3));
      expect(c.local.lastRead, '2026-11-15');
      expect(c.backup.lastRead, '2026-11-10');
      expect(pv.wordConflicts.map((w) => w.lemma).toSet(), {'rain', 'garden'});
      pv.dispose();
    });

    test('without a choice the position and the words on this device are kept', () {
      final pv = inspectBackup(v, out('x.storilex'));
      final r = restoreBackup(v, pv);
      pv.dispose();
      final book = v.books().single;
      expect(book.id, localBook, reason: 'the same book is not added twice');
      expect((book.lastChapter, book.lastParagraph), (0, 1));
      expect(v.statuses['rain'], WordStatus.learned);
      expect(v.statuses['garden'], WordStatus.learning);
      expect(r.booksKeptLocal, 1);
      expect(r.wordsKeptLocal, 2);
      // Stats of the matched book are joined, not doubled.
      final days = v.db.select('SELECT day FROM reading_time WHERE book_id=? ORDER BY day', [localBook]).map((r) => r['day']);
      expect(days, ['2026-11-10', '2026-11-15']);
    });

    test('the learner can take the position and the words from the backup', () {
      final pv = inspectBackup(v, out('x.storilex'));
      restoreBackup(v, pv,
          bookChoices: {pv.bookConflicts.single.key: ConflictChoice.useBackup}, wordChoice: ConflictChoice.useBackup);
      pv.dispose();
      final book = v.books().single;
      expect((book.lastChapter, book.lastParagraph), (1, 3));
      expect(v.statuses['rain'], WordStatus.learning);
      expect(v.statuses['garden'], WordStatus.learned);
      expect(v.db.select('SELECT reps FROM review WHERE lemma=?', ['rain']).first['reps'], 3,
          reason: 'the review card comes with the word');
    });
  });

  test('replace mode needs a backup with the book texts, and keeps the keys of this device', () {
    final u = device(a);
    exportBackup(u, out('lite.storilex'), includeBooks: false);
    exportBackup(u, out('full.storilex'));
    final v = UserDb.open(b);
    v.setSetting('ai_key_openai', 'sk-local');
    v.setSetting('tts_rtf_kokoro', '1.5');
    v.setWord('cloud', WordStatus.learning);

    final lite = inspectBackup(v, out('lite.storilex'));
    expect(() => restoreBackup(v, lite, mode: RestoreMode.replace),
        throwsA(isA<BackupException>().having((e) => e.code, 'code', 'replace_needs_books')));
    lite.dispose();

    final full = inspectBackup(v, out('full.storilex'));
    restoreBackup(v, full, mode: RestoreMode.replace);
    full.dispose();
    expect(v.statuses.keys.toSet(), {'rain', 'garden'});
    expect(v.getSetting('prefs'), isNotNull);
    expect(v.getSetting('ai_key_openai'), 'sk-local');
    expect(v.getSetting('tts_rtf_kokoro'), '1.5');
    expect(v.books().single.lastChapter, 1);
  });

  test('without book texts, unknown books wait for the learner to add them again', () {
    final u = device(a);
    exportBackup(u, out('lite.storilex'), includeBooks: false);
    final v = UserDb.open(b);
    final pv = inspectBackup(v, out('lite.storilex'));
    final r = restoreBackup(v, pv);
    pv.dispose();
    expect(v.books(), isEmpty);
    expect(r.booksWaiting, 1);
    final w = v.db.select('SELECT title, last_chapter, last_para FROM backup_pending_books').single;
    expect([w['title'], w['last_chapter'], w['last_para']], ['The Garden', 1, 3]);
  });

  test('a backup from an older database (fewer columns) still restores', () {
    final u = device(a);
    exportBackup(u, out('x.storilex'));
    // Make the backup look like it came from before "lang" and "last_page".
    final z = ZipDecoder().decodeBytes(out('x.storilex').readAsBytesSync());
    final tmp = File(p.join(root.path, 'old.db'))..writeAsBytesSync(z.findFile('data.db')!.readBytes()!);
    sqlite3.open(tmp.path)
      ..execute('ALTER TABLE books DROP COLUMN lang')
      ..execute('ALTER TABLE books DROP COLUMN last_page')
      ..execute('DROP TABLE read_para')
      ..close();
    final bytes = tmp.readAsBytesSync();
    final m = jsonDecode(utf8.decode(z.findFile('manifest.json')!.readBytes()!)) as Map;
    m['data_sha256'] = sha256.convert(bytes).toString();
    final n = Archive()
      ..add(ArchiveFile.string('manifest.json', jsonEncode(m)))
      ..add(ArchiveFile.bytes('data.db', bytes));
    for (final f in z.files.where((f) => f.name.startsWith('books/'))) {
      n.add(ArchiveFile.bytes(f.name, f.readBytes()!));
    }
    out('old.storilex').writeAsBytesSync(ZipEncoder().encodeBytes(n));

    final v = UserDb.open(b);
    final pv = inspectBackup(v, out('old.storilex'));
    restoreBackup(v, pv);
    pv.dispose();
    expect(v.books().single.title, 'The Garden');
    expect(v.statuses['rain'], WordStatus.learning);
  });

  group('large files are read from disk, and a zip bomb is refused before anything is unpacked', () {
    late UserDb v;
    late File db;
    setUp(() {
      v = device(b);
      db = File(p.join(b.path, 'user.db'));
      v.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    });

    void refused(File f, String code, {BackupLimits limits = const BackupLimits()}) {
      final before = fileSha(db);
      final tmpBefore = Directory.systemTemp.listSync().where((d) => p.basename(d.path).startsWith('storilex_restore')).length;
      expect(() => inspectBackup(v, f, limits: limits), failsWith(code));
      v.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      expect(fileSha(db), before);
      final tmpAfter = Directory.systemTemp.listSync().where((d) => p.basename(d.path).startsWith('storilex_restore')).length;
      expect(tmpAfter, tmpBefore, reason: 'no unpacked folder is left behind');
    }

    test('a normal illustrated library (200 pictures, 10 MB) passes the default limits and comes back whole', () {
      final u = UserDb.open(a);
      final rnd = List<int>.generate(50 * 1024, (i) => (i * 7919 + i ~/ 3) & 0xff);
      final images = {for (var i = 0; i < 200; i++) 'pic$i.png': [...rnd, i & 0xff, i >> 8]};
      final id = u.insertBook(sampleBook(title: 'Atlas', images: images));
      exportBackup(u, out('big.storilex'));
      final w = UserDb.open(Directory(p.join(root.path, 'c'))..createSync());
      final pv = inspectBackup(w, out('big.storilex'));
      restoreBackup(w, pv);
      pv.dispose();
      final mine = pictures(a), theirs = pictures(Directory(p.join(root.path, 'c')));
      expect(mine.length, greaterThanOrEqualTo(200));
      expect(theirs.values.toSet(), mine.values.toSet());
      expect(w.books().single.title, 'Atlas');
      expect(id, greaterThan(0));
    });

    test('one file larger than allowed', () {
      exportBackup(device(a), out('x.storilex'));
      refused(out('x.storilex'), 'too_large', limits: const BackupLimits(maxEntryBytes: 1000));
    });

    test('all files together larger than allowed', () {
      exportBackup(device(a), out('x.storilex'));
      refused(out('x.storilex'), 'too_large', limits: const BackupLimits(maxTotalBytes: 2000));
    });

    test('too many files', () {
      exportBackup(device(a), out('x.storilex'));
      refused(out('x.storilex'), 'too_large', limits: const BackupLimits(maxEntries: 2));
    });

    test('a file that unpacks to more than its header says', () {
      // 1 MB of zeros, packed to about 1 KB, with headers that claim 100 bytes.
      final zeros = List<int>.filled(1024 * 1024, 0);
      final m = {'format': backupFormat, 'format_version': backupFormatVersion, 'data_sha256': sha256.convert(zeros).toString()};
      final bytes = ZipEncoder().encodeBytes(Archive()
        ..add(ArchiveFile.string('manifest.json', jsonEncode(m)))
        ..add(ArchiveFile.bytes('data.db', zeros)));
      final z = Uint8List.fromList(bytes);
      final bd = ByteData.sublistView(z);
      var patched = 0;
      for (var i = 0; i + 46 < z.length; i++) {
        final sig = bd.getUint32(i, Endian.little);
        if (sig == 0x04034b50 && utf8.decode(z.sublist(i + 30, i + 30 + bd.getUint16(i + 26, Endian.little)), allowMalformed: true) == 'data.db') {
          bd.setUint32(i + 22, 100, Endian.little);
          patched++;
        }
        if (sig == 0x02014b50 && utf8.decode(z.sublist(i + 46, i + 46 + bd.getUint16(i + 28, Endian.little)), allowMalformed: true) == 'data.db') {
          bd.setUint32(i + 24, 100, Endian.little);
          patched++;
        }
      }
      expect(patched, 2);
      final before = fileSha(db);
      expect(() => inspectBackup(v, out('liar.storilex')..writeAsBytesSync(z)), throwsA(isA<BackupException>()));
      v.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
      expect(fileSha(db), before);
    });

    test('the same name twice', () {
      final f = exportBackup(device(a), out('x.storilex'));
      final z = ZipDecoder().decodeBytes(f.readAsBytesSync());
      // Archive keeps one entry per name, so the zip is written entry by entry.
      final o = OutputMemoryStream();
      final enc = ZipEncoder()..startEncode(o);
      for (final e in z.files) {
        enc.add(ArchiveFile.bytes(e.name, e.readBytes()!));
      }
      enc.add(ArchiveFile.bytes('data.db', [1, 2, 3]));
      enc.endEncode();
      final names = ZipDirectory().headers(InputMemoryStream(o.getBytes()), files: false).map((h) => h.filename);
      expect(names.where((n) => n == 'data.db').length, 2);
      refused(out('twice.storilex')..writeAsBytesSync(o.getBytes()), 'not_backup');
    });
  });

  group('a failed restore always puts the database and the pictures back', () {
    late UserDb v;
    late String data;
    late Map<String, String> pics;
    setUp(() {
      exportBackup(device(a), out('x.storilex'));
      // The second device has a book of its own, with a picture.
      v = UserDb.open(b);
      ReviewStore(v);
      StatsStore(v);
      v.insertBook(sampleBook(title: 'Local', images: {'local.png': [9, 9, 9]}));
      v.setWord('cloud', WordStatus.learning);
      v.setSetting('ai_key_openai', 'sk-local');
      data = snapshot(v);
      pics = pictures(b);
      expect(pics, isNotEmpty);
    });

    void same() {
      expect(snapshot(v), data);
      expect(pictures(b), pics);
      expect(v.statuses.keys.toList(), ['cloud']);
    }

    void fails(RestoreMode mode, bool Function(String step) at, Matcher error) {
      debugRestoreStep = (s) {
        if (at(s)) throw FileSystemException('disk full', s);
      };
      final pv = inspectBackup(v, out('x.storilex'));
      expect(() => restoreBackup(v, pv, mode: mode), error);
      pv.dispose();
      debugRestoreStep = null;
    }

    test('merge: copying a picture of a new book fails', () {
      fails(RestoreMode.merge, (s) => s.startsWith('copy '), throwsA(isA<FileSystemException>()));
      same();
      expect(journals(b), isEmpty, reason: 'no safety copy is left as an undo point');
      expect(undoLastRestore(v), isFalse);
    });

    test('merge: a folder left over from a deleted book is moved aside and comes back unchanged', () {
      final stale = File(p.join(b.path, 'books', '2', 'old.png'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([5, 5]);
      pics = pictures(b);
      fails(RestoreMode.merge, (s) => s.startsWith('copy '), throwsA(isA<FileSystemException>()));
      same();
      expect(stale.readAsBytesSync(), [5, 5]);
    });

    test('replace: moving the old picture folder away fails', () {
      fails(RestoreMode.replace, (s) => s == 'move books', throwsA(isA<FileSystemException>()));
      same();
      expect(journals(b), isEmpty);
    });

    test('replace: copying the new pictures fails after the old folder was moved away', () {
      fails(RestoreMode.replace, (s) => s.startsWith('copy '), throwsA(isA<FileSystemException>()));
      same();
      expect(Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>(), isEmpty,
          reason: 'the moved folder went back to its place');
    });

    test('the database fails after the pictures were copied', () {
      final pv = inspectBackup(v, out('x.storilex'));
      expect(() => restoreBackup(v, pv, mode: RestoreMode.replace, debugFailAfterWrites: true), throwsA(isA<StateError>()));
      pv.dispose();
      same();
    });

    test('when putting a folder back fails too, nothing is deleted and it is tried again later', () {
      fails(RestoreMode.replace, (s) => s.startsWith('copy ') || s.startsWith('undo move'), failsWith('rollback_incomplete'));
      expect(snapshot(v), data, reason: 'the database is rolled back either way');
      final moved = Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>().single;
      expect(moved.listSync(recursive: true).whereType<File>(), isNotEmpty, reason: 'the old pictures are kept');
      expect(undoLastRestore(v), isFalse, reason: 'an unfinished restore is not an undo point');
      // undoLastRestore ran the recovery, which put the folder back.
      same();
      expect(journals(b), isEmpty);
    });

    test('the app closed in the middle of a restore: the next start puts everything back', () {
      debugRestoreStep = (s) {
        if (s.startsWith('copy ')) throw const BackupDebugCrash();
      };
      final pv = inspectBackup(v, out('x.storilex'));
      expect(() => restoreBackup(v, pv, mode: RestoreMode.replace), throwsA(isA<BackupDebugCrash>()));
      pv.dispose();
      debugRestoreStep = null;
      expect(pictures(b), isNot(pics), reason: 'the folder is half replaced when the app stops');
      v.db.close(); // the open transaction is lost, as when the app is closed
      v = UserDb.open(b);
      expect(recoverInterruptedRestore(v), isTrue);
      same();
      expect(journals(b), isEmpty);
      expect(undoLastRestore(v), isFalse);
    });

    test('the app closed right after the restore was saved: it is kept and can be undone', () {
      final pv = inspectBackup(v, out('x.storilex'));
      restoreBackup(v, pv);
      pv.dispose();
      final restored = snapshot(v);
      // As if the journal had not been marked finished yet.
      final j = File(p.join(b.path, 'backups', journals(b).firstWhere((n) => n.endsWith('.json'))));
      final m = jsonDecode(j.readAsStringSync()) as Map..['state'] = 'pending';
      j.writeAsStringSync(jsonEncode(m));
      expect(recoverInterruptedRestore(v), isTrue);
      expect(snapshot(v), restored, reason: 'a finished restore is not taken back by the recovery');
      expect(undoLastRestore(v), isTrue);
      same();
    });
  });

  group('safety copies and undo points', () {
    test('the safety copy holds no API key, and undo keeps the key the device has now', () {
      exportBackup(device(a), out('x.storilex'));
      final v = UserDb.open(b);
      v.setSetting('ai_key_openai', 'sk-local-OLDKEY-123');
      v.setSetting('api_key', 'sk-local-OLDKEY-123');
      v.setWord('cloud', WordStatus.learning);
      final pv = inspectBackup(v, out('x.storilex'));
      final r = restoreBackup(v, pv);
      pv.dispose();
      final bytes = File(r.safetyCopy).readAsBytesSync();
      expect(latin1.decode(bytes, allowInvalid: true).contains('OLDKEY'), isFalse);
      v.setSetting('ai_key_openai', 'sk-local-NEWKEY-456');
      expect(undoLastRestore(v), isTrue);
      expect(v.getSetting('ai_key_openai'), 'sk-local-NEWKEY-456');
      expect(v.getSetting('api_key'), 'sk-local-OLDKEY-123');
      expect(v.statuses.keys.toList(), ['cloud']);
    });

    test('a failed restore leaves no undo point, even when its journal cannot be deleted', () {
      exportBackup(device(a), out('x.storilex'));
      final v = UserDb.open(b);
      v.setWord('cloud', WordStatus.learning);
      debugRestoreStep = (s) {
        if (s.startsWith('copy ') || s == 'discard') throw const FileSystemException('denied');
      };
      final pv = inspectBackup(v, out('x.storilex'));
      expect(() => restoreBackup(v, pv), throwsA(isA<FileSystemException>()));
      pv.dispose();
      debugRestoreStep = null;
      expect(journals(b).where((n) => n.endsWith('.db')), isEmpty, reason: 'its safety copy is removed');
      final j = File(p.join(b.path, 'backups', journals(b).single));
      expect((jsonDecode(j.readAsStringSync()) as Map)['state'], 'failed');
      v.setWord('sky', WordStatus.learning);
      expect(undoLastRestore(v), isFalse);
      expect(v.statuses.keys.toSet(), {'cloud', 'sky'}, reason: 'work done after the failure is not taken back');
    });

    test('only the newest restore can be undone, and only once', () {
      exportBackup(device(a), out('x.storilex'));
      final u2 = UserDb.open(Directory(p.join(root.path, 'c'))..createSync());
      u2.setWord('moon', WordStatus.learned);
      exportBackup(u2, out('y.storilex'));
      final v = UserDb.open(b);
      v.setWord('cloud', WordStatus.learning);
      for (final f in ['x.storilex', 'y.storilex']) {
        final pv = inspectBackup(v, out(f));
        restoreBackup(v, pv);
        pv.dispose();
      }
      expect(v.statuses.keys.toSet(), {'cloud', 'rain', 'garden', 'moon'});
      expect(undoLastRestore(v), isTrue);
      expect(v.statuses.keys.toSet(), {'cloud', 'rain', 'garden'});
      expect(undoLastRestore(v), isFalse, reason: 'the earlier restore was followed by another one');
      expect(v.statuses.keys.toSet(), {'cloud', 'rain', 'garden'});
    });
  });

  group('undo can stop at any step and be run again without losing data', () {
    late UserDb v;
    late String before, after;
    late Map<String, String> picsBefore, picsAfter;

    void restore(RestoreMode mode) {
      final pv = inspectBackup(v, out('x.storilex'));
      restoreBackup(v, pv, mode: mode);
      pv.dispose();
      after = snapshot(v);
      picsAfter = pictures(b);
      expect(after, isNot(before));
      expect(picsAfter, isNot(picsBefore));
    }

    setUp(() {
      exportBackup(device(a), out('x.storilex'));
      v = UserDb.open(b);
      ReviewStore(v);
      StatsStore(v);
      v.insertBook(sampleBook(title: 'Local', images: {'local.png': [9, 9, 9]}));
      v.setWord('cloud', WordStatus.learning);
      before = snapshot(v);
      picsBefore = pictures(b);
      restore(RestoreMode.replace);
    });

    void isBefore() {
      expect(snapshot(v), before);
      expect(pictures(b), picsBefore);
    }

    void isAfter() {
      expect(snapshot(v), after);
      expect(pictures(b), picsAfter);
    }

    void failAt(bool Function(String s) at, String code) {
      debugRestoreStep = (s) {
        if (at(s)) throw FileSystemException('denied', s);
      };
      expect(() => undoLastRestore(v), failsWith(code));
      debugRestoreStep = null;
    }

    void crashAt(String step) {
      debugRestoreStep = (s) {
        if (s == step) throw const BackupDebugCrash();
      };
      expect(() => undoLastRestore(v), throwsA(isA<BackupDebugCrash>()));
      debugRestoreStep = null;
      v.db.close(); // as when the app is closed: an open transaction is lost
      v = UserDb.open(b);
    }

    /// Every picture file there was, before or after the restore, is still somewhere in the app folder.
    void nothingDeleted() {
      final all = {
        for (final f in b.listSync(recursive: true).whereType<File>())
          if (!p.basename(f.path).endsWith('.db') && !f.path.endsWith('.json')) fileSha(f)
      };
      expect(all, containsAll({...picsBefore.values, ...picsAfter.values}));
    }

    test('a picture folder cannot be moved back: nothing changes, and the undo can be tried again', () {
      failAt((s) => s == 'undo move books', 'undo_failed');
      isAfter();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('the database step fails: the folders are moved back, and the undo can be tried again', () {
      failAt((s) => s == 'undo database', 'undo_failed');
      isAfter();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('moving the folders back fails too: nothing is deleted, the database is untouched, and the next try finishes', () {
      failAt((s) => s == 'undo move books' || s.startsWith('reverse '), 'rollback_incomplete');
      expect(snapshot(v), after);
      nothingDeleted();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('the app closes while the folders are moved: the next start puts the restore back, then undo works', () {
      crashAt('undo move books');
      expect(recoverInterruptedRestore(v), isTrue);
      isAfter();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('the app closes before the database step is saved: the next start puts the restore back, then undo works', () {
      crashAt('undo database');
      expect(recoverInterruptedRestore(v), isTrue);
      isAfter();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('the app closes after the database step was saved: the next start finishes the undo, and it is not run again', () {
      crashAt('undo finish');
      expect(recoverInterruptedRestore(v), isTrue);
      isBefore();
      expect(journals(b), isEmpty);
      v.setWord('sky', WordStatus.learning);
      final now = snapshot(v);
      expect(undoLastRestore(v), isFalse);
      expect(snapshot(v), now, reason: 'work done after the undo is kept');
      expect(pictures(b), picsBefore);
    });

    test('running the same undo a second time changes nothing, even after new books were added', () {
      expect(undoLastRestore(v), isTrue);
      isBefore();
      v.setWord('sky', WordStatus.learning);
      v.insertBook(sampleBook(title: 'New', images: {'new.png': [7, 7]}));
      final now = snapshot(v), pics = pictures(b);
      expect(undoLastRestore(v), isFalse);
      expect(recoverInterruptedRestore(v), isFalse);
      expect(snapshot(v), now);
      expect(pictures(b), pics);
    });

    test('merge: a book added after the undo keeps its pictures, even in a folder the restore had used', () {
      expect(undoLastRestore(v), isTrue);
      final pv = inspectBackup(v, out('x.storilex'));
      restoreBackup(v, pv); // adds "The Garden" with its pictures in a new folder
      pv.dispose();
      final used = pictures(b).keys.toSet().difference(picsBefore.keys.toSet());
      expect(used, isNotEmpty);
      failAt((s) => s.startsWith('undo create'), 'undo_failed');
      expect(undoLastRestore(v), isTrue);
      isBefore();
      // The next book may get the same id, and so the same folder.
      v.insertBook(sampleBook(title: 'New', images: {'new.png': [7, 7]}));
      final pics = pictures(b);
      expect(undoLastRestore(v), isFalse);
      expect(pictures(b), pics);
      expect(v.books().map((x) => x.title), contains('New'));
    });

    // ---- the app closes after a folder move was written to the journal, before the move

    test('closed after the first move was journaled, before it was made: the folders are as restored, then undo works', () {
      crashAt('undo create books');
      expect(Directory(p.join(b.path, 'books')).existsSync(), isTrue, reason: 'the move never happened');
      expect(Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('undo-')),
          isEmpty);
      expect(recoverInterruptedRestore(v), isTrue);
      isAfter();
      expect(journals(b).length, 2, reason: 'the restore is still the undo point');
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('closed after the second move was journaled, before it was made: the first is moved back, the second skipped', () {
      crashAt('undo move books');
      // The first move (the restore's pictures into the bin) happened, the second did not.
      expect(Directory(p.join(b.path, 'books')).existsSync(), isFalse);
      final moved = Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>().map((d) => p.basename(d.path)).toSet();
      expect(moved.any((n) => n.startsWith('books-before-restore-')), isTrue);
      expect(moved.any((n) => n.startsWith('undo-')), isTrue);
      expect(recoverInterruptedRestore(v), isTrue);
      isAfter();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('a folder appeared where one must be moved back: nothing is deleted or overwritten, and new restores wait', () {
      crashAt('undo move books');
      final stray = File(p.join(b.path, 'books', 'stray.png'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([4, 2]);
      recoverInterruptedRestore(v);
      expect(stray.readAsBytesSync(), [4, 2]);
      nothingDeleted();
      expect(snapshot(v), after, reason: 'the database is not touched');
      expect(() => undoLastRestore(v), failsWith('rollback_incomplete'));
      final pv = inspectBackup(v, out('x.storilex'));
      expect(() => restoreBackup(v, pv, mode: RestoreMode.replace), failsWith('rollback_incomplete'));
      pv.dispose();
      expect(stray.readAsBytesSync(), [4, 2]);
      nothingDeleted();
      // Once the stray folder is out of the way, the recovery finishes.
      Directory(p.join(b.path, 'books')).renameSync(p.join(root.path, 'stray'));
      expect(recoverInterruptedRestore(v), isTrue);
      isAfter();
      expect(undoLastRestore(v), isTrue);
      isBefore();
    });

    test('a folder to move back is gone: the database is not touched, and nothing else is deleted', () {
      crashAt('undo move books');
      final bin = Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>().firstWhere((d) => p.basename(d.path).startsWith('undo-'));
      bin.deleteSync(recursive: true); // removed outside the app
      recoverInterruptedRestore(v);
      expect(snapshot(v), after);
      for (final sha in picsBefore.values) {
        expect(b.listSync(recursive: true).whereType<File>().map(fileSha), contains(sha), reason: 'the old pictures are kept');
      }
      expect(() => undoLastRestore(v), failsWith('rollback_incomplete'));
      expect(snapshot(v), after);
    });

    // ---- the app closes while cleaning up, after the database was put back

    for (final step in ['undo finish', 'undo finish journal']) {
      test('closed at "$step": the next start finishes the clean-up without putting the database back again', () {
        crashAt(step);
        if (step == 'undo finish journal') {
          expect(Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('undo-')),
              isEmpty, reason: 'the bin was emptied, the journal was not removed yet');
        }
        expect(journals(b).any((n) => n.endsWith('.json')), isTrue);
        isBefore();
        // The learner keeps working before the clean-up runs.
        v.setWord('sky', WordStatus.learning);
        v.insertBook(sampleBook(title: 'New', images: {'new.png': [7, 7]}));
        final now = snapshot(v), pics = pictures(b);
        expect(recoverInterruptedRestore(v), isTrue);
        expect(snapshot(v), now, reason: 'the database is not put back a second time');
        expect(pictures(b), pics);
        expect(journals(b), isEmpty, reason: 'the journal and the safety copy are gone');
        expect(undoLastRestore(v), isFalse);
        expect(snapshot(v), now);
        expect(pictures(b), pics);
        expect(Directory(p.join(b.path, 'backups')).listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('undo-')),
            isEmpty);
      });
    }
  });
}
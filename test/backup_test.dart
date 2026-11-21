// The backup file (.storilex): what goes in, what never goes in, and that a
// restore keeps the learner's data safe. A bad file never touches the data on
// the device, a restore can be undone, and a merge never moves a reading
// position or a word on its own when the two devices disagree.
import 'dart:convert';
import 'dart:io';

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

void main() {
  late Directory root;
  late Directory a, b;
  setUp(() {
    root = Directory.systemTemp.createTempSync('storilex_backup');
    a = Directory(p.join(root.path, 'a'))..createSync();
    b = Directory(p.join(root.path, 'b'))..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

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
}

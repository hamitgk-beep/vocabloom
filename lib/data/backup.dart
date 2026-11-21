import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'review.dart';
import 'stats.dart';
import 'user_db.dart';

/// The learner's backup file (`.storilex`): a zip with `manifest.json`, a
/// snapshot of `user.db` as `data.db` and, when the book texts are in it, the
/// books' pictures under `books/<id>/`. The same file opens on every platform.
///
/// API keys and settings that only fit one device are never written into it.
/// A restore checks the whole file first, takes a safety copy of the data on
/// the device, and changes the database in one transaction. When the two
/// devices disagree (a book read again from the start, a word moved back to
/// "To learn"), nothing is decided silently: the device keeps its own data
/// unless the learner picks the backup's.
const backupFormat = 'storilex-backup';

/// Raise when the file layout changes; older apps then refuse newer files.
const backupFormatVersion = 1;

const backupExtension = 'storilex';

/// Why a backup was refused. [code] is one of: `not_backup` (not a Storilex
/// backup, or an entry that would leave the app folder), `newer_version`,
/// `checksum`, `corrupt`, `incomplete`, `too_large` (over [BackupLimits]),
/// `replace_needs_books`, `rollback_incomplete` (a failed restore or an undo
/// could not put every picture folder back; nothing was deleted, and
/// [recoverInterruptedRestore] tries again).
class BackupException implements Exception {
  final String code;
  final String detail;
  const BackupException(this.code, [this.detail = '']);

  @override
  String toString() => 'BackupException($code)${detail.isEmpty ? '' : ': $detail'}';
}

/// API keys: never in a backup, never replaced by one.
bool isSecretSetting(String key) => key == 'api_key' || key.startsWith('ai_key_');

/// Settings that describe this device, not the learner: the measured speed of
/// the phone, voice packs removed here, one-time text repairs already run on
/// this database, the state of the on-device translation package.
bool isDeviceSetting(String key) =>
    key == 'tts_rtf_kokoro' ||
    key.startsWith('tts_removed_') ||
    key.startsWith('repair_') ||
    key == 'mt_tr_ready' ||
    key == 'mt_tr_trying';

bool _staysOnDevice(String key) => isSecretSetting(key) || isDeviceSetting(key);

/// The learner's tables, in the order a restore fills them.
const _tables = [
  'words', 'review', 'activity', 'books', 'chapters', 'paras', 'reading_time', 'read_para', 'lookup_log', 'review_log',
  'grammar_attempt', 'expr_detail', 'sentence_ai', 'wfam_ai', 'expr_ai', 'missing_tr', 'ctx_ai', 'sense_feedback',
  'ai_meaning', 'sense_help', 'settings', 'backup_pending_books',
];

/// Tables whose rows have their own key: rows already on the device stay.
const _keyedCaches = ['expr_detail', 'sentence_ai', 'wfam_ai', 'expr_ai', 'missing_tr', 'ctx_ai', 'sense_help', 'ai_meaning'];

/// Log tables with a running id: a row is added unless the same row is there.
const _logs = ['lookup_log', 'review_log', 'grammar_attempt', 'sense_feedback'];

// ------------------------------------------------------------------ size

/// Upper bounds in bytes, before compression (the zip is usually smaller).
class BackupEstimate {
  final int withBooks;
  final int withoutBooks;
  const BackupEstimate(this.withBooks, this.withoutBooks);
}

BackupEstimate estimateBackupSize(UserDb u) {
  final pages = u.db.select('PRAGMA page_count').first.columnAt(0) as int;
  final free = u.db.select('PRAGMA freelist_count').first.columnAt(0) as int;
  final size = u.db.select('PRAGMA page_size').first.columnAt(0) as int;
  final dbBytes = (pages - free) * size;
  final text = u.db.select('SELECT COALESCE(SUM(LENGTH(CAST(text AS BLOB)) + COALESCE(LENGTH(CAST(tr AS BLOB)), 0) + '
          'COALESCE(LENGTH(CAST(meta AS BLOB)), 0)), 0) AS n FROM paras')
      .first['n'] as int;
  var pictures = 0;
  for (final id in _bookIds(u.db, 'main')) {
    final d = Directory(p.join(u.dir, 'books', '$id'));
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      pictures += f.lengthSync();
    }
  }
  final without = dbBytes - text;
  return BackupEstimate(dbBytes + pictures, without < size ? size : without);
}

// ------------------------------------------------------------------ export

/// Writes a backup of [u] to [out] and returns it. [includeBooks] keeps the
/// book texts and pictures in it (the default), so books come back on a new
/// device without their files.
File exportBackup(UserDb u, File out, {bool includeBooks = true, String appVersion = '', int appBuild = 0}) {
  _ensureTables(u);
  final tmp = Directory.systemTemp.createTempSync('storilex_export');
  try {
    final dataPath = p.join(tmp.path, 'data.db');
    u.db.execute('VACUUM INTO ?', [dataPath]);
    final fingerprints = {for (final id in _bookIds(u.db, 'main')) id: bookFingerprint(u.db, 'main', id)};
    final counts = <String, int>{};
    final d = sqlite3.open(dataPath);
    try {
      // Deleted rows must not linger in free pages: secure_delete + VACUUM.
      d.execute('PRAGMA secure_delete=ON');
      for (final r in d.select('SELECT key FROM settings').toList()) {
        final k = r['key'] as String;
        if (_staysOnDevice(k)) d.execute('DELETE FROM settings WHERE key=?', [k]);
      }
      d.execute('CREATE TABLE backup_books(book_id INTEGER PRIMARY KEY, fingerprint TEXT, source TEXT)');
      for (final e in fingerprints.entries) {
        final src = d.select('SELECT source FROM books WHERE id=?', [e.key]).first['source'];
        d.execute('INSERT INTO backup_books VALUES (?,?,?)', [e.key, e.value, src]);
      }
      if (!includeBooks) d.execute('DELETE FROM paras');
      d.execute('DROP TABLE IF EXISTS $_restoreLog'); // which restores ran here: this device only
      for (final t in [..._tables, 'backup_books']) {
        if (_hasTable(d, 'main', t)) counts[t] = d.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int;
      }
      d.execute('VACUUM');
    } finally {
      d.close();
    }
    final manifest = {
      'format': backupFormat,
      'format_version': backupFormatVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
      'app_version': appVersion,
      'app_build': appBuild,
      'platform': Platform.operatingSystem,
      'includes_books': includeBooks,
      'counts': counts,
      'data_sha256': _sha256File(File(dataPath)),
    };
    // Written next to the target first, so a failed write leaves no half file.
    // Each entry streams from its file into the zip on disk; no file is held
    // whole in memory, however large the library is.
    final part = File('${out.path}.part');
    final zip = ZipFileEncoder()..create(part.path);
    try {
      zip.addArchiveFile(ArchiveFile.string('manifest.json', const JsonEncoder.withIndent(' ').convert(manifest)));
      _zipFile(zip, File(dataPath), 'data.db');
      if (includeBooks) {
        for (final id in fingerprints.keys) {
          final dir = Directory(p.join(u.dir, 'books', '$id'));
          if (!dir.existsSync()) continue;
          for (final f in dir.listSync(recursive: true).whereType<File>()) {
            _zipFile(zip, f, p.split(p.relative(f.path, from: u.dir)).join('/'));
          }
        }
      }
      zip.closeSync();
    } catch (_) {
      try {
        zip.closeSync();
      } catch (_) {}
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
    if (out.existsSync()) out.deleteSync();
    return part.renameSync(out.path);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void _zipFile(ZipFileEncoder zip, File f, String name) {
  final s = InputFileStream(f.path);
  try {
    zip.addArchiveFile(ArchiveFile.stream(name, s));
  } finally {
    s.closeSync();
  }
}

String _sha256File(File f) {
  Digest? d;
  final sink = sha256.startChunkedConversion(_DigestSink((x) => d = x));
  final raf = f.openSync();
  try {
    final buf = Uint8List(1 << 20);
    for (var n = raf.readIntoSync(buf); n > 0; n = raf.readIntoSync(buf)) {
      sink.add(Uint8List.sublistView(buf, 0, n));
    }
  } finally {
    raf.closeSync();
  }
  sink.close();
  return d.toString();
}

class _DigestSink implements Sink<Digest> {
  final void Function(Digest) _on;
  _DigestSink(this._on);
  @override
  void add(Digest d) => _on(d);
  @override
  void close() {}
}

/// Identifies a book by its text, so the same book imported again on another
/// device is found: title, author, format, chapter and paragraph count and
/// the first 20 text paragraphs.
String bookFingerprint(Database db, String schema, int id) {
  final b = db.select('SELECT title, author, format FROM $schema.books WHERE id=?', [id]).first;
  final chapters = db.select('SELECT COUNT(*) AS n FROM $schema.chapters WHERE book_id=?', [id]).first['n'];
  final paras = db.select("SELECT COUNT(*) AS n FROM $schema.paras WHERE book_id=? AND kind != 'i'", [id]).first['n'];
  final first = [
    for (final r in db.select("SELECT text FROM $schema.paras WHERE book_id=? AND kind != 'i' ORDER BY chapter, idx LIMIT 20", [id]))
      r['text']
  ];
  return sha256.convert(utf8.encode(jsonEncode([b['title'], b['author'], b['format'], chapters, paras, first]))).toString();
}

// ------------------------------------------------------------------ inspect

class BackupManifest {
  final int formatVersion;
  final String created;
  final String appVersion;
  final String platform;
  final bool includesBooks;
  final Map<String, int> counts;
  const BackupManifest(this.formatVersion, this.created, this.appVersion, this.platform, this.includesBooks, this.counts);
}

/// Where a book was left on one side, and the last day it was read there.
class BookPosition {
  final int chapter, para, page;
  final String? lastRead;
  const BookPosition(this.chapter, this.para, this.page, this.lastRead);
}

/// A book on both devices with different reading positions.
class BookConflict {
  final String key;
  final String title;
  final BookPosition local, backup;
  const BookConflict(this.key, this.title, this.local, this.backup);
}

/// A word on both devices with a different status.
class WordConflict {
  /// The stored key (`tr:` in front of Turkish words).
  final String key;
  final WordStatus local, backup;
  const WordConflict(this.key, this.local, this.backup);
  String get lemma => key.startsWith('tr:') ? key.substring(3) : key;
}

class _BackupBook {
  final int id;
  final String key;
  final int? localId;
  const _BackupBook(this.id, this.key, this.localId);
}

/// A checked backup, unpacked in a temporary folder, with what a restore
/// would do. Call [dispose] when done.
class BackupPreview {
  final BackupManifest manifest;
  final Map<String, String> backupSettings;
  final List<BookConflict> bookConflicts;
  final List<WordConflict> wordConflicts;
  final int newWords;
  final int newBooks;
  final int matchedBooks;

  /// Books whose text is not in the backup and not on this device.
  final int waitingBooks;
  final Directory _tmp;
  final List<_BackupBook> _books;
  BackupPreview._(this.manifest, this.backupSettings, this.bookConflicts, this.wordConflicts, this.newWords, this.newBooks,
      this.matchedBooks, this.waitingBooks, this._tmp, this._books);

  String get _dataPath => p.join(_tmp.path, 'data.db');

  void dispose() {
    try {
      if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Checks [file] completely and compares it with the data on [u]. Throws a
/// [BackupException] for a file that is not a sound, compatible backup;
/// nothing on the device is changed either way.
///
/// The file is read from disk as it is unpacked, never whole into memory.
/// Before anything is unpacked, the sizes the zip declares are checked
/// against [limits] (a "zip bomb" is refused with `too_large`), and while
/// unpacking no entry may grow past the size it declared.
BackupPreview inspectBackup(UserDb u, File file, {BackupLimits limits = const BackupLimits()}) {
  final InputFileStream input;
  try {
    input = InputFileStream(file.path);
  } catch (e) {
    throw BackupException('not_backup', '$e');
  }
  try {
    _checkEntries(input, limits);
    final Archive zip;
    try {
      zip = ZipDecoder().decodeStream(input, verify: true);
    } catch (e) {
      throw BackupException('not_backup', '$e');
    }
    final mf = zip.findFile('manifest.json');
    if (mf == null) throw const BackupException('not_backup', 'no manifest');
    final Map m;
    try {
      m = jsonDecode(utf8.decode(mf.readBytes() ?? const [])) as Map;
    } catch (e) {
      throw BackupException('not_backup', 'manifest: $e');
    }
    final version = m['format_version'];
    if (m['format'] != backupFormat || version is! int) throw const BackupException('not_backup', 'not a Storilex backup');
    if (version > backupFormatVersion) throw BackupException('newer_version', 'format $version');
    final data = zip.findFile('data.db');
    if (data == null || !data.isFile) throw const BackupException('incomplete', 'no data.db');

    final tmp = Directory.systemTemp.createTempSync('storilex_restore');
    try {
      final dataFile = File(p.join(tmp.path, 'data.db'));
      _unpack(data, dataFile);
      if (_sha256File(dataFile) != m['data_sha256']) throw const BackupException('checksum');
      for (final f in zip.files) {
        if (!f.isFile || !f.name.startsWith('books/')) continue;
        _unpack(f, File(p.joinAll([tmp.path, ...f.name.split('/')])));
      }
      return _preview(u, m, tmp);
    } catch (e) {
      tmp.deleteSync(recursive: true);
      rethrow;
    }
  } finally {
    input.closeSync();
  }
}

/// How much a backup may unpack to. The defaults are far above a real
/// library (a database with the texts of a few hundred books is some
/// hundred MB; an illustrated book some tens of MB), so only a file built to
/// fill the device is refused.
class BackupLimits {
  /// Files in the zip.
  final int maxEntries;

  /// One unpacked file (the database is the largest).
  final int maxEntryBytes;

  /// All files together, unpacked.
  final int maxTotalBytes;

  final int maxManifestBytes;
  const BackupLimits(
      {this.maxEntries = 50000,
      this.maxEntryBytes = 2 * 1024 * 1024 * 1024,
      this.maxTotalBytes = 4 * 1024 * 1024 * 1024,
      this.maxManifestBytes = 1024 * 1024});
}

/// Reads only the zip's table of contents: names, count and declared sizes.
void _checkEntries(InputStream input, BackupLimits l) {
  var count = 0, total = 0;
  final names = <String>{};
  try {
    for (final h in ZipDirectory().headers(input, verify: true, files: false)) {
      if (++count > l.maxEntries) throw BackupException('too_large', 'more than ${l.maxEntries} files');
      final name = h.filename, size = h.uncompressedSize;
      if (!_safeEntry(name) || !names.add(name)) throw BackupException('not_backup', 'bad entry $name');
      final max = name == 'manifest.json' ? l.maxManifestBytes : l.maxEntryBytes;
      if (size < 0 || size > max) throw BackupException('too_large', '$name: $size bytes');
      total += size;
      if (total > l.maxTotalBytes) throw BackupException('too_large', 'more than ${l.maxTotalBytes} bytes');
    }
  } on BackupException {
    rethrow;
  } catch (e) {
    throw BackupException('not_backup', '$e');
  }
  if (count == 0) throw const BackupException('not_backup', 'empty');
}

/// Streams one entry to [target]. The zip reader stops an entry at the size
/// it declared and checks its CRC, so a lying header cannot fill the disk.
void _unpack(ArchiveFile f, File target) {
  target.parent.createSync(recursive: true);
  final o = OutputFileStream(target.path);
  try {
    f.writeContent(o);
  } catch (e) {
    throw BackupException('corrupt', '${f.name}: $e');
  } finally {
    o.closeSync();
  }
}

/// Only the manifest, the database and pictures inside `books/<id>/`.
bool _safeEntry(String name) {
  if (name == 'manifest.json' || name == 'data.db') return true;
  if (name.startsWith('/') || name.contains('\\') || name.contains(':')) return false;
  final parts = name.split('/');
  if (parts.length > 1 && parts.last.isEmpty) parts.removeLast(); // a folder entry
  return parts.length >= 2 &&
      parts.first == 'books' &&
      int.tryParse(parts[1]) != null &&
      parts.every((s) => s.isNotEmpty && s != '.' && s != '..');
}

BackupPreview _preview(UserDb u, Map m, Directory tmp) {
  final Database bk;
  try {
    bk = sqlite3.open(p.join(tmp.path, 'data.db'), mode: OpenMode.readOnly);
  } catch (e) {
    throw BackupException('corrupt', '$e');
  }
  try {
    final List<String> check;
    try {
      check = [for (final r in bk.select('PRAGMA integrity_check')) '${r.columnAt(0)}'];
    } catch (e) {
      throw BackupException('corrupt', '$e');
    }
    if (check.length != 1 || check.single != 'ok') throw BackupException('corrupt', check.take(3).join('; '));
    for (final t in ['words', 'books', 'settings', 'backup_books']) {
      if (!_hasTable(bk, 'main', t)) throw BackupException('incomplete', 'no $t table');
    }
    final includesBooks = m['includes_books'] == true;
    final manifest = BackupManifest(m['format_version'] as int, '${m['created'] ?? ''}', '${m['app_version'] ?? ''}',
        '${m['platform'] ?? ''}', includesBooks, {
      for (final e in ((m['counts'] as Map?) ?? const {}).entries)
        if (e.value is int) '${e.key}': e.value as int
    });
    final settings = {
      for (final r in bk.select('SELECT key, value FROM settings'))
        if (!_staysOnDevice(r['key'] as String)) r['key'] as String: '${r['value'] ?? ''}'
    };

    // Words
    final local = {for (final r in u.db.select('SELECT lemma, status FROM words')) r['lemma'] as String: r['status'] as int};
    final wordConflicts = <WordConflict>[];
    var newWords = 0;
    for (final r in bk.select('SELECT lemma, status FROM words')) {
      final k = r['lemma'] as String, s = r['status'] as int;
      final l = local[k];
      if (l == null) {
        newWords++;
      } else if (l != s) {
        wordConflicts.add(WordConflict(k, WordStatus.values[l], WordStatus.values[s]));
      }
    }

    // Books: by free-library id first, then by text.
    final bySource = <String, int>{}, byPrint = <String, int>{};
    for (final id in _bookIds(u.db, 'main')) {
      final src = u.db.select('SELECT source FROM books WHERE id=?', [id]).first['source'] as String?;
      if (src != null) bySource[src] = id;
      byPrint[bookFingerprint(u.db, 'main', id)] = id;
    }
    final books = <_BackupBook>[];
    final conflicts = <BookConflict>[];
    var newBooks = 0, matched = 0, waiting = 0;
    final prints = {for (final r in bk.select('SELECT book_id, fingerprint FROM backup_books')) r['book_id'] as int: r['fingerprint'] as String};
    for (final r in bk.select('SELECT * FROM books ORDER BY id')) {
      final id = r['id'] as int, src = r['source'] as String?;
      final fp = prints[id] ?? '';
      final key = src != null ? 'src:$src' : 'fp:$fp';
      final lid = (src != null ? bySource[src] : null) ?? byPrint[fp];
      books.add(_BackupBook(id, key, lid));
      if (lid == null) {
        includesBooks ? newBooks++ : waiting++;
        continue;
      }
      matched++;
      final l = u.db.select('SELECT * FROM books WHERE id=?', [lid]).first;
      final lp = BookPosition(l['last_chapter'] as int? ?? 0, l['last_para'] as int? ?? 0, l['last_page'] as int? ?? 0, _lastRead(u.db, lid));
      final bp = BookPosition(r['last_chapter'] as int? ?? 0, r['last_para'] as int? ?? 0, r['last_page'] as int? ?? 0, _lastRead(bk, id));
      if ((lp.chapter, lp.para, lp.page) != (bp.chapter, bp.para, bp.page)) {
        conflicts.add(BookConflict(key, l['title'] as String? ?? '', lp, bp));
      }
    }
    return BackupPreview._(manifest, settings, conflicts, wordConflicts, newWords, newBooks, matched, waiting, tmp, books);
  } finally {
    bk.close();
  }
}

/// The last day the book was read, from the reading statistics.
String? _lastRead(Database db, int bookId) {
  final days = <String>[];
  for (final t in ['reading_time', 'read_para']) {
    if (!_hasTable(db, 'main', t)) continue;
    final d = db.select('SELECT MAX(day) AS d FROM $t WHERE book_id=?', [bookId]).first['d'];
    if (d is String) days.add(d);
  }
  days.sort();
  return days.isEmpty ? null : days.last;
}

// ------------------------------------------------------------------ restore

enum RestoreMode {
  /// Adds what is new; keeps this device's data where the two disagree,
  /// unless the learner picked the backup's. Settings are not changed.
  merge,

  /// Replaces the learner's data with the backup's. Needs a backup with the
  /// book texts. API keys and device settings stay.
  replace,
}

enum ConflictChoice { keepLocal, useBackup }

class RestoreResult {
  int wordsAdded = 0, wordsKeptLocal = 0, wordsFromBackup = 0;
  int booksAdded = 0, booksMatched = 0, booksKeptLocal = 0, booksFromBackup = 0, booksWaiting = 0;

  /// The copy of the data taken before the restore ([undoLastRestore]).
  String safetyCopy = '';
}

/// Restores [pv] into [u]. Conflicts not named in [bookChoices] (by
/// [BookConflict.key]) or covered by [wordChoice] keep this device's data.
///
/// Before anything changes, a safety copy of the data (without API keys) and
/// a journal are written to `backups/`. Every picture folder the restore
/// creates or moves is written into the journal before it happens, so a
/// failure, or the app being closed in the middle, can put each one back
/// ([recoverInterruptedRestore]). The database changes in one transaction
/// that also records the restore as finished; the journal becomes an undo
/// point ([undoLastRestore]) only then.
///
/// [debugFailAfterWrites] makes the restore fail after all its writes
/// (tests).
RestoreResult restoreBackup(UserDb u, BackupPreview pv,
    {RestoreMode mode = RestoreMode.merge,
    Map<String, ConflictChoice> bookChoices = const {},
    ConflictChoice wordChoice = ConflictChoice.keepLocal,
    bool debugFailAfterWrites = false}) {
  if (mode == RestoreMode.replace && !pv.manifest.includesBooks) throw const BackupException('replace_needs_books');
  if (!pv._tmp.existsSync()) throw StateError('the backup preview was disposed');
  _ensureTables(u);
  recoverInterruptedRestore(u);
  final res = RestoreResult();
  final j = _Journal.begin(u, mode);
  res.safetyCopy = j.copy.path;
  final db = u.db;
  var crashed = false;
  db.execute('ATTACH DATABASE ? AS bk', [pv._dataPath]);
  try {
    db.execute('BEGIN');
    try {
      if (mode == RestoreMode.replace) {
        _replace(u, pv, j);
      } else {
        _merge(u, pv, res, bookChoices, wordChoice, j);
      }
      db.execute('INSERT INTO main.$_restoreLog(id, mode, finished) VALUES (?,?,?)',
          [j.id, mode.name, DateTime.now().millisecondsSinceEpoch]);
      if (debugFailAfterWrites) throw StateError('restore failed on purpose');
      db.execute('COMMIT');
    } catch (e) {
      if (e is BackupDebugCrash) {
        crashed = true; // as if the app had been closed here: nothing is cleaned up
        rethrow;
      }
      try {
        if (!db.autocommit) db.execute('ROLLBACK');
      } catch (_) {}
      if (!_undoOps(u, j)) {
        throw BackupException('rollback_incomplete', 'the restore failed ($e) and not every picture folder could be put back');
      }
      j.discard();
      rethrow;
    }
  } finally {
    if (!crashed) db.execute('DETACH DATABASE bk');
  }
  try {
    j.finish();
  } catch (_) {
    // The data is restored; the journal says "pending" with the restore
    // recorded in the database, and recoverInterruptedRestore finishes it.
  }
  if (mode == RestoreMode.replace) {
    res.wordsAdded = db.select('SELECT COUNT(*) AS n FROM words').first['n'] as int;
    res.booksAdded = db.select('SELECT COUNT(*) AS n FROM books').first['n'] as int;
  }
  u.reloadStatuses();
  return res;
}

/// Finishes a restore the app was closed in the middle of, and is safe to
/// call at every start. When its transaction was committed, the restore is
/// kept and becomes the undo point; when not (the database already rolled it
/// back on its own), the picture folders are put back and its safety copy is
/// removed. True when there was something to do.
bool recoverInterruptedRestore(UserDb u) {
  var any = false;
  for (final j in _journals(u)) {
    if (j.state != 'pending') continue;
    any = true;
    final committed = _hasTable(u.db, 'main', _restoreLog) &&
        u.db.select('SELECT 1 FROM main.$_restoreLog WHERE id=?', [j.id]).isNotEmpty;
    if (committed) {
      j.finish();
    } else if (_undoOps(u, j)) {
      j.discard();
    }
  }
  return any;
}

/// Puts the data back the way it was before the last restore. False when
/// there is no restore to undo: only the newest restore can be undone, only
/// when it finished, and only once (a restore that failed, or one followed
/// by another restore, is never an undo point). API keys and device settings
/// stay as they are now.
bool undoLastRestore(UserDb u) {
  recoverInterruptedRestore(u);
  final js = _journals(u);
  if (js.isEmpty) return false;
  final j = js.first;
  if (j.state != 'done' || !j.copy.existsSync()) return false;
  final db = u.db;
  db.execute('ATTACH DATABASE ? AS sf', [j.copy.path]);
  try {
    db.execute('BEGIN');
    try {
      for (final t in _tables) {
        if (!_hasTable(db, 'main', t)) continue;
        if (t == 'settings') {
          for (final r in db.select('SELECT key FROM main.settings').toList()) {
            final k = r['key'] as String;
            if (!_staysOnDevice(k)) db.execute('DELETE FROM main.settings WHERE key=?', [k]);
          }
          if (!_hasTable(db, 'sf', t)) continue;
          for (final r in db.select('SELECT key, value FROM sf.settings').toList()) {
            final k = r['key'] as String;
            if (!_staysOnDevice(k)) db.execute('INSERT OR REPLACE INTO main.settings(key, value) VALUES (?,?)', [k, r['value']]);
          }
          continue;
        }
        db.execute('DELETE FROM main."$t"');
        if (_hasTable(db, 'sf', t)) _copy(db, 'sf', 'main', t);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  } finally {
    db.execute('DETACH DATABASE sf');
  }
  u.reloadStatuses();
  if (!_undoOps(u, j)) {
    // The database is back; the journal stays, so undo can be tried again.
    throw const BackupException('rollback_incomplete', 'not every picture folder could be put back');
  }
  j.remove();
  return true;
}

void _merge(UserDb u, BackupPreview pv, RestoreResult res, Map<String, ConflictChoice> bookChoices, ConflictChoice wordChoice,
    _Journal j) {
  final db = u.db;
  final hasReview = _hasTable(db, 'bk', 'review');

  // Words and their review cards travel together.
  final local = {for (final r in db.select('SELECT lemma, status FROM main.words')) r['lemma'] as String: r['status'] as int};
  for (final r in db.select('SELECT lemma, status FROM bk.words')) {
    final k = r['lemma'] as String;
    final l = local[k];
    if (l != null && l == r['status']) continue;
    if (l != null && wordChoice == ConflictChoice.keepLocal) {
      res.wordsKeptLocal++;
      continue;
    }
    _copy(db, 'bk', 'main', 'words', where: 'lemma=?', args: [k], verb: 'INSERT OR REPLACE');
    db.execute('DELETE FROM main.review WHERE lemma=?', [k]);
    if (hasReview) _copy(db, 'bk', 'main', 'review', where: 'lemma=?', args: [k]);
    l == null ? res.wordsAdded++ : res.wordsFromBackup++;
  }
  if (_hasTable(db, 'bk', 'activity')) _copy(db, 'bk', 'main', 'activity', verb: 'INSERT OR IGNORE');

  // Books
  final ids = <int, int>{}; // backup id -> id on this device
  final conflicts = {for (final c in pv.bookConflicts) c.key: c};
  for (final b in pv._books) {
    final lid = b.localId;
    if (lid != null) {
      ids[b.id] = lid;
      res.booksMatched++;
      final c = conflicts[b.key];
      if (c != null) {
        if ((bookChoices[b.key] ?? ConflictChoice.keepLocal) == ConflictChoice.useBackup) {
          db.execute('UPDATE main.books SET last_chapter=?, last_para=?, last_page=? WHERE id=?',
              [c.backup.chapter, c.backup.para, c.backup.page, lid]);
          res.booksFromBackup++;
        } else {
          res.booksKeptLocal++;
        }
      }
      // AI summaries and translations fill only what is empty here.
      db.execute('UPDATE main.chapters SET summary=(SELECT s.summary FROM bk.chapters s WHERE s.book_id=? AND s.idx=main.chapters.idx) '
          'WHERE book_id=? AND summary IS NULL', [b.id, lid]);
      if (pv.manifest.includesBooks) {
        db.execute('UPDATE main.paras SET tr=(SELECT s.tr FROM bk.paras s WHERE s.book_id=? AND s.chapter=main.paras.chapter '
            'AND s.idx=main.paras.idx) WHERE book_id=? AND tr IS NULL', [b.id, lid]);
      }
    } else if (pv.manifest.includesBooks) {
      ids[b.id] = _addBook(u, pv, b.id, j);
      res.booksAdded++;
    } else {
      final r = db.select('SELECT * FROM bk.books WHERE id=?', [b.id]).first;
      db.execute(
          'INSERT OR REPLACE INTO main.backup_pending_books(key, title, author, format, source, lang, last_chapter, last_para, last_page, added) '
          'VALUES (?,?,?,?,?,?,?,?,?,?)',
          [b.key, r['title'], r['author'], r['format'], r['source'], r['lang'] ?? 'en', r['last_chapter'] ?? 0, r['last_para'] ?? 0,
            r['last_page'] ?? 0, DateTime.now().millisecondsSinceEpoch]);
      res.booksWaiting++;
    }
  }
  if (_hasTable(db, 'bk', 'backup_pending_books')) _copy(db, 'bk', 'main', 'backup_pending_books', verb: 'INSERT OR IGNORE');

  // Reading statistics of the books that are on this device now. A day
  // already counted here is not counted twice.
  for (final e in ids.entries) {
    for (final t in ['reading_time', 'read_para']) {
      if (!_hasTable(db, 'bk', t)) continue;
      _copy(db, 'bk', 'main', t, where: 'book_id=?', args: [e.key], verb: 'INSERT OR IGNORE', set: {'book_id': '${e.value}'});
    }
  }
  for (final t in _logs) {
    if (_hasTable(db, 'bk', t)) _copyNew(db, t);
  }
  for (final t in _keyedCaches) {
    if (_hasTable(db, 'bk', t)) _copy(db, 'bk', 'main', t, verb: 'INSERT OR IGNORE', skip: {'id'});
  }
}

/// Adds a book of the backup that is not on this device; returns its new id.
int _addBook(UserDb u, BackupPreview pv, int id, _Journal j) {
  final db = u.db;
  _copy(db, 'bk', 'main', 'books', where: 'id=?', args: [id], skip: {'id'});
  final nid = db.lastInsertRowId;
  _copy(db, 'bk', 'main', 'chapters', where: 'book_id=?', args: [id], set: {'book_id': '$nid'});
  final from = 'books/$id/', to = 'books/$nid/';
  _copy(db, 'bk', 'main', 'paras', where: 'book_id=?', args: [id], skip: {'id'}, set: {
    'book_id': '$nid',
    'text': "CASE WHEN kind='i' AND substr(text, 1, ${from.length})='$from' THEN '$to' || substr(text, ${from.length + 1}) ELSE text END",
  });
  final src = Directory(p.join(pv._tmp.path, 'books', '$id'));
  if (src.existsSync()) {
    final rel = 'books/$nid';
    _freshDir(u, j, rel);
    _copyDir(src, Directory(_abs(u, rel)), rel);
  }
  return nid;
}

/// Replaces the learner's tables, and the picture folder: the old one is
/// moved into `backups/` (never deleted here), the backup's is copied in.
void _replace(UserDb u, BackupPreview pv, _Journal j) {
  final db = u.db;
  for (final t in _tables) {
    if (t == 'settings' || !_hasTable(db, 'main', t)) continue;
    db.execute('DELETE FROM main."$t"');
    if (_hasTable(db, 'bk', t)) _copy(db, 'bk', 'main', t);
  }
  for (final r in db.select('SELECT key FROM main.settings').toList()) {
    final k = r['key'] as String;
    if (!_staysOnDevice(k)) db.execute('DELETE FROM main.settings WHERE key=?', [k]);
  }
  for (final e in pv.backupSettings.entries) {
    db.execute('INSERT OR REPLACE INTO main.settings(key, value) VALUES (?,?)', [e.key, e.value]);
  }
  if (Directory(_abs(u, 'books')).existsSync()) _move(u, j, 'books', 'backups/books-before-restore-${j.id}');
  final src = Directory(p.join(pv._tmp.path, 'books'));
  if (src.existsSync()) {
    _freshDir(u, j, 'books');
    _copyDir(src, Directory(_abs(u, 'books')), 'books');
  }
}

// ------------------------------------------------------------------ journal

/// The database table that records, in the restore's own transaction, that
/// a restore finished. Only on this device (left out of every backup).
const _restoreLog = 'backup_restore_log';

/// Tests only: called before each step on the picture folders (`move …`,
/// `create …`, `copy …`, `undo …`, `discard`); throwing makes that step fail.
void Function(String step)? debugRestoreStep;

/// Tests only: thrown from [debugRestoreStep], it stops a restore as if the
/// app had been closed at that point (no rollback, no clean-up).
class BackupDebugCrash implements Exception {
  const BackupDebugCrash();
}

void _step(String s) => debugRestoreStep?.call(s);

String _abs(UserDb u, String rel) => p.joinAll([u.dir, ...rel.split('/')]);

/// One restore's safety copy (`backups/before-restore-<id>.db`) and journal
/// (`.json`): its state — `pending` while it runs, `done` when it can be
/// undone, `superseded` once a later restore finished, `failed` — and each
/// step on the picture folders, written before the step is taken. Paths are
/// relative to the app folder, which can move (iOS moves it on updates).
class _Journal {
  final UserDb u;
  final int id;
  String state;
  final String mode;
  final List<Map<String, dynamic>> ops;
  _Journal(this.u, this.id, this.state, this.mode, this.ops);

  static Directory dir(UserDb u) => Directory(p.join(u.dir, 'backups'));
  File get copy => File(p.join(dir(u).path, 'before-restore-$id.db'));
  File get file => File(p.join(dir(u).path, 'before-restore-$id.json'));

  /// Takes the safety copy: the whole database without API keys and device
  /// settings (a restore never changes those, and undo keeps the ones the
  /// device has then), so no key lies in a second file.
  static _Journal begin(UserDb u, RestoreMode mode) {
    dir(u).createSync(recursive: true);
    var id = DateTime.now().millisecondsSinceEpoch;
    _Journal j() => _Journal(u, id, 'pending', mode.name, []);
    while (j().file.existsSync() || j().copy.existsSync()) {
      id++;
    }
    final jr = j();
    try {
      u.db.execute('VACUUM INTO ?', [jr.copy.path]);
      final d = sqlite3.open(jr.copy.path);
      try {
        d.execute('PRAGMA secure_delete=ON');
        if (_hasTable(d, 'main', 'settings')) {
          for (final r in d.select('SELECT key FROM settings').toList()) {
            final k = r['key'] as String;
            if (_staysOnDevice(k)) d.execute('DELETE FROM settings WHERE key=?', [k]);
          }
        }
        d.execute('VACUUM');
      } finally {
        d.close();
      }
      jr.save();
    } catch (_) {
      jr.remove();
      rethrow;
    }
    return jr;
  }

  static _Journal load(UserDb u, int id, File f) {
    try {
      final m = jsonDecode(f.readAsStringSync()) as Map;
      return _Journal(u, id, '${m['state']}', '${m['mode'] ?? ''}',
          [for (final o in (m['ops'] as List? ?? const [])) Map<String, dynamic>.from(o as Map)]);
    } catch (_) {
      return _Journal(u, id, 'unreadable', '', []);
    }
  }

  void add(Map<String, dynamic> op) {
    ops.add(op);
    save();
  }

  /// Written beside and renamed over, so the journal is never half written.
  void save() {
    final part = File('${file.path}.part');
    part.writeAsStringSync(jsonEncode({'state': state, 'mode': mode, 'ops': ops}), flush: true);
    part.renameSync(file.path);
  }

  /// The restore finished: this is the undo point now, no earlier one is.
  void finish() {
    state = 'done';
    save();
    for (final o in _journals(u)) {
      if (o.id != id && o.state == 'done') {
        o.state = 'superseded';
        o.save();
      }
    }
    _prune(u);
  }

  /// A restore that failed and was rolled back leaves nothing behind that
  /// could later be taken for an undo point.
  void discard() {
    try {
      _step('discard');
      file.deleteSync();
    } catch (_) {
      try {
        state = 'failed';
        ops.clear();
        save();
      } catch (_) {}
    }
    try {
      if (copy.existsSync()) copy.deleteSync();
    } catch (_) {}
  }

  void remove() {
    for (final f in [file, copy, File('${file.path}.part')]) {
      try {
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }
}

/// The journals in `backups/`, newest first.
List<_Journal> _journals(UserDb u) {
  final d = _Journal.dir(u);
  if (!d.existsSync()) return [];
  final out = <_Journal>[];
  for (final f in d.listSync().whereType<File>()) {
    final m = RegExp(r'^before-restore-(\d+)\.json$').firstMatch(p.basename(f.path));
    if (m != null) out.add(_Journal.load(u, int.parse(m[1]!), f));
  }
  out.sort((a, b) => b.id.compareTo(a.id));
  return out;
}

/// Keeps the three newest restores (with the picture folders they moved
/// aside); removes safety copies that never got a journal.
void _prune(UserDb u) {
  final js = _journals(u);
  for (final o in js.skip(3)) {
    for (final op in o.ops) {
      final to = op['to'];
      if (op['op'] == 'move' && to is String && to.startsWith('backups/')) {
        try {
          final d = Directory(_abs(u, to));
          if (d.existsSync()) d.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
    o.remove();
  }
  final ids = {for (final o in js.take(3)) o.id};
  for (final f in _Journal.dir(u).listSync().whereType<File>()) {
    final m = RegExp(r'^before-restore-(\d+)\.db$').firstMatch(p.basename(f.path));
    if (m != null && !ids.contains(int.parse(m[1]!))) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }
}

void _move(UserDb u, _Journal j, String from, String to) {
  j.add({'op': 'move', 'from': from, 'to': to});
  _step('move $from');
  final t = Directory(_abs(u, to));
  t.parent.createSync(recursive: true);
  Directory(_abs(u, from)).renameSync(t.path);
}

/// A new, empty folder at [rel]; a folder already there is moved aside.
void _freshDir(UserDb u, _Journal j, String rel) {
  if (Directory(_abs(u, rel)).existsSync()) _move(u, j, rel, 'backups/restore-${j.id}-aside/${rel.replaceAll('/', '_')}');
  j.add({'op': 'create', 'path': rel});
  _step('create $rel');
  Directory(_abs(u, rel)).createSync(recursive: true);
}

/// Takes back the journal's steps on the picture folders, newest first. Each
/// step is tried even when an earlier one fails, and nothing that was there
/// before the restore is deleted: a folder moved aside is only moved back.
/// False when some step could not be taken back.
bool _undoOps(UserDb u, _Journal j) {
  var ok = true;
  for (final o in j.ops.reversed) {
    try {
      if (o['op'] == 'create') {
        _step('undo create ${o['path']}');
        final d = Directory(_abs(u, '${o['path']}'));
        if (d.existsSync()) d.deleteSync(recursive: true);
      } else if (o['op'] == 'move') {
        _step('undo move ${o['from']}');
        final from = Directory(_abs(u, '${o['from']}')), to = Directory(_abs(u, '${o['to']}'));
        if (to.existsSync()) {
          if (from.existsSync()) throw StateError('${o['from']} is in the way');
          from.parent.createSync(recursive: true);
          to.renameSync(from.path);
        } else if (!from.existsSync()) {
          throw StateError('${o['to']} is missing');
        }
      }
    } catch (_) {
      ok = false;
    }
  }
  return ok;
}

void _ensureTables(UserDb u) {
  ReviewStore(u);
  StatsStore(u);
  u.db.execute('''
    CREATE TABLE IF NOT EXISTS backup_pending_books(key TEXT PRIMARY KEY, title TEXT, author TEXT, format TEXT, source TEXT,
      lang TEXT, last_chapter INTEGER, last_para INTEGER, last_page INTEGER, added INTEGER)
  ''');
  u.db.execute('CREATE TABLE IF NOT EXISTS $_restoreLog(id INTEGER PRIMARY KEY, mode TEXT, finished INTEGER)');
}

// ------------------------------------------------------------------ helpers

bool _hasTable(Database db, String schema, String t) =>
    db.select("SELECT 1 FROM $schema.sqlite_master WHERE type='table' AND name=?", [t]).isNotEmpty;

List<String> _columns(Database db, String schema, String t) => [for (final r in db.select('PRAGMA $schema.table_info("$t")')) r['name'] as String];

List<int> _bookIds(Database db, String schema) => [for (final r in db.select('SELECT id FROM $schema.books ORDER BY id')) r['id'] as int];

/// Copies rows of [t] from [from] to [to], over the columns both have (an
/// older backup may lack newer columns). [set] gives SQL for some columns,
/// [skip] leaves columns out (a new id is given).
void _copy(Database db, String from, String to, String t,
    {String? where, List<Object?> args = const [], String verb = 'INSERT', Set<String> skip = const {}, Map<String, String> set = const {}}) {
  final have = _columns(db, from, t).toSet();
  final cols = [for (final c in _columns(db, to, t)) if (!skip.contains(c) && (have.contains(c) || set.containsKey(c))) c];
  if (cols.isEmpty) return;
  final names = cols.map((c) => '"$c"').join(', ');
  final values = cols.map((c) => set[c] ?? '"$c"').join(', ');
  db.execute('$verb INTO $to."$t"($names) SELECT $values FROM $from."$t"${where == null ? '' : ' WHERE $where'}', args);
}

/// Adds log rows (running id) that are not on this device yet.
void _copyNew(Database db, String t) {
  final have = _columns(db, 'bk', t).toSet();
  final cols = [for (final c in _columns(db, 'main', t)) if (c != 'id' && have.contains(c)) c];
  if (cols.isEmpty) return;
  final names = cols.map((c) => '"$c"').join(', ');
  final same = cols.map((c) => 'm."$c" IS b."$c"').join(' AND ');
  db.execute('INSERT INTO main."$t"($names) SELECT ${cols.map((c) => 'b."$c"').join(', ')} FROM bk."$t" b '
      'WHERE NOT EXISTS (SELECT 1 FROM main."$t" m WHERE $same)');
}

void _copyDir(Directory src, Directory dst, String rel) {
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    final r = p.relative(f.path, from: src.path);
    _step('copy $rel/${p.split(r).join('/')}');
    final target = File(p.join(dst.path, r));
    target.parent.createSync(recursive: true);
    f.copySync(target.path);
  }
}

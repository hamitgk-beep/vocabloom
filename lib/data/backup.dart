import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
/// `checksum`, `corrupt`, `incomplete`, `replace_needs_books`.
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
      for (final t in [..._tables, 'backup_books']) {
        if (_hasTable(d, 'main', t)) counts[t] = d.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int;
      }
      d.execute('VACUUM');
    } finally {
      d.close();
    }
    final data = File(dataPath).readAsBytesSync();
    final manifest = {
      'format': backupFormat,
      'format_version': backupFormatVersion,
      'created': DateTime.now().toUtc().toIso8601String(),
      'app_version': appVersion,
      'app_build': appBuild,
      'platform': Platform.operatingSystem,
      'includes_books': includeBooks,
      'counts': counts,
      'data_sha256': sha256.convert(data).toString(),
    };
    final zip = Archive()
      ..add(ArchiveFile.string('manifest.json', const JsonEncoder.withIndent(' ').convert(manifest)))
      ..add(ArchiveFile.bytes('data.db', data));
    if (includeBooks) {
      for (final id in fingerprints.keys) {
        final dir = Directory(p.join(u.dir, 'books', '$id'));
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          final rel = p.split(p.relative(f.path, from: u.dir)).join('/');
          zip.add(ArchiveFile.bytes(rel, f.readAsBytesSync()));
        }
      }
    }
    // Written next to the target first, so a failed write leaves no half file.
    final part = File('${out.path}.part');
    part.writeAsBytesSync(ZipEncoder().encodeBytes(zip), flush: true);
    if (out.existsSync()) out.deleteSync();
    return part.renameSync(out.path);
  } finally {
    tmp.deleteSync(recursive: true);
  }
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
BackupPreview inspectBackup(UserDb u, File file) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(file.readAsBytesSync(), verify: true);
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
  for (final f in zip.files) {
    if (!_safeEntry(f.name)) throw BackupException('not_backup', 'bad entry ${f.name}');
  }
  final data = zip.findFile('data.db')?.readBytes();
  if (data == null) throw const BackupException('incomplete', 'no data.db');
  if (sha256.convert(data).toString() != m['data_sha256']) throw const BackupException('checksum');

  final tmp = Directory.systemTemp.createTempSync('storilex_restore');
  try {
    File(p.join(tmp.path, 'data.db')).writeAsBytesSync(data, flush: true);
    for (final f in zip.files) {
      if (!f.isFile || !f.name.startsWith('books/')) continue;
      final target = File(p.joinAll([tmp.path, ...f.name.split('/')]));
      target.parent.createSync(recursive: true);
      target.writeAsBytesSync(f.readBytes() ?? const []);
    }
    return _preview(u, m, tmp);
  } catch (e) {
    tmp.deleteSync(recursive: true);
    rethrow;
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
/// [debugFailAfterWrites] makes the restore fail after all its writes (tests).
RestoreResult restoreBackup(UserDb u, BackupPreview pv,
    {RestoreMode mode = RestoreMode.merge,
    Map<String, ConflictChoice> bookChoices = const {},
    ConflictChoice wordChoice = ConflictChoice.keepLocal,
    bool debugFailAfterWrites = false}) {
  if (mode == RestoreMode.replace && !pv.manifest.includesBooks) throw const BackupException('replace_needs_books');
  if (!pv._tmp.existsSync()) throw StateError('the backup preview was disposed');
  _ensureTables(u);
  final res = RestoreResult();
  final safety = _safetyCopy(u);
  res.safetyCopy = safety.path;
  final created = <String>[];
  String? moved;
  final db = u.db;
  db.execute('ATTACH DATABASE ? AS bk', [pv._dataPath]);
  try {
    db.execute('BEGIN');
    try {
      if (mode == RestoreMode.replace) {
        moved = _replace(u, pv, created);
      } else {
        _merge(u, pv, res, bookChoices, wordChoice, created);
      }
      if (debugFailAfterWrites) throw StateError('restore failed on purpose');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      _undoFiles(u, created, moved);
      rethrow;
    }
  } finally {
    db.execute('DETACH DATABASE bk');
  }
  File(p.setExtension(safety.path, '.json')).writeAsStringSync(jsonEncode({'created_dirs': created, 'moved_books': moved}));
  if (mode == RestoreMode.replace) {
    res.wordsAdded = db.select('SELECT COUNT(*) AS n FROM words').first['n'] as int;
    res.booksAdded = db.select('SELECT COUNT(*) AS n FROM books').first['n'] as int;
  }
  u.reloadStatuses();
  return res;
}

/// Puts the data back the way it was before the last restore. False when
/// there is no restore to undo.
bool undoLastRestore(UserDb u) {
  final dir = Directory(p.join(u.dir, 'backups'));
  if (!dir.existsSync()) return false;
  final copies = dir.listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('before-restore-') && f.path.endsWith('.db')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (copies.isEmpty) return false;
  final copy = copies.last;
  final info = File(p.setExtension(copy.path, '.json'));
  final meta = info.existsSync() ? jsonDecode(info.readAsStringSync()) as Map : const {};
  final db = u.db;
  db.execute('ATTACH DATABASE ? AS sf', [copy.path]);
  try {
    db.execute('BEGIN');
    try {
      for (final t in _tables) {
        if (!_hasTable(db, 'main', t)) continue;
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
  _undoFiles(u, [for (final d in (meta['created_dirs'] as List? ?? const [])) '$d'], meta['moved_books'] as String?);
  copy.deleteSync();
  if (info.existsSync()) info.deleteSync();
  u.reloadStatuses();
  return true;
}

void _merge(UserDb u, BackupPreview pv, RestoreResult res, Map<String, ConflictChoice> bookChoices, ConflictChoice wordChoice,
    List<String> created) {
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
      ids[b.id] = _addBook(u, pv, b.id, created);
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
int _addBook(UserDb u, BackupPreview pv, int id, List<String> created) {
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
    final dst = Directory(p.join(u.dir, 'books', '$nid'));
    if (!dst.existsSync()) created.add(dst.path);
    _copyDir(src, dst);
  }
  return nid;
}

/// Replaces the learner's tables; returns where the old pictures were moved.
String? _replace(UserDb u, BackupPreview pv, List<String> created) {
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
  final books = Directory(p.join(u.dir, 'books'));
  String? moved;
  if (books.existsSync()) {
    moved = p.join(u.dir, 'backups', 'books-before-restore-${DateTime.now().millisecondsSinceEpoch}');
    books.renameSync(moved);
  }
  final src = Directory(p.join(pv._tmp.path, 'books'));
  created.add(books.path);
  if (src.existsSync()) _copyDir(src, books);
  return moved;
}

void _undoFiles(UserDb u, List<String> created, String? moved) {
  for (final d in created) {
    try {
      final dir = Directory(d);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
  if (moved != null && Directory(moved).existsSync()) {
    final books = Directory(p.join(u.dir, 'books'));
    if (books.existsSync()) books.deleteSync(recursive: true);
    Directory(moved).renameSync(books.path);
  }
}

/// A full copy of the device's data, the last three kept.
File _safetyCopy(UserDb u) {
  final dir = Directory(p.join(u.dir, 'backups'))..createSync(recursive: true);
  final f = File(p.join(dir.path, 'before-restore-${DateTime.now().millisecondsSinceEpoch}.db'));
  u.db.execute('VACUUM INTO ?', [f.path]);
  final old = dir.listSync().whereType<File>().where((x) => p.basename(x.path).startsWith('before-restore-') && x.path.endsWith('.db')).toList()
    ..sort((a, b) => b.path.compareTo(a.path));
  for (final x in old.skip(3)) {
    try {
      x.deleteSync();
      final j = File(p.setExtension(x.path, '.json'));
      if (j.existsSync()) j.deleteSync();
    } catch (_) {}
  }
  return f;
}

void _ensureTables(UserDb u) {
  ReviewStore(u);
  StatsStore(u);
  u.db.execute('''
    CREATE TABLE IF NOT EXISTS backup_pending_books(key TEXT PRIMARY KEY, title TEXT, author TEXT, format TEXT, source TEXT,
      lang TEXT, last_chapter INTEGER, last_para INTEGER, last_page INTEGER, added INTEGER)
  ''');
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

void _copyDir(Directory src, Directory dst) {
  for (final f in src.listSync(recursive: true).whereType<File>()) {
    final target = File(p.join(dst.path, p.relative(f.path, from: src.path)));
    target.parent.createSync(recursive: true);
    f.copySync(target.path);
  }
}

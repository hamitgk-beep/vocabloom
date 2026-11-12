import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

enum WordStatus { none, learning, learned }

class Book {
  final int id;
  final String title;
  final String? author;
  final String format;
  final int chapterCount;
  int lastChapter;
  int lastParagraph;
  final DateTime added;
  Book(this.id, this.title, this.author, this.format, this.chapterCount, this.lastChapter,
      this.lastParagraph, this.added);
}

class Chapter {
  final int idx;
  final String title;
  final String? summary;
  Chapter(this.idx, this.title, this.summary);
}

class Para {
  final int id;
  final int idx;
  final String kind; // p, h
  final String text;
  Para(this.id, this.idx, this.kind, this.text);
}

class SavedWord {
  final String lemma;
  final WordStatus status;
  final String? context;
  final String? bookTitle;
  final String? meaning;
  final DateTime added;
  SavedWord(this.lemma, this.status, this.context, this.bookTitle, this.meaning, this.added);
}

/// Imported book content shape, produced by the importers.
class ImportedBook {
  final String title;
  final String? author;
  final String format;
  final List<ImportedChapter> chapters;
  ImportedBook(this.title, this.author, this.format, this.chapters);
}

class ImportedChapter {
  final String title;
  final List<(String kind, String text)> paragraphs;
  ImportedChapter(this.title, this.paragraphs);
}

/// Everything the user creates lives here, on the device.
class UserDb {
  late final Database db;
  final Map<String, WordStatus> statuses = {};

  static UserDb open(Directory dir) {
    final u = UserDb();
    u.db = sqlite3.open(p.join(dir.path, 'user.db'));
    u.db.execute('PRAGMA journal_mode=WAL');
    u.db.execute('''
      CREATE TABLE IF NOT EXISTS books(id INTEGER PRIMARY KEY, title TEXT, author TEXT, format TEXT,
        chapters INTEGER, last_chapter INTEGER DEFAULT 0, last_para INTEGER DEFAULT 0, added INTEGER);
      CREATE TABLE IF NOT EXISTS chapters(book_id INTEGER, idx INTEGER, title TEXT, summary TEXT,
        PRIMARY KEY(book_id, idx));
      CREATE TABLE IF NOT EXISTS paras(id INTEGER PRIMARY KEY, book_id INTEGER, chapter INTEGER, idx INTEGER,
        kind TEXT, text TEXT, tr TEXT);
      CREATE INDEX IF NOT EXISTS paras_book ON paras(book_id, chapter, idx);
      CREATE TABLE IF NOT EXISTS words(lemma TEXT PRIMARY KEY, status INTEGER, context TEXT, book TEXT,
        meaning TEXT, added INTEGER);
      CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT);
    ''');
    for (final r in u.db.select('SELECT lemma, status FROM words')) {
      u.statuses[r['lemma'] as String] = WordStatus.values[r['status'] as int];
    }
    return u;
  }

  // ---- settings
  String? getSetting(String key) {
    final r = db.select('SELECT value FROM settings WHERE key=?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void setSetting(String key, String? value) {
    if (value == null) {
      db.execute('DELETE FROM settings WHERE key=?', [key]);
    } else {
      db.execute('INSERT OR REPLACE INTO settings VALUES (?, ?)', [key, value]);
    }
  }

  Map<String, dynamic> getJson(String key) {
    final s = getSetting(key);
    return s == null ? {} : (jsonDecode(s) as Map<String, dynamic>);
  }

  void setJson(String key, Map<String, dynamic> v) => setSetting(key, jsonEncode(v));

  // ---- books
  int insertBook(ImportedBook b) {
    db.execute('BEGIN');
    try {
      db.execute('INSERT INTO books(title, author, format, chapters, added) VALUES (?,?,?,?,?)',
          [b.title, b.author, b.format, b.chapters.length, DateTime.now().millisecondsSinceEpoch]);
      final id = db.lastInsertRowId;
      final ch = db.prepare('INSERT INTO chapters(book_id, idx, title) VALUES (?,?,?)');
      final pa = db.prepare('INSERT INTO paras(book_id, chapter, idx, kind, text) VALUES (?,?,?,?,?)');
      for (var c = 0; c < b.chapters.length; c++) {
        ch.execute([id, c, b.chapters[c].title]);
        final ps = b.chapters[c].paragraphs;
        for (var i = 0; i < ps.length; i++) {
          pa.execute([id, c, i, ps[i].$1, ps[i].$2]);
        }
      }
      ch.close();
      pa.close();
      db.execute('COMMIT');
      return id;
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Book> books() => [
        for (final r in db.select('SELECT * FROM books ORDER BY added DESC'))
          Book(r['id'] as int, r['title'] as String, r['author'] as String?, r['format'] as String,
              r['chapters'] as int, r['last_chapter'] as int, r['last_para'] as int,
              DateTime.fromMillisecondsSinceEpoch(r['added'] as int))
      ];

  void deleteBook(int id) {
    db.execute('DELETE FROM paras WHERE book_id=?', [id]);
    db.execute('DELETE FROM chapters WHERE book_id=?', [id]);
    db.execute('DELETE FROM books WHERE id=?', [id]);
  }

  void saveProgress(int bookId, int chapter, int para) =>
      db.execute('UPDATE books SET last_chapter=?, last_para=? WHERE id=?', [chapter, para, bookId]);

  List<Chapter> chapters(int bookId) => [
        for (final r in db.select('SELECT idx, title, summary FROM chapters WHERE book_id=? ORDER BY idx', [bookId]))
          Chapter(r['idx'] as int, r['title'] as String, r['summary'] as String?)
      ];

  List<Para> paras(int bookId, int chapter) => [
        for (final r in db.select(
            'SELECT id, idx, kind, text FROM paras WHERE book_id=? AND chapter=? ORDER BY idx', [bookId, chapter]))
          Para(r['id'] as int, r['idx'] as int, r['kind'] as String, r['text'] as String)
      ];

  /// Sentence translations stored by the online analysis (JSON list).
  List<String>? paraTranslation(int paraId) {
    final r = db.select('SELECT tr FROM paras WHERE id=?', [paraId]);
    final s = r.isEmpty ? null : r.first['tr'] as String?;
    return s == null ? null : (jsonDecode(s) as List).cast<String>();
  }

  void setParaTranslation(int paraId, List<String> tr) =>
      db.execute('UPDATE paras SET tr=? WHERE id=?', [jsonEncode(tr), paraId]);

  void setChapterSummary(int bookId, int idx, String summary) =>
      db.execute('UPDATE chapters SET summary=? WHERE book_id=? AND idx=?', [summary, bookId, idx]);

  List<({int id, String text})> parasMissingTranslation(int bookId) => [
        for (final r in db.select(
            'SELECT id, text FROM paras WHERE book_id=? AND tr IS NULL ORDER BY chapter, idx', [bookId]))
          (id: r['id'] as int, text: r['text'] as String)
      ];

  /// Sentences in the book that contain any of [forms] (for examples).
  List<String> findSentences(int bookId, Set<String> forms, {int limit = 4, String? exclude}) {
    final out = <String>[];
    final re = RegExp(r'\b(' + forms.map(RegExp.escape).join('|') + r')\b', caseSensitive: false);
    for (final r in db.select('SELECT text FROM paras WHERE book_id=? AND kind=?', [bookId, 'p'])) {
      final t = r['text'] as String;
      if (!re.hasMatch(t)) continue;
      for (final s in t.split(RegExp(r'(?<=[.!?])\s+'))) {
        if (s.length > 15 && s.length < 260 && re.hasMatch(s) && s != exclude && !out.contains(s)) {
          out.add(s.trim());
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  // ---- words
  void setWord(String lemma, WordStatus status, {String? context, String? book, String? meaning}) {
    if (status == WordStatus.none) {
      db.execute('DELETE FROM words WHERE lemma=?', [lemma]);
      statuses.remove(lemma);
      return;
    }
    final exists = db.select('SELECT 1 FROM words WHERE lemma=?', [lemma]).isNotEmpty;
    if (exists) {
      db.execute('UPDATE words SET status=? WHERE lemma=?', [status.index, lemma]);
    } else {
      db.execute('INSERT INTO words VALUES (?,?,?,?,?,?)',
          [lemma, status.index, context, book, meaning, DateTime.now().millisecondsSinceEpoch]);
    }
    statuses[lemma] = status;
  }

  List<SavedWord> words(WordStatus status) => [
        for (final r in db.select('SELECT * FROM words WHERE status=? ORDER BY added DESC', [status.index]))
          SavedWord(r['lemma'] as String, status, r['context'] as String?, r['book'] as String?,
              r['meaning'] as String?, DateTime.fromMillisecondsSinceEpoch(r['added'] as int))
      ];
}

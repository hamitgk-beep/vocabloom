import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'sentence_translation.dart';

enum WordStatus { none, learning, learned }

class Book {
  final int id;
  final String title;
  final String? author;
  final String format;
  final int chapterCount;
  int lastChapter;

  /// Scroll offset in the page last read.
  int lastParagraph;

  /// Page of [lastChapter] last read (counted from 0 in that chapter).
  int lastPage;
  final DateTime added;

  /// Id of the free-library item this book came from (pb-0002, pg-1342), if any.
  final String? source;
  Book(this.id, this.title, this.author, this.format, this.chapterCount, this.lastChapter,
      this.lastParagraph, this.added, {this.source, this.lastPage = 0});
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

  /// p (paragraph), h (heading), c (picture caption), i (picture: [text] is
  /// its file, relative to the app folder).
  final String kind;
  final String text;

  /// How the book sets it, from the import (see [ParaMeta]); empty when unknown.
  final Map<String, dynamic> meta;
  Para(this.id, this.idx, this.kind, this.text, [this.meta = const {}]);

  /// Page of the original book (from 0), when the book has pages (PDF).
  int? get page => (meta['pg'] as num?)?.toInt();

  /// Type size compared with the book's body text (1 = the same).
  double get size => (meta['sz'] as num?)?.toDouble() ?? 1;

  /// l (left), c (centre), r (right), j (justified); null when unknown.
  String? get align => meta['al'] as String?;

  /// Width / height of a picture.
  double? get aspect => (meta['ar'] as num?)?.toDouble();
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

  /// Pictures of the book by name; an 'i' paragraph's text is one of these names.
  final Map<String, List<int>> images;
  ImportedBook(this.title, this.author, this.format, this.chapters, [Map<String, List<int>>? images]) : images = images ?? {};
}

class ImportedChapter {
  final String title;
  final List<(String kind, String text)> paragraphs;

  /// How each paragraph is set ([Para.meta]); shorter than [paragraphs] (or
  /// empty) when not known.
  final List<Map<String, Object?>?> meta;
  ImportedChapter(this.title, this.paragraphs, [List<Map<String, Object?>?>? meta]) : meta = meta ?? [];

  Map<String, Object?>? metaAt(int i) => i >= 0 && i < meta.length ? meta[i] : null;

  /// Adds a paragraph with its [m] (kept in step with [paragraphs]).
  void add(String kind, String text, [Map<String, Object?>? m]) {
    while (meta.length < paragraphs.length) {
      meta.add(null);
    }
    paragraphs.add((kind, text));
    meta.add(m);
  }
}

/// Everything the user creates lives here, on the device.
class UserDb {
  late final Database db;

  /// The app folder: the database and the books' pictures (`books/<id>/`).
  late final String dir;
  /// Saved words of the language being learned, by lemma. Turkish words are
  /// stored with a `tr:` key so the two languages never mix.
  final Map<String, WordStatus> statuses = {};

  /// The language being learned: 'en' or 'tr'.
  String get lang => _lang;
  String _lang = 'en';
  set lang(String v) {
    if (v == _lang) return;
    _lang = v;
    _loadStatuses();
  }

  String get _prefix => _lang == 'en' ? '' : '$_lang:';

  /// The stored key of [lemma] in the language being learned.
  String key(String lemma) => '$_prefix$lemma';

  String get _langWhere => _lang == 'en' ? "lemma NOT LIKE 'tr:%'" : "lemma LIKE '$_prefix%'";

  /// Reads the saved words again (after a backup was restored).
  void reloadStatuses() => _loadStatuses();

  void _loadStatuses() {
    statuses.clear();
    for (final r in db.select('SELECT lemma, status FROM words WHERE $_langWhere')) {
      final k = r['lemma'] as String;
      statuses[k.substring(_prefix.length)] = WordStatus.values[r['status'] as int];
    }
  }

  static UserDb open(Directory dir) {
    final u = UserDb();
    u.dir = dir.path;
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
      CREATE TABLE IF NOT EXISTS expr_detail(key TEXT PRIMARY KEY, json TEXT);
      CREATE TABLE IF NOT EXISTS sentence_ai(sentence TEXT PRIMARY KEY, tr TEXT, exp TEXT);
      CREATE TABLE IF NOT EXISTS wfam_ai(word TEXT PRIMARY KEY, json TEXT);
      CREATE TABLE IF NOT EXISTS expr_ai(phrase TEXT, cat TEXT, tr TEXT, exp TEXT, PRIMARY KEY(phrase, cat));
      CREATE TABLE IF NOT EXISTS missing_tr(lemma TEXT, syn INTEGER, gloss TEXT, reported INTEGER DEFAULT 0,
        PRIMARY KEY(lemma, syn));
      CREATE TABLE IF NOT EXISTS ctx_ai(lemma TEXT, sentence TEXT, tr TEXT, PRIMARY KEY(lemma, sentence));
      CREATE TABLE IF NOT EXISTS sense_feedback(id INTEGER PRIMARY KEY, created INTEGER, word TEXT, sentence TEXT,
        sense_id TEXT, shown_tr TEXT, confidence TEXT, dict_version TEXT, engine_version TEXT, book TEXT);
      CREATE TABLE IF NOT EXISTS ai_meaning(id INTEGER PRIMARY KEY, created INTEGER, phrase TEXT, cat TEXT, lemma TEXT,
        sentence TEXT, tr TEXT, model TEXT, status TEXT DEFAULT 'draft', dict_version TEXT, engine_version TEXT,
        UNIQUE(sentence, phrase, cat));
      CREATE TABLE IF NOT EXISTS sense_help(word TEXT, sentence TEXT, created INTEGER, PRIMARY KEY(word, sentence));
    ''');
    // Older databases have no withdrawn flag on the reports: add it, keep every row.
    final fb = u.db.select('PRAGMA table_info(sense_feedback)').map((r) => r['name']).toSet();
    if (!fb.contains('withdrawn')) u.db.execute('ALTER TABLE sense_feedback ADD COLUMN withdrawn INTEGER DEFAULT 0');
    final cols = u.db.select('PRAGMA table_info(books)').map((r) => r['name']).toSet();
    if (!cols.contains('analyzed')) u.db.execute('ALTER TABLE books ADD COLUMN analyzed INTEGER DEFAULT 0');
    if (!cols.contains('source')) u.db.execute('ALTER TABLE books ADD COLUMN source TEXT');
    if (!cols.contains('last_page')) u.db.execute('ALTER TABLE books ADD COLUMN last_page INTEGER DEFAULT 0');
    // The language of the book's text ('en', 'tr'): each language shows its own books.
    if (!cols.contains('lang')) u.db.execute("ALTER TABLE books ADD COLUMN lang TEXT DEFAULT 'en'");
    final pc = u.db.select('PRAGMA table_info(paras)').map((r) => r['name']).toSet();
    if (!pc.contains('meta')) u.db.execute('ALTER TABLE paras ADD COLUMN meta TEXT');
    u._loadStatuses();
    return u;
  }

  // ---- AI translations of dictionary expressions
  Map<String, (String, String?)> exprAi() => {
        for (final r in db.select('SELECT phrase, cat, tr, exp FROM expr_ai'))
          '${r['phrase']}|${r['cat']}': (r['tr'] as String, r['exp'] as String?),
      };

  void setExprAi(String phrase, String cat, String tr, String? exp) =>
      db.execute('INSERT OR REPLACE INTO expr_ai(phrase, cat, tr, exp) VALUES (?,?,?,?)', [phrase, cat, tr, exp]);

  // ---- AI meaning of a saved word in its own sentence (review answers)
  String? contextAi(String lemma, String sentence) {
    final r = db.select('SELECT tr FROM ctx_ai WHERE lemma=? AND sentence=?', [lemma, sentence]);
    return r.isEmpty ? null : r.first['tr'] as String;
  }

  void setContextAi(String lemma, String sentence, String tr) =>
      db.execute('INSERT OR REPLACE INTO ctx_ai(lemma, sentence, tr) VALUES (?,?,?)', [lemma, sentence, tr]);

  // ---- "wrong meaning" reports on the meaning chosen for a sentence. Kept
  // apart from everything else: adding or exporting them never touches the
  // word list, the reviews or the reading progress.
  /// Records a "wrong meaning" report and returns its id. A report for the same
  /// word in the same sentence that is still active is not added twice.
  int addSenseFeedback({required String word, required String sentence, String? senseId, String? shownTr,
      String? confidence, required String dictVersion, required String engineVersion, String? book}) {
    final active = activeSenseFeedbackId(word, sentence);
    if (active != null) return active;
    db.execute(
        'INSERT INTO sense_feedback(created, word, sentence, sense_id, shown_tr, confidence, dict_version, engine_version, book, withdrawn) '
        'VALUES (?,?,?,?,?,?,?,?,?,0)',
        [DateTime.now().millisecondsSinceEpoch, word, sentence, senseId, shownTr, confidence, dictVersion, engineVersion, book]);
    return db.select('SELECT last_insert_rowid() AS id').first['id'] as int;
  }

  /// The active (not withdrawn) report for this word and sentence, if any.
  int? activeSenseFeedbackId(String word, String sentence) {
    final r = db.select('SELECT id FROM sense_feedback WHERE word=? AND sentence=? AND withdrawn=0 ORDER BY id DESC LIMIT 1',
        [word, sentence]);
    return r.isEmpty ? null : r.first['id'] as int;
  }

  /// Takes a report back: the row stays (the export shows it as withdrawn).
  void withdrawSenseFeedback(int id) => db.execute('UPDATE sense_feedback SET withdrawn=1 WHERE id=?', [id]);

  int senseFeedbackCount() => db.select('SELECT COUNT(*) AS n FROM sense_feedback').first['n'] as int;

  // ---- "Anlamı anlamadım": the learner asked for the simple explanation (not a wrong report)
  bool senseHelpShown(String word, String sentence) =>
      db.select('SELECT 1 FROM sense_help WHERE word=? AND sentence=?', [word, sentence]).isNotEmpty;

  void markSenseHelp(String word, String sentence) => db.execute(
      'INSERT OR IGNORE INTO sense_help(word, sentence, created) VALUES (?,?,?)', [word, sentence, DateTime.now().millisecondsSinceEpoch]);

  // ---- AI meanings kept on the device, per sentence. They are drafts until checked.
  /// The saved AI draft for this phrase in this sentence, unless it was flagged as wrong.
  String? aiMeaning(String sentence, String phrase, String cat) {
    final r = db.select("SELECT tr FROM ai_meaning WHERE sentence=? AND phrase=? AND cat=? AND status='draft'", [sentence, phrase, cat]);
    return r.isEmpty ? null : r.first['tr'] as String;
  }

  void saveAiMeaning({required String sentence, required String phrase, required String cat, required String lemma,
      required String tr, String? model, required String dictVersion, required String engineVersion}) {
    if (tr.trim().isEmpty) return; // an empty answer is never kept as a meaning
    db.execute(
        'INSERT OR REPLACE INTO ai_meaning(created, phrase, cat, lemma, sentence, tr, model, status, dict_version, engine_version) '
        "VALUES (?,?,?,?,?,?,?, 'draft', ?, ?)",
        [DateTime.now().millisecondsSinceEpoch, phrase, cat, lemma, sentence, tr.trim(), model, dictVersion, engineVersion]);
  }

  /// A word reported as wrong: its AI drafts in that sentence are no longer offered.
  void flagAiMeanings(String lemma, String sentence) =>
      db.execute("UPDATE ai_meaning SET status='flagged' WHERE lemma=? AND sentence=?", [lemma, sentence]);

  /// All reports as tab-separated text with a header line, for quality checks.
  String senseFeedbackTsv() {
    String clean(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[\t\r\n]+'), ' ');
    final out = StringBuffer('time\tword\tsentence\tsense_id\tshown_tr\tconfidence\tdict_version\tengine_version\tbook\twithdrawn\n');
    for (final r in db.select('SELECT * FROM sense_feedback ORDER BY id')) {
      out.writeln([
        DateTime.fromMillisecondsSinceEpoch(r['created'] as int).toIso8601String(),
        for (final k in ['word', 'sentence', 'sense_id', 'shown_tr', 'confidence', 'dict_version', 'engine_version', 'book']) clean(r[k]),
        // A withdrawn report is not an active error; the export says so.
        (r['withdrawn'] == 1 ? 'geri alındı' : 'aktif'),
      ].join('\t'));
    }
    return out.toString();
  }

  // ---- words the dictionary has no exact Turkish for (reported to the developer)
  void addMissing(String lemma, int? syn, String? gloss) => db.execute(
      'INSERT OR IGNORE INTO missing_tr(lemma, syn, gloss) VALUES (?,?,?)', [lemma, syn ?? 0, gloss]);

  List<({String lemma, int syn, String? gloss})> missingToReport() => [
        for (final r in db.select('SELECT lemma, syn, gloss FROM missing_tr WHERE reported=0 ORDER BY rowid'))
          (lemma: r['lemma'] as String, syn: r['syn'] as int, gloss: r['gloss'] as String?)
      ];

  void markMissingReported() => db.execute('UPDATE missing_tr SET reported=1 WHERE reported=0');

  // ---- AI expression details and sentence explanations
  String? exprDetail(String key) {
    final r = db.select('SELECT json FROM expr_detail WHERE key=?', [key]);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  void setExprDetail(String key, String json) =>
      db.execute('INSERT OR REPLACE INTO expr_detail(key, json) VALUES (?,?)', [key, json]);

  (String, String?)? sentenceAi(String sentence) {
    final r = db.select('SELECT tr, exp FROM sentence_ai WHERE sentence=?', [sentence]);
    return r.isEmpty ? null : (r.first['tr'] as String, r.first['exp'] as String?);
  }

  void setSentenceAi(String sentence, String tr, String? exp) =>
      db.execute('INSERT OR REPLACE INTO sentence_ai(sentence, tr, exp) VALUES (?,?,?)', [sentence, tr, exp]);

  // ---- AI word families
  String? familyAi(String word) {
    final r = db.select('SELECT json FROM wfam_ai WHERE word=?', [word]);
    return r.isEmpty ? null : r.first['json'] as String;
  }

  void setFamilyAi(String word, String json) =>
      db.execute('INSERT OR REPLACE INTO wfam_ai(word, json) VALUES (?,?)', [word, json]);

  /// Gives books with a machine-made title (a UUID file name) a title from
  /// their own text, and updates the saved words that name the old title.
  void repairBookTitles(bool Function(String title) generated,
      String Function(List<String> chapterTitles, List<(String, String)> firstParas) derive) {
    for (final r in db.select('SELECT id, title FROM books')) {
      final old = r['title'] as String? ?? '';
      if (!generated(old)) continue;
      final id = r['id'] as int;
      final titles = [for (final c in db.select('SELECT title FROM chapters WHERE book_id=? ORDER BY idx', [id])) c['title'] as String? ?? ''];
      final paras = [
        for (final p in db.select('SELECT kind, text FROM paras WHERE book_id=? ORDER BY chapter, idx LIMIT 8', [id]))
          (p['kind'] as String, p['text'] as String)
      ];
      final t = derive(titles, paras);
      if (t.isEmpty || t == old) continue;
      db.execute('UPDATE books SET title=? WHERE id=?', [t, id]);
      db.execute('UPDATE words SET book=? WHERE book=?', [t, old]);
    }
  }

  /// Once per device: splits glued words ("witha" -> "with a") in books
  /// imported from PDFs and images before the import fixed them itself.
  void repairJoinedWordsOnce(String Function(String text) fix) {
    const key = 'repair_joined_words_v1';
    if (getSetting(key) != null) return;
    final rows = db.select(
        "SELECT p.id, p.text FROM paras p JOIN books b ON b.id = p.book_id WHERE b.format IN ('pdf', 'image') AND p.kind != 'i'");
    db.execute('BEGIN');
    try {
      final upd = db.prepare('UPDATE paras SET text=? WHERE id=?');
      for (final r in rows) {
        final t = r['text'] as String? ?? '';
        final f = fix(t);
        if (f != t) upd.execute([f, r['id']]);
      }
      upd.close();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    setSetting(key, '1');
  }

  /// Once per device: text slips in books imported before the import
  /// repaired them itself (see text_repair.dart): hidden characters and
  /// symbol-font bullets in every book; broken words, "uEven", "pOOr",
  /// "mormng", "overwhelmn" in books from PDFs and pictures.
  /// [fix] gets a paragraph and its book's format.
  void repairImportedTextOnce(String Function(String text, String format) fix) {
    const key = 'repair_imported_text_v1';
    if (getSetting(key) != null) return;
    final rows = db.select("SELECT p.id, p.text, b.format FROM paras p JOIN books b ON b.id = p.book_id WHERE p.kind != 'i'");
    db.execute('BEGIN');
    try {
      final upd = db.prepare('UPDATE paras SET text=? WHERE id=?');
      for (final r in rows) {
        final t = r['text'] as String? ?? '';
        final f = fix(t, r['format'] as String? ?? '');
        if (f != t && f.isNotEmpty) upd.execute([f, r['id']]);
      }
      upd.close();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    setSetting(key, '1');
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
  /// The language of a book's text: 'tr' when Turkish letters are common in
  /// it (ç ğ ı ö ş ü), otherwise 'en'.
  static String textLang(ImportedBook b) {
    var letters = 0, tr = 0;
    for (final c in b.chapters) {
      for (final (kind, text) in c.paragraphs) {
        if (kind == 'i') continue;
        for (final r in text.runes) {
          if (_trLetters.contains(r)) {
            tr++;
            letters++;
          } else if (r >= 65 && r <= 90 || r >= 97 && r <= 122) {
            letters++;
          }
        }
        if (letters > 20000) break;
      }
      if (letters > 20000) break;
    }
    return letters > 0 && tr / letters > 0.01 ? 'tr' : 'en';
  }

  static final _trLetters = 'çğıöşüÇĞİÖŞÜ'.runes.toSet();

  int insertBook(ImportedBook b, {String? source, String? lang}) {
    db.execute('BEGIN');
    try {
      db.execute('INSERT INTO books(title, author, format, chapters, added, source, lang) VALUES (?,?,?,?,?,?,?)',
          [b.title, b.author, b.format, b.chapters.length, DateTime.now().millisecondsSinceEpoch, source, lang ?? textLang(b)]);
      final id = db.lastInsertRowId;
      // Pictures go to books/<id>/ in the app folder.
      final imgDir = p.join('books', '$id');
      if (b.images.isNotEmpty) Directory(p.join(dir, imgDir)).createSync(recursive: true);
      for (final e in b.images.entries) {
        File(p.join(dir, imgDir, e.key)).writeAsBytesSync(e.value);
      }
      final ch = db.prepare('INSERT INTO chapters(book_id, idx, title) VALUES (?,?,?)');
      final pa = db.prepare('INSERT INTO paras(book_id, chapter, idx, kind, text, meta) VALUES (?,?,?,?,?,?)');
      for (var c = 0; c < b.chapters.length; c++) {
        ch.execute([id, c, b.chapters[c].title]);
        final ps = b.chapters[c].paragraphs;
        var n = 0;
        for (var i = 0; i < ps.length; i++) {
          final m = b.chapters[c].metaAt(i);
          var text = ps[i].$2;
          if (ps[i].$1 == 'i') {
            if (!b.images.containsKey(text)) continue; // a picture that was not kept
            text = p.posix.join('books', '$id', text);
          }
          pa.execute([id, c, n++, ps[i].$1, text, m == null || m.isEmpty ? null : jsonEncode(m)]);
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

  /// Books in [lang], by default the language being learned.
  List<Book> books({String? lang}) => [
        for (final r in db.select("SELECT * FROM books WHERE coalesce(lang, 'en')=? ORDER BY added DESC", [lang ?? _lang]))
          Book(r['id'] as int, r['title'] as String, r['author'] as String?, r['format'] as String,
              r['chapters'] as int, r['last_chapter'] as int, r['last_para'] as int,
              DateTime.fromMillisecondsSinceEpoch(r['added'] as int),
              source: r['source'] as String?, lastPage: (r['last_page'] as int?) ?? 0)
      ];

  /// Free-library item id → the book made from it.
  /// How many pictures the book has.
  int pictureCount(int bookId) => db.select("SELECT COUNT(*) AS n FROM paras WHERE book_id=? AND kind='i'", [bookId]).first['n'] as int;

  Map<String, Book> booksBySource() => {for (final b in books()) if (b.source != null) b.source!: b};

  void deleteBook(int id) {
    db.execute('DELETE FROM paras WHERE book_id=?', [id]);
    db.execute('DELETE FROM chapters WHERE book_id=?', [id]);
    db.execute('DELETE FROM books WHERE id=?', [id]);
    try {
      final d = Directory(p.join(dir, 'books', '$id'));
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Number of pages of the original book (a PDF), null when it has none.
  int? bookPages(int bookId) {
    try {
      final r = db.select("SELECT MAX(CAST(json_extract(meta, '\$.pg') AS INTEGER)) AS m FROM paras WHERE book_id=?", [bookId]);
      final m = r.first['m'] as int?;
      return m == null ? null : m + 1;
    } catch (_) {
      return null;
    }
  }

  /// A picture's file on this device.
  File imageFile(Para para) => File(p.join(dir, para.text));

  /// The book's cover: a picture at the very start of the book (most books
  /// open with their cover), when its file is there. Null otherwise.
  File? coverFile(int bookId) {
    final r = db.select(
      "SELECT text, meta FROM paras WHERE book_id=? AND kind='i' AND chapter=(SELECT MIN(chapter) FROM paras WHERE book_id=?) "
      'AND idx < 4 ORDER BY idx LIMIT 1',
      [bookId, bookId],
    );
    if (r.isEmpty) return null;
    final meta = r.first['meta'] == null ? const {} : jsonDecode(r.first['meta'] as String) as Map;
    // A PDF's picture must be on its first page; a small icon is no cover.
    if ((meta['pg'] as int? ?? 0) > 0) return null;
    final ar = (meta['ar'] as num?)?.toDouble();
    if (ar != null && (ar < 0.45 || ar > 1.1)) return null;
    final f = File(p.join(dir, r.first['text'] as String));
    return f.existsSync() ? f : null;
  }

  void saveProgress(int bookId, int chapter, int para, {int page = 0}) =>
      db.execute('UPDATE books SET last_chapter=?, last_para=?, last_page=? WHERE id=?', [chapter, para, page, bookId]);

  List<Chapter> chapters(int bookId) => [
        for (final r in db.select('SELECT idx, title, summary FROM chapters WHERE book_id=? ORDER BY idx', [bookId]))
          Chapter(r['idx'] as int, r['title'] as String, r['summary'] as String?)
      ];

  /// The whole book as plain text, the way the reader shows it: chapter titles,
  /// headings and paragraphs separated by blank lines, picture captions in brackets.
  String bookText(int bookId) {
    final b = db.select('SELECT title, author FROM books WHERE id=?', [bookId]);
    final out = StringBuffer();
    if (b.isNotEmpty) {
      out.writeln(b.first['title']);
      if (b.first['author'] != null) out.writeln(b.first['author']);
      out.writeln();
    }
    for (final c in chapters(bookId)) {
      out
        ..writeln()
        ..writeln('## ${c.title}')
        ..writeln();
      out.write(chapterText(bookId, c.idx));
    }
    return out.toString();
  }

  /// One chapter as plain text.
  String chapterText(int bookId, int chapter) {
    final out = StringBuffer();
    for (final p in paras(bookId, chapter)) {
      if (p.kind == 'i') continue;
      out
        ..writeln(p.kind == 'c' ? '[${p.text}]' : p.text)
        ..writeln();
    }
    return out.toString();
  }

  List<Para> paras(int bookId, int chapter) => [
        for (final r in db.select(
            'SELECT id, idx, kind, text, meta FROM paras WHERE book_id=? AND chapter=? ORDER BY idx', [bookId, chapter]))
          Para(r['id'] as int, r['idx'] as int, r['kind'] as String, r['text'] as String,
              r['meta'] == null ? const {} : (jsonDecode(r['meta'] as String) as Map<String, dynamic>))
      ];

  /// Sentence translations stored by the online analysis, each tied to its
  /// English sentence (see sentence_translation.dart). Null when none.
  ParaTranslations? paraTranslation(int paraId) {
    final r = db.select('SELECT tr FROM paras WHERE id=?', [paraId]);
    return ParaTranslations.decode(r.isEmpty ? null : r.first['tr'] as String?);
  }

  void setParaTranslation(int paraId, ParaTranslations tr) =>
      db.execute('UPDATE paras SET tr=? WHERE id=?', [tr.encode(), paraId]);

  void setChapterSummary(int bookId, int idx, String summary) =>
      db.execute('UPDATE chapters SET summary=? WHERE book_id=? AND idx=?', [summary, bookId, idx]);

  List<({int id, String text})> parasMissingTranslation(int bookId) => [
        for (final r in db.select(
            "SELECT id, text FROM paras WHERE book_id=? AND tr IS NULL AND kind != 'i' ORDER BY chapter, idx", [bookId]))
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
    final k = key(lemma);
    if (status == WordStatus.none) {
      db.execute('DELETE FROM words WHERE lemma=?', [k]);
      statuses.remove(lemma);
      return;
    }
    final exists = db.select('SELECT 1 FROM words WHERE lemma=?', [k]).isNotEmpty;
    if (exists) {
      db.execute('UPDATE words SET status=? WHERE lemma=?', [status.index, k]);
    } else {
      db.execute('INSERT INTO words VALUES (?,?,?,?,?,?)',
          [k, status.index, context, book, meaning, DateTime.now().millisecondsSinceEpoch]);
    }
    statuses[lemma] = status;
  }

  /// Saved words of the language being learned.
  List<SavedWord> words(WordStatus status) => [
        for (final r in db.select('SELECT * FROM words WHERE status=? AND ($_langWhere) ORDER BY added DESC', [status.index]))
          SavedWord((r['lemma'] as String).substring(_prefix.length), status, r['context'] as String?, r['book'] as String?,
              r['meaning'] as String?, DateTime.fromMillisecondsSinceEpoch(r['added'] as int))
      ];
}

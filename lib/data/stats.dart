import 'review.dart';
import 'user_db.dart';

/// Personal statistics, kept on the device only. Nothing here is sent anywhere.
///
/// The tables only record what happens from now on. Older numbers that the app
/// never measured (reading time, lookups, grammar answers) are not made up: the
/// journey screen says since when each number is measured.
class StatsStore {
  final UserDb user;

  StatsStore(this.user) {
    user.db.execute('''
      CREATE TABLE IF NOT EXISTS reading_time(day TEXT, book_id INTEGER, seconds INTEGER, PRIMARY KEY(day, book_id));
      CREATE TABLE IF NOT EXISTS read_para(book_id INTEGER, chapter INTEGER, idx INTEGER, words INTEGER, day TEXT,
        PRIMARY KEY(book_id, chapter, idx));
      CREATE TABLE IF NOT EXISTS lookup_log(id INTEGER PRIMARY KEY, created INTEGER, kind TEXT, key TEXT);
      CREATE TABLE IF NOT EXISTS review_log(id INTEGER PRIMARY KEY, created INTEGER, lemma TEXT, answer TEXT, graduated INTEGER);
      CREATE TABLE IF NOT EXISTS grammar_attempt(id INTEGER PRIMARY KEY, created INTEGER, topic TEXT, exercise TEXT, right INTEGER);
    ''');
    if (user.getSetting(_sinceKey) == null) {
      user.setSetting(_sinceKey, DateTime.now().millisecondsSinceEpoch.toString());
    }
  }

  static const _sinceKey = 'stats_since';
  static const _deletedWordsKey = 'stats_deleted_book_words';

  /// When the app started measuring time, lookups and answers on this device.
  DateTime get since => DateTime.fromMillisecondsSinceEpoch(int.tryParse(user.getSetting(_sinceKey) ?? '') ?? 0);

  // ---- reading time

  void addReadingSeconds(int bookId, int seconds, {DateTime? now}) {
    if (seconds <= 0) return;
    user.db.execute('''
      INSERT INTO reading_time(day, book_id, seconds) VALUES (?,?,?)
      ON CONFLICT(day, book_id) DO UPDATE SET seconds = seconds + excluded.seconds
    ''', [ReviewStore.dayKey(now ?? DateTime.now()), bookId, seconds]);
  }

  /// Seconds read from [from] (a day, inclusive) on; all days when null. Only [bookId] when given.
  /// [before] (a day, exclusive) limits the range at the other end.
  int readingSeconds({DateTime? from, DateTime? before, int? bookId}) {
    final where = <String>[], args = <Object>[];
    if (from != null) {
      where.add('day >= ?');
      args.add(ReviewStore.dayKey(from));
    }
    if (before != null) {
      where.add('day < ?');
      args.add(ReviewStore.dayKey(before));
    }
    if (bookId != null) {
      where.add('book_id = ?');
      args.add(bookId);
    }
    final r = user.db.select('SELECT COALESCE(SUM(seconds), 0) AS s FROM reading_time${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}', args);
    return r.first['s'] as int;
  }

  /// Seconds read on each of the last [days] days, oldest first, ending [now].
  List<(DateTime, int)> readingByDay(int days, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final end = DateTime(n.year, n.month, n.day);
    final from = end.subtract(Duration(days: days - 1));
    final by = {
      for (final r in user.db.select('SELECT day, SUM(seconds) AS s FROM reading_time WHERE day >= ? GROUP BY day', [ReviewStore.dayKey(from)]))
        r['day'] as String: r['s'] as int,
    };
    return [
      for (var i = 0; i < days; i++)
        (from.add(Duration(days: i)), by[ReviewStore.dayKey(from.add(Duration(days: i)))] ?? 0),
    ];
  }

  /// Dictionary lookups on each of the last [days] days, oldest first.
  List<(DateTime, int)> lookupsByDay(int days, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final end = DateTime(n.year, n.month, n.day);
    final from = end.subtract(Duration(days: days - 1));
    final counts = List.filled(days, 0);
    for (final r in user.db.select('SELECT created FROM lookup_log WHERE created >= ?', [from.millisecondsSinceEpoch])) {
      final d = DateTime.fromMillisecondsSinceEpoch(r['created'] as int);
      final i = DateTime(d.year, d.month, d.day).difference(from).inDays;
      if (i >= 0 && i < days) counts[i]++;
    }
    return [for (var i = 0; i < days; i++) (from.add(Duration(days: i)), counts[i])];
  }

  /// Distinct days with any reading time.
  int readingDays() => user.db.select('SELECT COUNT(DISTINCT day) AS n FROM reading_time WHERE seconds > 0').first['n'] as int;

  /// Last day [bookId] was read, from the reading time.
  String? lastReadDay(int bookId) =>
      user.db.select('SELECT MAX(day) AS d FROM reading_time WHERE book_id = ?', [bookId]).first['d'] as String?;

  // ---- words read (an estimate: every paragraph the reader reached counts once)

  /// Counts the paragraphs [fromIdx]..[toIdx] of a chapter as read. A paragraph read
  /// again is not counted twice.
  void markRead(int bookId, int chapter, List<Para> paras, int toIdx, {DateTime? now}) {
    if (paras.isEmpty || toIdx < 0) return;
    final day = ReviewStore.dayKey(now ?? DateTime.now());
    final st = user.db.prepare('INSERT OR IGNORE INTO read_para(book_id, chapter, idx, words, day) VALUES (?,?,?,?,?)');
    try {
      for (final p in paras) {
        if (p.idx > toIdx) break;
        if (p.kind == 'c') continue;
        st.execute([bookId, chapter, p.idx, countWords(p.text), day]);
      }
    } finally {
      st.close();
    }
  }

  int wordsRead({int? bookId}) {
    final r = bookId == null
        ? user.db.select('SELECT COALESCE(SUM(words), 0) AS w FROM read_para')
        : user.db.select('SELECT COALESCE(SUM(words), 0) AS w FROM read_para WHERE book_id = ?', [bookId]);
    return (r.first['w'] as int) + (bookId == null ? (int.tryParse(user.getSetting(_deletedWordsKey) ?? '') ?? 0) : 0);
  }

  final _bookWords = <int, int>{};

  /// Text words in the whole book (captions not counted). A book's text does not change.
  int bookWords(int bookId) => _bookWords[bookId] ??= _countBook(bookId);

  int _countBook(int bookId) {
    var n = 0;
    for (final r in user.db.select("SELECT text FROM paras WHERE book_id = ? AND kind != 'c'", [bookId])) {
      n += countWords(r['text'] as String);
    }
    return n;
  }

  /// Before a book is removed: its words read stay in the total, its rows go, so a
  /// new book that gets the same id starts from zero. Reading time stays (book 0).
  void forgetBook(int bookId) {
    final w = wordsRead(bookId: bookId);
    if (w > 0) {
      final old = int.tryParse(user.getSetting(_deletedWordsKey) ?? '') ?? 0;
      user.setSetting(_deletedWordsKey, '${old + w}');
    }
    _bookWords.remove(bookId);
    user.db.execute('DELETE FROM read_para WHERE book_id = ?', [bookId]);
    user.db.execute('''
      INSERT INTO reading_time(day, book_id, seconds) SELECT day, 0, seconds FROM reading_time WHERE book_id = ?
      ON CONFLICT(day, book_id) DO UPDATE SET seconds = seconds + excluded.seconds
    ''', [bookId]);
    user.db.execute('DELETE FROM reading_time WHERE book_id = ?', [bookId]);
  }

  static final _word = RegExp(r"[A-Za-zÀ-ÿ]+(?:['’][A-Za-z]+)?");
  static int countWords(String s) => _word.allMatches(s).length;

  // ---- dictionary lookups

  void logLookup(String kind, String key, {DateTime? now}) => user.db.execute(
      'INSERT INTO lookup_log(created, kind, key) VALUES (?,?,?)', [(now ?? DateTime.now()).millisecondsSinceEpoch, kind, key.toLowerCase()]);

  int lookups({DateTime? from}) => user.db.select('SELECT COUNT(*) AS n FROM lookup_log WHERE created >= ?',
      [from?.millisecondsSinceEpoch ?? 0]).first['n'] as int;

  int uniqueLookups() => user.db.select('SELECT COUNT(DISTINCT kind || key) AS n FROM lookup_log').first['n'] as int;

  /// Meanings the learner asked the AI for in the reader (the background analysis
  /// of whole books is not counted: nobody asked for those one by one).
  int aiExplained() => user.db.select('SELECT COUNT(*) AS n FROM ai_meaning').first['n'] as int;

  // ---- reviews

  void logReview(String lemma, String answer, bool graduated, {DateTime? now}) => user.db.execute(
      'INSERT INTO review_log(created, lemma, answer, graduated) VALUES (?,?,?,?)',
      [(now ?? DateTime.now()).millisecondsSinceEpoch, lemma, answer, graduated ? 1 : 0]);

  /// All reviews ever answered (the daily review counter existed before this table).
  int reviewsTotal() => user.db.select('SELECT COALESCE(SUM(reviewed), 0) AS n FROM activity').first['n'] as int;

  /// (answered, known) since the review log started.
  (int, int) reviewSuccess() {
    final r = user.db.select("SELECT COUNT(*) AS n, COALESCE(SUM(answer != 'again'), 0) AS ok FROM review_log").first;
    return (r['n'] as int, r['ok'] as int);
  }

  /// Words that reached "Learned" through the reviews (not marked by hand).
  int learnedByReview({DateTime? from}) => user.db.select(
      'SELECT COUNT(DISTINCT lemma) AS n FROM review_log WHERE graduated = 1 AND created >= ?',
      [from?.millisecondsSinceEpoch ?? 0]).first['n'] as int;

  // ---- grammar answers (every answer is kept; nothing is overwritten)

  void logGrammar(String topic, String exercise, bool right, {DateTime? now}) => user.db.execute(
      'INSERT INTO grammar_attempt(created, topic, exercise, right) VALUES (?,?,?,?)',
      [(now ?? DateTime.now()).millisecondsSinceEpoch, topic, exercise, right ? 1 : 0]);

  /// topic → (answered, right), from [from] on.
  Map<String, (int, int)> grammarByTopic({DateTime? from}) => {
        for (final r in user.db.select(
            'SELECT topic, COUNT(*) AS n, SUM(right) AS ok FROM grammar_attempt WHERE created >= ? GROUP BY topic',
            [from?.millisecondsSinceEpoch ?? 0]))
          r['topic'] as String: (r['n'] as int, r['ok'] as int),
      };
}

/// Counts active reading time. Time counts only while the reader is on screen, the
/// app is in the foreground, and the reader was used (scroll, tap, read aloud) within
/// [idleLimit]. A long pause counts at most [idleLimit] after the last use.
class ActiveTimer {
  final Duration idleLimit;
  final DateTime Function() clock;
  ActiveTimer({this.idleLimit = const Duration(minutes: 2), DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  bool _foreground = true;
  DateTime? _lastUse;
  DateTime? _countedTo;
  int _pending = 0;

  /// The reader was used: scroll, tap, key, or read aloud still speaking.
  void touch() {
    _settle();
    final now = clock();
    final last = _lastUse;
    // After a pause longer than the limit, counting starts again from now.
    if (last == null || _countedTo == null || now.difference(last) > idleLimit) _countedTo = now;
    _lastUse = now;
  }

  void setForeground(bool v) {
    _settle();
    _foreground = v;
    // Coming back counts nothing until the reader is used again.
    _lastUse = null;
    _countedTo = null;
  }

  void _settle() {
    final last = _lastUse, from = _countedTo;
    if (!_foreground || last == null || from == null) return;
    final now = clock();
    final end = now.isBefore(last.add(idleLimit)) ? now : last.add(idleLimit);
    final secs = end.difference(from).inSeconds;
    if (secs > 0) {
      _pending += secs;
      _countedTo = from.add(Duration(seconds: secs));
    }
  }

  /// Seconds counted since the last call. Each second is returned once.
  int take() {
    _settle();
    final s = _pending;
    _pending = 0;
    return s;
  }
}

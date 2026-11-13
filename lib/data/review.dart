import 'user_db.dart';

/// One card in a review session.
class ReviewCard {
  final SavedWord word;
  final int box;
  ReviewCard(this.word, this.box);
}

enum ReviewAnswer { again, hard, good }

/// Spaced repetition for the "To learn" list (Leitner boxes).
///
/// A word starts in box 0 and is due right away. "I know it" moves it up a
/// box and the next review is further away; "Again" puts it back to box 0.
/// After the last box the word is marked as learned.
class ReviewStore {
  final UserDb user;

  /// Days until the next review for each box.
  static const intervals = [0, 1, 3, 7, 14, 30];

  ReviewStore(this.user) {
    user.db.execute('''
      CREATE TABLE IF NOT EXISTS review(lemma TEXT PRIMARY KEY, box INTEGER, due INTEGER, reps INTEGER, lapses INTEGER);
      CREATE TABLE IF NOT EXISTS activity(day TEXT PRIMARY KEY, reviewed INTEGER);
    ''');
  }

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, (int box, int due)> _state() => {
        for (final r in user.db.select('SELECT lemma, box, due FROM review'))
          r['lemma'] as String: (r['box'] as int, r['due'] as int),
      };

  /// Words on the "To learn" list whose review is due, oldest first.
  List<ReviewCard> due({DateTime? now, int? limit}) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final st = _state();
    final out = <(int, ReviewCard)>[];
    for (final w in user.words(WordStatus.learning).reversed) {
      final s = st[w.lemma];
      final due = s?.$2 ?? w.added.millisecondsSinceEpoch;
      if (due <= t) out.add((due, ReviewCard(w, s?.$1 ?? 0)));
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    final cards = out.map((e) => e.$2).toList();
    return limit == null || cards.length <= limit ? cards : cards.sublist(0, limit);
  }

  int dueCount() => due().length;

  /// Records an answer. Returns true when the word graduated to "Learned".
  bool answer(String lemma, int box, ReviewAnswer a, {DateTime? now}) {
    final n = now ?? DateTime.now();
    var nb = switch (a) {
      ReviewAnswer.again => 0,
      ReviewAnswer.hard => box,
      ReviewAnswer.good => box + 1,
    };
    var graduated = false;
    if (nb >= intervals.length) {
      graduated = true;
      nb = intervals.length - 1;
    }
    final days = a == ReviewAnswer.again ? 0 : (a == ReviewAnswer.hard ? intervals[nb].clamp(1, 30) : intervals[nb]);
    final due = a == ReviewAnswer.again
        ? n.add(const Duration(minutes: 10))
        : DateTime(n.year, n.month, n.day).add(Duration(days: days, hours: 4));
    user.db.execute('''
      INSERT INTO review(lemma, box, due, reps, lapses) VALUES (?,?,?,1,?)
      ON CONFLICT(lemma) DO UPDATE SET box=excluded.box, due=excluded.due, reps=reps+1, lapses=lapses+excluded.lapses
    ''', [lemma, nb, due.millisecondsSinceEpoch, a == ReviewAnswer.again ? 1 : 0]);
    user.db.execute('''
      INSERT INTO activity(day, reviewed) VALUES (?,1)
      ON CONFLICT(day) DO UPDATE SET reviewed=reviewed+1
    ''', [dayKey(n)]);
    if (graduated) user.db.execute('DELETE FROM review WHERE lemma=?', [lemma]);
    return graduated;
  }

  int reviewedOn(DateTime d) {
    final r = user.db.select('SELECT reviewed FROM activity WHERE day=?', [dayKey(d)]);
    return r.isEmpty ? 0 : r.first['reviewed'] as int;
  }

  /// Days in a row with at least one review, counting today or yesterday.
  int streak({DateTime? now}) {
    final days = {for (final r in user.db.select('SELECT day FROM activity WHERE reviewed>0')) r['day'] as String};
    var d = now ?? DateTime.now();
    d = DateTime(d.year, d.month, d.day);
    if (!days.contains(dayKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(dayKey(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  /// Reviews per day for the last [n] days, oldest first.
  List<int> lastDays(int n, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return [for (var i = n - 1; i >= 0; i--) reviewedOn(DateTime(t.year, t.month, t.day - i))];
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/review.dart';
import 'package:kelime_okur/data/user_db.dart';

void main() {
  test('spaced repetition boxes and streak', () {
    final u = UserDb.open(Directory.systemTemp.createTempSync('rv'));
    final r = ReviewStore(u);
    u.setWord('narrow', WordStatus.learning);
    u.setWord('storm', WordStatus.learning);
    final now = DateTime.now().add(const Duration(seconds: 1));
    expect(r.due(now: now).map((c) => c.word.lemma).toSet(), {'narrow', 'storm'});

    // "Got it" moves the word up a box and out of today's queue.
    expect(r.answer('narrow', 0, ReviewAnswer.good, now: now), isFalse);
    expect(r.due(now: now).map((c) => c.word.lemma), ['storm']);
    expect(r.due(now: now.add(const Duration(days: 2))).map((c) => c.word.lemma).toSet(), {'narrow', 'storm'});

    // "Again" brings it back in ten minutes.
    r.answer('storm', 0, ReviewAnswer.again, now: now);
    expect(r.due(now: now.add(const Duration(minutes: 11))).map((c) => c.word.lemma), ['storm']);

    // Answering from the last box graduates the word.
    expect(r.answer('narrow', ReviewStore.intervals.length - 1, ReviewAnswer.good, now: now), isTrue);

    expect(r.streak(now: now), 1);
    expect(r.streak(now: now.add(const Duration(days: 1))), 1);
    expect(r.streak(now: now.add(const Duration(days: 2))), 0);
    expect(r.lastDays(7, now: now).last, 3);
  });
}

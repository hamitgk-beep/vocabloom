// Learner data around the context-meaning card: reports, withdrawal, the
// "I don't understand" request and AI drafts. Everything is local; the old
// database format must open and keep its rows.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vocabloom_fb'));
  tearDown(() => dir.deleteSync(recursive: true));

  int addReport(UserDb u, {String word = 'know', String sentence = 'I know her very well.'}) => u.addSenseFeedback(
      word: word, sentence: sentence, senseId: 'wn:1', shownTr: 'tanımak', confidence: 'sure', dictVersion: '26', engineVersion: '1');

  test('a second report for the same word and sentence is not added again', () {
    final u = UserDb.open(dir);
    final a = addReport(u);
    final b = addReport(u);
    expect(b, a);
    expect(u.senseFeedbackCount(), 1);
  });

  test('withdrawing keeps the row, marks it, and a new report is a new row', () {
    final u = UserDb.open(dir);
    final id = addReport(u);
    u.withdrawSenseFeedback(id);
    expect(u.activeSenseFeedbackId('know', 'I know her very well.'), isNull);
    expect(u.senseFeedbackCount(), 1, reason: 'nothing is deleted');
    final tsv = u.senseFeedbackTsv().trim().split('\n');
    expect(tsv.first.endsWith('\twithdrawn'), isTrue);
    expect(tsv.last.endsWith('geri alındı'), isTrue);
    final again = addReport(u);
    expect(again, isNot(id));
    expect(u.senseFeedbackCount(), 2);
    expect(tsv.first, startsWith('time\tword\tsentence\tsense_id\tshown_tr\tconfidence\tdict_version\tengine_version'));
  });

  test('the report and the "I don\'t understand" request are still there after a restart', () {
    var u = UserDb.open(dir);
    addReport(u);
    u.markSenseHelp('know', 'I know her very well.');
    u.db.dispose();
    u = UserDb.open(dir);
    expect(u.activeSenseFeedbackId('know', 'I know her very well.'), isNotNull);
    expect(u.senseHelpShown('know', 'I know her very well.'), isTrue);
    expect(u.senseHelpShown('know', 'another sentence'), isFalse);
    u.markSenseHelp('know', 'I know her very well.'); // a second request is not an error
  });

  test('AI drafts are kept per sentence, never empty, and flagged ones are not offered again', () {
    final u = UserDb.open(dir);
    const s = 'Cracks run through the wall.';
    u.saveAiMeaning(sentence: s, phrase: 'run through', cat: 'phrasal_verbs', lemma: 'run', tr: 'bir yerden geçmek', model: 'key',
        dictVersion: '26', engineVersion: '1');
    expect(u.aiMeaning(s, 'run through', 'phrasal_verbs'), 'bir yerden geçmek');
    expect(u.aiMeaning('Another sentence.', 'run through', 'phrasal_verbs'), isNull, reason: 'the draft belongs to its sentence');
    u.saveAiMeaning(sentence: 'Empty.', phrase: 'x', cat: 'word', lemma: 'x', tr: '  ', dictVersion: '26', engineVersion: '1');
    expect(u.aiMeaning('Empty.', 'x', 'word'), isNull);
    u.flagAiMeanings('run', s);
    expect(u.aiMeaning(s, 'run through', 'phrasal_verbs'), isNull);
  });

  test('an old database (no withdrawn column) opens and keeps its reports', () {
    final path = p.join(dir.path, 'user.db');
    final old = sqlite3.open(path);
    old.execute('''
      CREATE TABLE sense_feedback(id INTEGER PRIMARY KEY, created INTEGER, word TEXT, sentence TEXT,
        sense_id TEXT, shown_tr TEXT, confidence TEXT, dict_version TEXT, engine_version TEXT, book TEXT);
      INSERT INTO sense_feedback(created, word, sentence, sense_id, shown_tr, confidence, dict_version, engine_version, book)
        VALUES (1, 'know', 'I know the answer.', 'wn:9', 'bilmek', 'sure', '25', '1', 'Kitap');
    ''');
    old.dispose();
    final u = UserDb.open(dir);
    expect(u.senseFeedbackCount(), 1);
    expect(u.activeSenseFeedbackId('know', 'I know the answer.'), isNotNull, reason: 'an old report stays active');
    final tsv = u.senseFeedbackTsv().trim().split('\n');
    expect(tsv.last.endsWith('\taktif'), isTrue);
  });
}

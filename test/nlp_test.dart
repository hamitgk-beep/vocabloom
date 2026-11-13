import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/user_db.dart';
import 'package:kelime_okur/import/importers.dart';
import 'package:kelime_okur/nlp/grammar.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

DictDb openDict() {
  final d = DictDb();
  d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  return d;
}

void main() {
  final d = openDict();

  test('lemmatizer', () {
    expect(d.lemmatizer.lemmas('ran').first, 'run');
    expect(d.lemmatizer.lemmas('running').first, 'run');
    expect(d.lemmatizer.lemmas('stopped').first, 'stop');
    expect(d.lemmatizer.lemmas('children').first, 'child');
    expect(d.lemmatizer.lemmas('news').first, 'news');
    expect(d.lemmatizer.lemmas('decisions').first, 'decision');
  });

  test('phrase matching', () {
    String cats(String s) {
      final ms = d.matcher.match(tokenize(s));
      return ms.map((m) => '${m.expr.cat}:${m.expr.phrase}').toSet().join(', ');
    }

    final a = cats('She finally gave it up, although she had made a decision to break the ice.');
    print(a);
    expect(a, contains('phrasal_verbs:give up'));
    expect(a, contains('conjunctions:although'));
    expect(a, contains('collocations:make a decision'));
    expect(a, contains('idioms:break the ice'));
    final b = cats('By the way, he lost his temper and looked forward to the trip.');
    print(b);
    expect(b, contains('discourse_markers:by the way'));
    expect(b, contains("collocations:lose one's temper"));
    expect(b, contains('phrasal_verbs:look forward to'));
  });

  test('sense choice', () {
    final s = tokenize('He deposited the money in the bank and asked for a loan.');
    final best = d.bestSense(d.lookup('bank'), s, 6)!;
    print(best.gloss);
    expect(best.gloss, contains('financial'));
    final s2 = tokenize('They sat on the bank of the river and watched the water.');
    final b2 = d.bestSense(d.lookup('bank'), s2, 4)!;
    print(b2.gloss);
  });

  test('tenses', () {
    final td = TenseDetector(d.lemmatizer, {'went', 'saw', 'gave'}, {'gone', 'seen', 'given', 'written', 'known', 'come'});
    String t(String s) => td.detect(tokenize(s)).map((h) => h.en).join(', ');
    print(t('I have been waiting for hours.'));
    expect(t('I have been waiting for hours.'), contains('Present Perfect Continuous'));
    expect(t('She will have finished by noon.'), contains('Future Perfect'));
    expect(t('They were playing outside when it started to rain.'), contains('Past Continuous'));
    expect(t('The letter was written by my father.'), contains('Simple Past (Passive)'));
    expect(t('If I had known, I would have come.'), contains('Conditional'));
    expect(t('He went home early.'), contains('Simple Past'));
  });

  test('importers', () {
    final txt = importBytes('CHAPTER ONE\n\nIt was a cold morning.\n\nShe walked out.\n\nCHAPTER TWO\n\nThe end came.'.codeUnits, 'txt', 'x');
    expect(txt.chapters.length, 2);
    final rtf = importBytes(r'{\rtf1\ansi{\fonttbl{\f0 Arial;}}\f0 Hello \b world\b0 .\par Second para.}'.codeUnits, 'rtf', 'r');
    print(rtf.chapters.first.paragraphs);
    expect(rtf.chapters.first.paragraphs.first.$2, contains('Hello world'));
    final f = File('test/fixtures/sample.epub');
    if (f.existsSync()) {
      final e = importBytes(f.readAsBytesSync(), 'epub', 'e');
      print('${e.title} ${e.chapters.map((c) => '${c.title}:${c.paragraphs.length}').join(' | ')}');
      expect(e.chapters, isNotEmpty);
    }
  });

  test('dictionary: Wiktionary entries and saved AI translations', () {
    final idiom = d.exprs.firstWhere((e) => e.phrase == 'off the hook');
    expect(idiom.en, isNotNull);
    expect(d.exprs.where((e) => e.cat == 'idioms').length, greaterThan(3000));
    final dir = Directory.systemTemp.createTempSync('vb_user');
    final u = UserDb.open(dir);
    final e = d.exprs.firstWhere((x) => x.needsAi);
    u.setExprAi(e.phrase, e.cat, 'deneme', 'açıklama');
    final saved = u.exprAi()['${e.phrase}|${e.cat}'];
    expect(saved?.$1, 'deneme');
    expect(saved?.$2, 'açıklama');
    u.db.dispose();
    dir.deleteSync(recursive: true);
  });
}

// The hand-checked dictionary data (tools/contrib) is in both dictionaries:
// new meanings, examples shown first, meaning in context, new phrases.
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/app_state.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/data/tr_en_dict.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final tr = TrEnDict(sqlite3.open('assets/tr_en.db', mode: OpenMode.readOnly));
  final en = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);

  List<String> lemmasOf(String sentence) => [
        for (final w in RegExp(r"[a-zçğıöşüâîû]+").allMatches(TrEnDict.lower(sentence)).map((m) => m.group(0)!))
          if (tr.lemmas(w) case final l when l.isNotEmpty) l.first,
      ];

  test('Turkish: checked examples come first, new meanings carry their source', () {
    final e = tr.entry('sürmek')!;
    expect(e.examples.first.tr, 'Toplantı iki saat sürdü.');
    final kirmak = tr.entry('kırmak')!;
    final st = kirmak.senses.where((s) => s.source == 'st').expand((s) => s.glosses);
    expect(st, contains('to turn sharply, to swerve'));
  });

  test('Turkish: the sentence picks the meaning it was checked with', () {
    final kirmak = tr.entry('kırmak')!;
    final flat = kirmak.senses.expand((s) => s.glosses).toList();
    final g = tr.meaningInContext('kırmak', lemmasOf('Direksiyonu aniden sağa kırarak kazadan kurtuldu.'));
    expect(flat[g!], contains('swerve'));
  });

  test('Turkish: a new verb finds its forms, a phrase is in the dictionary', () {
    expect(tr.lemmas('bitirdim'), contains('bitirmek'));
    expect(tr.entry('kılı kırk yarmak')!.senses.first.glosses.first, contains('split hairs'));
  });

  test('English: a new meaning and a new phrase', () {
    expect(en.ownSenses('book').map((s) => s.tr), contains('sarı kart göstermek, ceza yazmak'));
    final r = en.db.select("SELECT tr FROM expr WHERE phrase = 'no pain, no gain'");
    expect(r.single['tr'], 'emek olmadan yemek olmaz');
    expect(en.examples('w:run').first.$1, 'She has been successfully running her own software company for five years.');
  });

  test('Second sheet: split meanings, fixed examples, new phrases', () {
    expect(en.ownSenses('dull').map((s) => s.tr), contains('kör'));
    expect(en.examples('w:maintain').first.$1, 'This hotel has maintained its high quality of service for years.');
    final r = en.db.select("SELECT tr FROM expr WHERE phrase = 'zero in on'");
    expect(r.single['tr'], 'tam üzerine odaklanmak, hedef almak');
    final st = tr.entry('akmak')!.senses.where((s) => s.source == 'st').expand((s) => s.glosses);
    expect(st, contains('to flow smoothly (traffic)'));
    expect(tr.entry('çorbada tuzu olmak'), isNotNull);
  });

  test('Filter sheet: new filters have their phrases, every filter has a category', () {
    final cats = en.db.select('SELECT DISTINCT cat FROM expr').map((r) => r['cat'] as String);
    for (final c in cats) {
      expect(categoryById[c], isNotNull, reason: c);
      expect(filterGroups.any((g) => g.$3.contains(c)), isTrue, reason: c);
    }
    String? tr(String phrase, String cat) =>
        en.db.select('SELECT tr FROM expr WHERE phrase = ? AND cat = ?', [phrase, cat]).firstOrNull?['tr'] as String?;
    expect(tr('interested in', 'dependent_prepositions'), '-e ilgi duyan');
    expect(tr('affect', 'confusables'), 'etkilemek (≠ effect: etki, sonuç)');
    expect(tr('lorry', 'uk_us'), 'kamyon (UK; US: truck)');
    expect(tr('as busy as a bee', 'similes'), 'arı gibi çalışkan');
    expect(tr('do', 'confusables'), isNull);
  });

  test('Third sheet: stand-in rows are left out, a phrasal verb keeps its own meaning', () {
    expect(tr.entry('tr_word_499'), isNull);
    expect(en.ownSenses('bring').map((s) => s.tr), isNot(contains('sebep olmak, yol açmak')));
    final st = tr.entry('tırmanmak')!.senses.where((s) => s.source == 'st').expand((s) => s.glosses);
    expect(st, contains('to escalate'));
  });
}

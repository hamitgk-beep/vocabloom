import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late DictDb d;
  setUpAll(() {
    d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
  });

  List<String> phrases(String s) => [
        for (final m in d.matcher.match(tokenize(s), text: s))
          if (m.tokens.length > 1) '${m.expr.phrase}${m.tokens}'
      ];

  test('phrasal verb split by a short object: turn the light off', () {
    expect(phrases('Please turn the light off.'), contains('turn off[1, 4]'));
    expect(phrases('Please turn off the light.'), contains('turn off[1, 2]'));
  });

  test('the particle may be followed by a new clause: turn the light off before you leave', () {
    expect(phrases('Please turn the light off before you leave.'), contains('turn off[1, 4]'));
    expect(phrases('Pick the toys up when you finish.'), contains('pick up[0, 3]'));
    expect(phrases('She put the book on the table before dinner.').where((x) => x.startsWith('put on')), isEmpty);
  });

  test('pick the cup up and turn the lights out', () {
    expect(phrases('He picked the cup up and left.'), contains('pick up[1, 4]'));
    expect(phrases('She turned the lights out and slept.'), contains('turn out[1, 4]'));
  });

  test('a normal word sequence is not a phrasal verb: put the book on the table', () {
    final p = phrases('She put the book on the table.');
    expect(p.where((x) => x.startsWith('put on')), isEmpty, reason: '$p');
    expect(p.where((x) => x.startsWith('put')), isEmpty, reason: '$p');
  });

  test('no split when the particle is not at the end of the clause', () {
    // "on" here starts a prepositional phrase, not the particle of "put on".
    expect(phrases('Put the book on the shelf in the hall.').where((x) => x.startsWith('put on')), isEmpty);
  });

  test('pronoun object keeps the existing split: turn it off (no new noun-object match)', () {
    expect(phrases('They turn it off.'), ['turn off[1, 3]']);
    expect(phrases('They turn off quickly.'), ['turn off[1, 2]']);
  });
}

// A misspelt word in a book ("overwhelmn") shows the closest dictionary word
// instead of "not found"; real words and names are left alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:kelime_okur/data/dict_db.dart';

late DictDb d;

void main() {
  setUpAll(() {
    d = DictDb();
    d.db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
    d.load();
  });

  test('typos find the intended word', () {
    expect(d.closestWord('overwhelmn'), 'overwhelm');
    expect(d.closestWord('recieve'), 'receive');
    expect(d.closestWord('beautifull'), 'beautiful');
    expect(d.closestWord('becuase'), 'because');
    expect(d.closestWord('enviroment'), 'environment');
  });

  test('known words, corpus words and short words are not corrected', () {
    expect(d.closestWord('overwhelm'), isNull);
    expect(d.closestWord('gonna'), isNull);
    expect(d.closestWord('teh'), isNull);
    expect(d.closestWord('qxzv'), isNull);
  });
}

// The phrases of the new filters (tools/contrib filter sheet) are found in a
// text: an inflected verb, a single word, a fixed comparison.
import 'package:flutter_test/flutter_test.dart';
import 'package:kelime_okur/data/dict_db.dart';
import 'package:kelime_okur/nlp/text.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  final d = DictDb()..db = sqlite3.open('assets/dict.db', mode: OpenMode.readOnly);
  d.load();
  List<String> found(String s, String cat) => [
        for (final m in d.matcher.match(tokenize(s), text: s))
          if (m.expr.cat == cat) m.expr.phrase
      ];

  test('each new filter finds its phrase', () {
    expect(found('She was interested in history.', 'dependent_prepositions'), contains('interested in'));
    expect(found('It depended on the weather.', 'dependent_prepositions'), contains('depend on'));
    expect(found('The cold weather affected the crops.', 'confusables'), contains('affect'));
    expect(found('He was as busy as a bee.', 'similes'), contains('as busy as a bee'));
    expect(found('Could you please close the window?', 'polite_phrases'), contains('could you please'));
    expect(found('The lorry arrived early.', 'uk_us'), contains('lorry'));
    expect(found('We hung out after class.', 'informal_slang'), contains('hang out'));
  });
}

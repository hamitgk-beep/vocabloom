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
    // Second sheet: a slot for the person, "be" in any form, a proverb.
    expect(found('They accused him of lying.', 'dependent_prepositions'), contains('accuse someone of'));
    expect(found('The village is famous for its olive oil.', 'dependent_prepositions'), contains('be famous for'));
    expect(found('Well, better late than never.', 'proverbs'), contains('better late than never'));
    // Third sheet: everyday chunks and discourse markers.
    expect(found('Hey Tom, long time no see!', 'chunks'), contains('long time no see'));
    expect(found("I'll get back to you tomorrow.", 'chunks'), contains("i'll get back to you"));
    expect(found('To be honest, I did not like the film.', 'discourse_markers'), contains('to be honest'));
  });
}
